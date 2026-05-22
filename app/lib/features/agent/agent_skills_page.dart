import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/agent_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';

class AgentSkillsPage extends ConsumerStatefulWidget {
  const AgentSkillsPage({super.key});

  @override
  ConsumerState<AgentSkillsPage> createState() => _AgentSkillsPageState();
}

class _AgentSkillsPageState extends ConsumerState<AgentSkillsPage> with SingleTickerProviderStateMixin {
  List<AgentSkill> _installed = const [];
  List<BundledSkill> _bundled = const [];
  bool _loading = false;
  String? _error;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
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
      final installed = await api.listSkills();
      final bundled = await api.listBundledSkills();
      if (mounted) {
        setState(() {
          _installed = installed;
          _bundled = bundled;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(BundledSkill s) async {
    final api = _api();
    if (api == null) return;
    try {
      final list = await api.installSkill(s.id);
      if (mounted) setState(() => _installed = list);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<void> _uninstall(AgentSkill s) async {
    final api = _api();
    if (api == null) return;
    final id = s.id ?? s.name;
    try {
      final list = await api.uninstallSkill(id);
      if (mounted) setState(() => _installed = list);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '技能',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: '已安装'), Tab(text: '可安装')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _listPane(
                  loading: _loading,
                  empty: '暂无已安装技能',
                  children: _installed.map(
                    (s) => ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.description.isEmpty ? s.category : '${s.category} · ${s.description}'),
                      trailing: TextButton(onPressed: () => _uninstall(s), child: const Text('卸载')),
                    ),
                  ),
                ),
                _listPane(
                  loading: _loading,
                  empty: '未找到可安装技能（请确认 HERMES_REPO 可访问）',
                  children: _bundled.map(
                    (s) => ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.description.isEmpty ? s.category : '${s.category} · ${s.description}'),
                      trailing: s.installed
                          ? const Text('已安装', style: TextStyle(color: AppColors.gray, fontSize: 12))
                          : TextButton(onPressed: () => _install(s), child: const Text('安装')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listPane({
    required bool loading,
    required String empty,
    required Iterable<Widget> children,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
          if (loading && children.isEmpty)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (children.isEmpty)
            Text(empty, style: const TextStyle(color: AppColors.gray))
          else
            ...children,
        ],
      ),
    );
  }
}
