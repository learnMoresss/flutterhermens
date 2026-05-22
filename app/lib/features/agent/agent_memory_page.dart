import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/agent_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';

class AgentMemoryPage extends ConsumerStatefulWidget {
  const AgentMemoryPage({super.key});

  @override
  ConsumerState<AgentMemoryPage> createState() => _AgentMemoryPageState();
}

class _AgentMemoryPageState extends ConsumerState<AgentMemoryPage> {
  AgentMemoryData? _data;
  bool _loading = false;
  String? _error;
  final _userController = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    super.dispose();
  }

  AgentAdminApi? _api() {
    if (ref.read(userSessionProvider).token == null) return null;
    return AgentAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load() async {
    final api = _api();
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.getMemory();
      if (mounted) {
        setState(() => _data = data);
        _userController.text = data.userContent;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _addEntry() async {
    final api = _api();
    if (api == null) return;
    final text = await _promptText('新增记忆条目');
    if (text == null || text.trim().isEmpty) return;
    try {
      final data = await api.addMemoryEntry(text.trim());
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<void> _editEntry(MemoryEntry entry) async {
    final api = _api();
    if (api == null) return;
    final text = await _promptText('编辑记忆', initial: entry.content);
    if (text == null) return;
    try {
      final data = await api.updateMemoryEntry(entry.index, text.trim());
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<void> _deleteEntry(MemoryEntry entry) async {
    final api = _api();
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除记忆条目'),
        content: const Text('确定删除该条目？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final data = await api.removeMemoryEntry(entry.index);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<void> _saveUser() async {
    final api = _api();
    if (api == null) return;
    try {
      final data = await api.saveUserProfile(_userController.text);
      if (mounted) {
        setState(() => _data = data);
        AppMessage.success('用户档案已保存');
      }
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<String?> _promptText(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('确定')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Widget _capacityBar(int used, int limit, String label) {
    final pct = limit > 0 ? (used / limit * 100).clamp(0, 100).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label：$used / $limit 字符（$pct%）', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: limit > 0 ? used / limit : 0, minHeight: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AppScaffold(
      title: '记忆',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            if (_loading && data == null)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (data != null) ...[
              Text(
                '会话统计：${data.totalSessions} 个会话，${data.totalMessages} 条消息',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Agent 记忆'),
              const SizedBox(height: 8),
              _capacityBar(data.memoryCharCount, data.memoryCharLimit, 'MEMORY.md'),
              const SizedBox(height: 12),
              MonoButton(label: '新增条目', outlined: true, onPressed: _addEntry),
              const SizedBox(height: 12),
              if (data.memoryEntries.isEmpty)
                const Text('暂无记忆条目', style: TextStyle(color: AppColors.gray))
              else
                ...data.memoryEntries.map(
                  (e) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(e.content, maxLines: 4, overflow: TextOverflow.ellipsis),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _editEntry(e);
                          if (v == 'delete') _deleteEntry(e);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              const SectionLabel('用户档案 (USER.md)'),
              const SizedBox(height: 8),
              _capacityBar(data.userCharCount, data.userCharLimit, 'USER.md'),
              const SizedBox(height: 8),
              TextField(
                controller: _userController,
                maxLines: 6,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '关于你的偏好与背景…'),
              ),
              const SizedBox(height: 12),
              MonoButton(label: '保存用户档案', onPressed: _saveUser),
            ],
          ],
        ),
      ),
    );
  }
}
