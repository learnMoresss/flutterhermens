import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/agent_admin_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';

class AgentToolsetsPage extends ConsumerStatefulWidget {
  const AgentToolsetsPage({super.key});

  @override
  ConsumerState<AgentToolsetsPage> createState() => _AgentToolsetsPageState();
}

class _AgentToolsetsPageState extends ConsumerState<AgentToolsetsPage> {
  List<AgentToolset> _toolsets = const [];
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
      final list = await api.listToolsets();
      if (mounted) setState(() => _toolsets = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(AgentToolset t, bool enabled) async {
    final api = _api();
    if (api == null) return;
    try {
      final list = await api.setToolset(t.key, enabled);
      if (mounted) setState(() => _toolsets = list);
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '工具集',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020))),
              ),
            if (_loading && _toolsets.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
            else
              ..._toolsets.map(
                (t) => SwitchListTile(
                  title: Text(t.label),
                  subtitle: Text(t.description, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                  value: t.enabled,
                  onChanged: _loading ? null : (v) => _toggle(t, v),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
