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

class AgentProfilesPage extends ConsumerStatefulWidget {
  const AgentProfilesPage({super.key});

  @override
  ConsumerState<AgentProfilesPage> createState() => _AgentProfilesPageState();
}

class _AgentProfilesPageState extends ConsumerState<AgentProfilesPage> {
  List<AgentProfile> _profiles = const [];
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
      final list = await api.listProfiles();
      if (mounted) setState(() => _profiles = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate(AgentProfile profile) async {
    if (profile.isActive) return;
    final api = _api();
    if (api == null) return;
    try {
      final list = await api.activateProfile(profile.name);
      if (mounted) {
        setState(() => _profiles = list);
        AppMessage.success('已切换到「${profile.displayName}」');
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    }
  }

  Future<void> _createProfile() async {
    final api = _api();
    if (api == null) return;
    final nameCtrl = TextEditingController();
    var clone = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('新建档案'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '档案名称（字母/数字/_/-）'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('从当前档案克隆'),
                value: clone,
                onChanged: (v) => setLocal(() => clone = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
    try {
      final list = await api.createProfile(nameCtrl.text.trim(), clone: clone);
      if (mounted) setState(() => _profiles = list);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
    nameCtrl.dispose();
  }

  Future<void> _deleteProfile(AgentProfile profile) async {
    if (profile.isDefault) return;
    final api = _api();
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除档案'),
        content: Text('确定删除「${profile.name}」？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final list = await api.deleteProfile(profile.name);
      if (mounted) setState(() => _profiles = list);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '档案',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '每个档案拥有独立的配置、技能与人格。切换后 Agent 将使用对应目录下的设置。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            MonoButton(label: '新建档案', outlined: true, onPressed: _createProfile),
            const SizedBox(height: 12),
            if (_loading && _profiles.isEmpty)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_profiles.isEmpty)
              const Text('暂无档案', style: TextStyle(color: AppColors.gray))
            else
              ..._profiles.map(
                (p) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(color: p.isActive ? AppColors.black : AppColors.grayLight, width: p.isActive ? 1.5 : 1),
                  ),
                  child: ListTile(
                    title: Text(p.displayName),
                    subtitle: Text(
                      '提供商：${p.provider.isEmpty ? '—' : p.provider} · 模型：${p.model.isEmpty ? '—' : p.model}\n'
                      '技能 ${p.skillCount} 个 · ${p.hasEnv ? '已配置环境' : '无 .env'} · ${p.hasSoul ? '有人格' : '无人格'}',
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!p.isDefault)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _deleteProfile(p),
                          ),
                        if (p.isActive)
                          const Chip(label: Text('当前', style: TextStyle(fontSize: 11)))
                        else
                          TextButton(onPressed: () => _activate(p), child: const Text('切换')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
