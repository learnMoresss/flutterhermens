import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/network/jobs_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';

enum _ScheduleFrequency { minutes, hourly, daily, weekly, custom }

const _deliverOptions = [
  ('local', '本地'),
  ('origin', '来源端'),
  ('telegram', 'Telegram'),
  ('discord', 'Discord'),
  ('slack', 'Slack'),
  ('email', '邮件'),
  ('webhook', 'Webhook'),
  ('dingtalk', '钉钉'),
  ('feishu', '飞书'),
  ('wecom', '企业微信'),
];

class SchedulesPage extends ConsumerStatefulWidget {
  const SchedulesPage({super.key});

  @override
  ConsumerState<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends ConsumerState<SchedulesPage> {
  JobsAdminApi? _api;
  List<HermesCronJob> _jobs = const [];
  bool _loading = false;
  String? _error;
  String? _actionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _ensureApi() {
    _api = JobsAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load() async {
    _ensureApi();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await _api!.listJobs();
      if (mounted) setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String id, String action) async {
    _ensureApi();
    setState(() => _actionId = id);
    try {
      await _api!.jobAction(id, action);
      await _load();
      if (mounted) {
        AppMessage.success(action == 'run' ? '已触发执行' : action == 'pause' ? '已暂停' : '已恢复');
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  Future<void> _deleteJob(HermesCronJob job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${job.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    _ensureApi();
    setState(() => _actionId = job.id);
    try {
      await _api!.deleteJob(job.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    var frequency = _ScheduleFrequency.daily;
    var minutes = '30';
    var hourly = '1';
    var dailyTime = const TimeOfDay(hour: 9, minute: 0);
    var weeklyDay = 1;
    var weeklyTime = const TimeOfDay(hour: 9, minute: 0);
    var customCron = '';
    var deliver = 'local';

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            String buildSchedule() {
              switch (frequency) {
                case _ScheduleFrequency.minutes:
                  return '${minutes}m';
                case _ScheduleFrequency.hourly:
                  return '${hourly}h';
                case _ScheduleFrequency.daily:
                  return '${dailyTime.minute} ${dailyTime.hour} * * *';
                case _ScheduleFrequency.weekly:
                  return '${weeklyTime.minute} ${weeklyTime.hour} * * $weeklyDay';
                case _ScheduleFrequency.custom:
                  return customCron.trim();
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('新建计划任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '任务名称', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: promptCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '执行提示词', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_ScheduleFrequency>(
                      value: frequency,
                      decoration: const InputDecoration(labelText: '频率', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: _ScheduleFrequency.minutes, child: Text('每 N 分钟')),
                        DropdownMenuItem(value: _ScheduleFrequency.hourly, child: Text('每 N 小时')),
                        DropdownMenuItem(value: _ScheduleFrequency.daily, child: Text('每天')),
                        DropdownMenuItem(value: _ScheduleFrequency.weekly, child: Text('每周')),
                        DropdownMenuItem(value: _ScheduleFrequency.custom, child: Text('自定义 Cron')),
                      ],
                      onChanged: (v) => setLocal(() => frequency = v ?? frequency),
                    ),
                    const SizedBox(height: 8),
                    if (frequency == _ScheduleFrequency.minutes)
                      TextField(
                        decoration: const InputDecoration(labelText: '间隔（分钟）', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => minutes = v,
                      ),
                    if (frequency == _ScheduleFrequency.hourly)
                      TextField(
                        decoration: const InputDecoration(labelText: '间隔（小时）', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => hourly = v,
                      ),
                    if (frequency == _ScheduleFrequency.daily)
                      ListTile(
                        title: const Text('每天执行时间'),
                        subtitle: Text('${dailyTime.hour.toString().padLeft(2, '0')}:${dailyTime.minute.toString().padLeft(2, '0')}'),
                        trailing: const Icon(Icons.schedule),
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: dailyTime);
                          if (picked != null) setLocal(() => dailyTime = picked);
                        },
                      ),
                    if (frequency == _ScheduleFrequency.weekly) ...[
                      DropdownButtonFormField<int>(
                        value: weeklyDay,
                        decoration: const InputDecoration(labelText: '星期', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('周日')),
                          DropdownMenuItem(value: 1, child: Text('周一')),
                          DropdownMenuItem(value: 2, child: Text('周二')),
                          DropdownMenuItem(value: 3, child: Text('周三')),
                          DropdownMenuItem(value: 4, child: Text('周四')),
                          DropdownMenuItem(value: 5, child: Text('周五')),
                          DropdownMenuItem(value: 6, child: Text('周六')),
                        ],
                        onChanged: (v) => setLocal(() => weeklyDay = v ?? weeklyDay),
                      ),
                      ListTile(
                        title: const Text('执行时间'),
                        subtitle: Text('${weeklyTime.hour.toString().padLeft(2, '0')}:${weeklyTime.minute.toString().padLeft(2, '0')}'),
                        trailing: const Icon(Icons.schedule),
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: weeklyTime);
                          if (picked != null) setLocal(() => weeklyTime = picked);
                        },
                      ),
                    ],
                    if (frequency == _ScheduleFrequency.custom)
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Cron 表达式',
                          hintText: '分 时 日 月 周',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => customCron = v,
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: deliver,
                      decoration: const InputDecoration(labelText: '投递目标', border: OutlineInputBorder()),
                      items: _deliverOptions
                          .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                          .toList(growable: false),
                      onChanged: (v) => setLocal(() => deliver = v ?? deliver),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '计划：${buildSchedule()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray),
                    ),
                    const SizedBox(height: 16),
                    MonoButton(
                      label: '创建',
                      onPressed: () async {
                        final schedule = buildSchedule();
                        if (schedule.isEmpty) return;
                        _ensureApi();
                        try {
                          await _api!.createJob(
                            schedule: schedule,
                            name: nameCtrl.text.trim(),
                            prompt: promptCtrl.text.trim(),
                            deliver: deliver,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            AppMessage.error(e.message);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    promptCtrl.dispose();
    if (created == true) {
      await _load();
      if (mounted) {
        AppMessage.success('任务已创建');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '计划任务',
      showDivider: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/home/config'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              '定时向 Hermes 发送提示词，可按计划自动执行 Agent 任务。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
            ),
            const SizedBox(height: 16),
            MonoButton(label: '新建任务', onPressed: _showCreateDialog),
            const SizedBox(height: 8),
            MonoButton(label: _loading ? '刷新中…' : '刷新列表', outlined: true, onPressed: _loading ? null : _load),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            const SectionLabel('任务列表'),
            const SizedBox(height: 8),
            if (_loading && _jobs.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_jobs.isEmpty)
              Text('暂无计划任务', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray))
            else
              ..._jobs.map((job) {
                final busy = _actionId == job.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.grayLight),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(job.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(job.stateLabel, style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('计划：${job.schedule}', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                      Text('投递：${job.deliverLabel}', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                      if (job.prompt.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(job.prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        ),
                      if (job.lastRunAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '上次运行：${job.lastRunAt}${job.lastStatus != null ? '（${job.lastStatus}）' : ''}',
                            style: const TextStyle(fontSize: 11, color: AppColors.gray),
                          ),
                        ),
                      if (job.lastError != null && job.lastError!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('错误：${job.lastError}', style: const TextStyle(fontSize: 11, color: Color(0xFFB00020))),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: busy ? null : () => _runAction(job.id, 'run'),
                            child: const Text('立即执行'),
                          ),
                          if (job.state == 'paused')
                            TextButton(
                              onPressed: busy ? null : () => _runAction(job.id, 'resume'),
                              child: const Text('恢复'),
                            )
                          else
                            TextButton(
                              onPressed: busy ? null : () => _runAction(job.id, 'pause'),
                              child: const Text('暂停'),
                            ),
                          TextButton(
                            onPressed: busy ? null : () => _deleteJob(job),
                            child: const Text('删除', style: TextStyle(color: Color(0xFFB00020))),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
