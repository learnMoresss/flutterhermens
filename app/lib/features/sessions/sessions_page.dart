import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chat/session_groups.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hermes_sessions_api.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';

class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key});

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  final _searchController = TextEditingController();
  List<HermesSessionSummary> _sessions = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  HermesSessionsApi? _api() {
    if (ref.read(userSessionProvider).token == null) return null;
    return HermesSessionsApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load([String query = '']) async {
    final api = _api();
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = query.trim().isEmpty
          ? await api.listSessions()
          : await api.searchSessions(query.trim());
      if (mounted) setState(() => _sessions = list);
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

  @override
  Widget build(BuildContext context) {
    final grouped = groupSessions(_sessions);
    return AppScaffold(
      title: '全部会话',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索会话内容…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                ),
              ),
              onSubmitted: _load,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
            ),
          Expanded(
            child: _loading && _sessions.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : RefreshIndicator(
                    onRefresh: () => _load(_searchController.text),
                    child: ListView(
                      children: [
                        for (final group in SessionDateGroup.values) ...[
                          if (grouped[group]!.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                sessionDateGroupLabels[group] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.gray),
                              ),
                            ),
                            for (final s in grouped[group]!)
                              ListTile(
                                title: Text(s.title),
                                subtitle: Text(
                                  s.snippet ?? s.preview ?? '${s.messageCount} 条消息',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => context.go('/home/chat'),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
