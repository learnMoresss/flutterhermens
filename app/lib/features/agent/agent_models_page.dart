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

class AgentModelsPage extends ConsumerStatefulWidget {
  const AgentModelsPage({super.key});

  @override
  ConsumerState<AgentModelsPage> createState() => _AgentModelsPageState();
}

class _AgentModelsPageState extends ConsumerState<AgentModelsPage> {
  List<HermesSavedModel> _models = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  AgentAdminApi? _api() {
    final session = ref.read(userSessionProvider);
    if (session.token == null) return null;
    return AgentAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load() async {
    final api = _api();
    if (api == null) {
      setState(() => _error = '请先登录');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await api.listModels();
      if (mounted) setState(() => _models = models);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showModelForm({HermesSavedModel? existing}) async {
    final api = _api();
    if (api == null) return;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final providerCtrl = TextEditingController(text: existing?.provider ?? '');
    final modelCtrl = TextEditingController(text: existing?.model ?? '');
    final baseUrlCtrl = TextEditingController(text: existing?.baseUrl ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? '添加模型' : '编辑模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '显示名称')),
              TextField(controller: providerCtrl, decoration: const InputDecoration(labelText: '提供商')),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: '模型 ID')),
              TextField(controller: baseUrlCtrl, decoration: const InputDecoration(labelText: 'Base URL（可选）')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      providerCtrl.dispose();
      modelCtrl.dispose();
      baseUrlCtrl.dispose();
      return;
    }
    try {
      if (existing == null) {
        await api.addModel(
          name: nameCtrl.text.trim(),
          provider: providerCtrl.text.trim(),
          model: modelCtrl.text.trim(),
          baseUrl: baseUrlCtrl.text.trim(),
        );
      } else {
        await api.updateModel(
          existing.id,
          name: nameCtrl.text.trim(),
          provider: providerCtrl.text.trim(),
          model: modelCtrl.text.trim(),
          baseUrl: baseUrlCtrl.text.trim(),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
    nameCtrl.dispose();
    providerCtrl.dispose();
    modelCtrl.dispose();
    baseUrlCtrl.dispose();
  }

  Future<void> _deleteModel(HermesSavedModel m) async {
    final api = _api();
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除「${m.displayLabel}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.removeModel(m.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '模型',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '来自服务器 models.json 的模型预设。在聊天页可选择模型发送请求。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            if (_loading && _models.isEmpty)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_models.isEmpty)
              const Text('暂无模型预设', style: TextStyle(color: AppColors.gray))
            else ...[
              MonoButton(label: '添加模型', onPressed: () => _showModelForm()),
              const SizedBox(height: 12),
              ..._models.map(
                (m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.displayLabel),
                  subtitle: Text('${m.provider} · ${m.model}', style: const TextStyle(fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _showModelForm(existing: m);
                      if (v == 'delete') _deleteModel(m);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
