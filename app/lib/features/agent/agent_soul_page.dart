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

class AgentSoulPage extends ConsumerStatefulWidget {
  const AgentSoulPage({super.key});

  @override
  ConsumerState<AgentSoulPage> createState() => _AgentSoulPageState();
}

class _AgentSoulPageState extends ConsumerState<AgentSoulPage> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  AgentAdminApi? _api() {
    final config = ref.read(appConfigProvider);
    final session = ref.read(userSessionProvider);
    if (!config.isConfigured || session.token == null) return null;
    return AgentAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final content = await api.getSoul();
      if (mounted) {
        _controller.text = content;
        _dirty = false;
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      await api.saveSoul(_controller.text);
      if (mounted) {
        setState(() => _dirty = false);
        AppMessage.success('人格设定已保存');
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('确定将 SOUL.md 恢复为默认人格？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true) return;
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final content = await api.resetSoul();
      if (mounted) {
        _controller.text = content;
        _dirty = false;
        AppMessage.success('已恢复默认人格');
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '人格（SOUL）',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '编辑 Agent 的人格与行为准则（SOUL.md）。保存后建议发送 /reload 或重启 Agent。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '人格设定内容…',
                ),
                onChanged: (_) => setState(() => _dirty = true),
              ),
            ),
            const SizedBox(height: 12),
            MonoButton(label: _loading ? '处理中…' : '保存', onPressed: _loading || !_dirty ? null : _save),
            const SizedBox(height: 8),
            MonoButton(label: '恢复默认', outlined: true, onPressed: _loading ? null : _reset),
          ],
        ),
      ),
    );
  }
}
