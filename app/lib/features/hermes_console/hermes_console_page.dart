import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/hermes_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/app_config.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';

class HermesConsolePage extends ConsumerStatefulWidget {
  const HermesConsolePage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HermesConsolePage> createState() => _HermesConsolePageState();
}

class _HermesConsolePageState extends ConsumerState<HermesConsolePage> {
  final _retentionController = TextEditingController();
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _backups = [];
  bool _loading = false;
  String? _error;
  String? _message;
  String? _logsContent;
  String? _doctorOutput;
  List<Map<String, String>> _mcpServers = const [];
  final _importPathController = TextEditingController();

  void _snack(String text, {bool error = false}) {
    if (error) {
      AppMessage.error(text);
    } else {
      AppMessage.success(text);
    }
  }

  String? _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return e.message;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    _retentionController.dispose();
    _importPathController.dispose();
    super.dispose();
  }

  HermesAdminApi? _api() {
    final session = ref.read(userSessionProvider);
    if (session.token == null || session.token!.isEmpty) return null;
    return HermesAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _refresh({bool quiet = false}) async {
    final api = _api();
    if (api == null) {
      const hint = '请先完成初始化引导并登录（运维接口使用与聊天相同的登录 JWT）';
      setState(() {
        _status = null;
        _backups = [];
        _error = hint;
        _message = null;
      });
      if (!quiet) _snack(hint, error: true);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await api.status();
      final list = await api.listBackups();
      final max = await api.getRetention();
      if (mounted) {
        setState(() {
          _status = st;
          _backups = list;
          _retentionController.text = '$max';
          _loading = false;
          _message = '状态已更新';
        });
      }
      if (!quiet) _snack('状态已刷新');
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '请求失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      if (!quiet) _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      if (!quiet) _snack(msg, error: true);
    }
  }

  Future<void> _viewLogs() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final text = await api.fetchLogs();
      if (mounted) setState(() => _logsContent = text.isEmpty ? '（日志为空）' : text);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runDoctor() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final r = await api.runDoctor();
      if (mounted) setState(() => _doctorOutput = r.output);
      _snack(r.ok ? 'Doctor 完成' : 'Doctor 发现问题', error: !r.ok);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMcp() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final list = await api.listMcpServers();
      if (mounted) setState(() => _mcpServers = list);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importBackup() async {
    final api = _api();
    if (api == null) return;
    final path = _importPathController.text.trim();
    if (path.isEmpty) {
      _snack('请填写服务器上的备份路径', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final out = await api.importArchive(path);
      _snack(out);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadGatewayEnv() async {
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await api.reloadGatewayEnv();
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Gateway 配置已重载';
        });
      }
      _snack('Gateway 已从磁盘重载 .env');
      await _refresh(quiet: true);
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '重载失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  Future<void> _setRetention() async {
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    final n = int.tryParse(_retentionController.text.trim());
    if (n == null || n < 1 || n > 365) {
      const msg = '保留数量须为 1–365 的整数';
      setState(() => _error = msg);
      _snack(msg, error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await api.setRetention(n);
      if (mounted) {
        setState(() {
          _loading = false;
          _message = '已更新最多保留备份数';
        });
      }
      _snack('已保存保留备份数');
      await _refresh(quiet: true);
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '保存失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  Future<void> _backup() async {
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await api.triggerBackup();
      if (mounted) {
        setState(() {
          _loading = false;
          _message = '备份已触发';
        });
      }
      _snack('备份任务已触发');
      await _refresh(quiet: true);
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '备份失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认重启'),
        content: const Text('将执行网关上配置的重启命令，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final out = await api.restart();
      if (mounted) {
        setState(() {
          _loading = false;
          _message = out != null && out.isNotEmpty ? '输出：${out.substring(0, out.length > 200 ? 200 : out.length)}…' : '重启命令已执行';
        });
      }
      _snack(out != null && out.isNotEmpty ? '重启命令已执行（见下方摘要）' : '重启命令已执行');
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '重启失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  Future<void> _maintenance() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('执行维护'),
        content: const Text('将执行网关上 HERMES_MAINTENANCE_SHELL，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final out = await api.runMaintenance();
      if (mounted) {
        setState(() {
          _loading = false;
          _message = out ?? '维护命令已执行';
        });
      }
      _snack('维护脚本已执行');
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '执行失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  Future<void> _restore(String filename) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('危险操作'),
        content: Text('将用备份「$filename」覆盖 Hermes 数据目录，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定还原')),
        ],
      ),
    );
    if (ok != true) return;
    final api = _api();
    if (api == null) {
      _snack('请先登录', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await api.restore(filename);
      if (mounted) {
        setState(() {
          _loading = false;
          _message = '还原已执行';
        });
      }
      _snack('还原已执行');
      await _refresh(quiet: true);
    } on DioException catch (e) {
      final msg = _dioMessage(e) ?? '还原失败';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
      _snack(msg, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(24, widget.embedded ? 16 : 24, 24, 32),
      children: [
        if (!widget.embedded) ...[
          Text(
            'Hermes 运维',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black,
                ) ??
                const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black,
                ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '请求发往 Gateway，由网关在本机执行 tar / shell。\n'
          '鉴权与聊天相同：使用登录后获得的 JWT。Hermes 地址与网关 `.env` 请在服务器上编辑或通过部署脚本上传；修改磁盘文件后可使用下方「重载配置」。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray,
                height: 1.45,
              ),
        ),
        Builder(
          builder: (context) {
            final local = ref.watch(appConfigProvider);
            final ho = local.hermesOriginForServerSafe;
            final bs = local.backupSourcePathSafe;
            final bd = local.backupDirPathSafe;
            if (!local.isConfigured || ho.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '本机引导已记录：\nHERMES_ORIGIN：$ho\n'
                '备份源：$bs\n备份目录：$bd',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray,
                      height: 1.45,
                      fontSize: 11,
                    ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        const SectionLabel('状态与策略'),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13, height: 1.35),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _message!,
              style: const TextStyle(color: AppColors.gray, fontSize: 13, height: 1.35),
            ),
          ),
        MonoButton(
          label: _loading ? '加载中…' : '刷新状态',
          outlined: true,
          onPressed: _loading ? null : _refresh,
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          _kv('Hermes API', _status!['hermesApiOrigin']?.toString() ?? '—'),
          _kv('备份源', _status!['backupSource']?.toString() ?? '—'),
          _kv('备份目录', _status!['backupDir']?.toString() ?? '—'),
          _kv('每日备份整点', '${_status!['dailyBackupHour'] ?? '—'}'),
          _kv('当前保留上限', '${_status!['maxBackups'] ?? '—'}'),
          _kv('备份文件数', '${_status!['backupCount'] ?? '—'}'),
          _kv('上次计划备份', _status!['lastDailyBackupAt']?.toString() ?? '无'),
          _kv('已配置重启', _status!['restartConfigured'] == true ? '是' : '否'),
          _kv('已配置维护', _status!['maintenanceConfigured'] == true ? '是' : '否'),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _retentionController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '最多保留备份数 (1–365)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        MonoButton(
          label: '保存保留数',
          outlined: true,
          onPressed: _loading ? null : _setRetention,
        ),
        const SizedBox(height: 28),
        const SectionLabel('扩展管理'),
        const SizedBox(height: 12),
        MonoButton(
          label: 'Agent 管理',
          outlined: true,
          onPressed: _loading ? null : () => context.push('/home/workspace/agent'),
        ),
        const SizedBox(height: 12),
        MonoButton(
          label: '计划任务',
          outlined: true,
          onPressed: _loading ? null : () => context.push('/home/workspace/schedules'),
        ),
        const SizedBox(height: 12),
        MonoButton(
          label: '消息网关',
          outlined: true,
          onPressed: _loading ? null : () => context.push('/home/workspace/message-gateway'),
        ),
        const SizedBox(height: 28),
        const SectionLabel('高级运维'),
        const SizedBox(height: 12),
        MonoButton(label: '查看 Gateway 日志', outlined: true, onPressed: _loading ? null : _viewLogs),
        const SizedBox(height: 12),
        MonoButton(label: '运行 Hermes Doctor', outlined: true, onPressed: _loading ? null : _runDoctor),
        const SizedBox(height: 12),
        MonoButton(label: '刷新 MCP 列表', outlined: true, onPressed: _loading ? null : _loadMcp),
        if (_doctorOutput != null) ...[
          const SizedBox(height: 12),
          Text(_doctorOutput!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ],
        if (_logsContent != null) ...[
          const SizedBox(height: 12),
          Text(_logsContent!, maxLines: 12, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ],
        if (_mcpServers.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._mcpServers.map((s) => Text('${s['name']}: ${s['command']}', style: const TextStyle(fontSize: 12))),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _importPathController,
          decoration: const InputDecoration(
            labelText: '备份包服务器路径（导入）',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        MonoButton(label: '导入备份', outlined: true, onPressed: _loading ? null : _importBackup),
        const SizedBox(height: 28),
        const SectionLabel('操作'),
        const SizedBox(height: 12),
        MonoButton(
          label: '重载 Gateway 配置',
          outlined: true,
          onPressed: _loading ? null : _reloadGatewayEnv,
        ),
        const SizedBox(height: 12),
        MonoButton(label: '立即备份', outlined: true, onPressed: _loading ? null : _backup),
        const SizedBox(height: 12),
        MonoButton(label: '重启 Hermes', outlined: true, onPressed: _loading ? null : _restart),
        const SizedBox(height: 12),
        MonoButton(label: '执行维护脚本', outlined: true, onPressed: _loading ? null : _maintenance),
        const SizedBox(height: 24),
        const SectionLabel('备份列表'),
        const SizedBox(height: 8),
        if (_backups.isEmpty)
          Text('暂无备份', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray))
        else
          ..._backups.map((b) {
            final name = b['filename']?.toString() ?? '';
            final size = b['sizeBytes']?.toString() ?? '';
            final at = b['createdAt']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grayLight),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 12)),
                        Text('$at · $size bytes', style: TextStyle(fontSize: 11, color: AppColors.gray)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => _restore(name),
                    child: const Text('还原'),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(k, style: const TextStyle(color: AppColors.gray, fontSize: 12)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
