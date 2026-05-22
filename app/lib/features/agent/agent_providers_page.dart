import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/agent_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/section_label.dart';

class AgentProvidersPage extends ConsumerStatefulWidget {
  const AgentProvidersPage({super.key});

  @override
  ConsumerState<AgentProvidersPage> createState() => _AgentProvidersPageState();
}

class _AgentProvidersPageState extends ConsumerState<AgentProvidersPage> {
  List<EnvKeyInfo> _keys = const [];
  String _provider = '';
  String _model = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await api.listProviders();
      if (mounted) {
        setState(() {
          _keys = result.keys;
          _provider = result.provider;
          _model = result.model;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editEnvKey(EnvKeyInfo key) async {
    final api = _api();
    if (api == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('设置 ${key.label}'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: key.key, hintText: '输入新密钥值'),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    try {
      final keys = await api.setEnvKey(key.key, ctrl.text.trim());
      if (mounted) setState(() => _keys = keys);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
    ctrl.dispose();
  }

  Future<void> _editConfig() async {
    final api = _api();
    if (api == null) return;
    final providerCtrl = TextEditingController(text: _provider);
    final modelCtrl = TextEditingController(text: _model);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑 config.yaml'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: providerCtrl, decoration: const InputDecoration(labelText: 'provider')),
            TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'default model')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      providerCtrl.dispose();
      modelCtrl.dispose();
      return;
    }
    try {
      final result = await api.setProviderConfig(
        provider: providerCtrl.text.trim(),
        model: modelCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _keys = result.keys;
          _provider = result.provider;
          _model = result.model;
        });
      }
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
    providerCtrl.dispose();
    modelCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<EnvKeyInfo>>{};
    for (final k in _keys) {
      grouped.putIfAbsent(k.category, () => []).add(k);
    }

    return AppScaffold(
      title: '提供商',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '查看并编辑服务器 .env 密钥（保存后立即生效，已配置项显示脱敏值）。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loading ? null : _editConfig,
              child: const Text('编辑默认 provider / model'),
            ),
            if (_provider.isNotEmpty || _model.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionLabel('当前 config.yaml'),
              const SizedBox(height: 8),
              Text('提供商：${_provider.isEmpty ? '—' : _provider}', style: const TextStyle(fontSize: 13)),
              Text('默认模型：${_model.isEmpty ? '—' : _model}', style: const TextStyle(fontSize: 13)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            ],
            const SizedBox(height: 20),
            if (_loading && _keys.isEmpty)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              for (final entry in grouped.entries) ...[
                SectionLabel(entry.key),
                const SizedBox(height: 8),
                ...entry.value.map(
                  (k) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(k.label),
                    subtitle: Text(k.key, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    trailing: k.configured
                        ? Text(k.maskedValue, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))
                        : const Text('未配置', style: TextStyle(fontSize: 12, color: AppColors.gray)),
                    onTap: () => _editEnvKey(k),
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}
