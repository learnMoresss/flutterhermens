import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/network/api_client.dart';
import '../../core/network/projects_api.dart';
import '../../core/storage/apps_history_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_message.dart';
import '../../providers/app_project_providers.dart';
import '../../providers/app_providers.dart';
import 'hermes_app_bridge.dart';
import 'project_html_inject.dart';
import '../../shared/widgets/mono_button.dart';
import '../main/workspace_chrome.dart';

class AppsPage extends ConsumerStatefulWidget {
  const AppsPage({
    super.key,
    this.embedded = false,
    this.onOpenDrawer,
    this.onChromeChanged,
  });

  final bool embedded;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<WorkspaceChrome>? onChromeChanged;

  static void notifyDrawerOpened(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppsPageState>();
    state?._onDrawerOpened();
  }

  @override
  ConsumerState<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends ConsumerState<AppsPage> {
  WebViewController? _controller;
  bool _loadingList = false;
  bool _loadingPage = false;
  List<HermesProjectInfo> _projects = const [];
  String? _activeSlug;
  String? _error;
  bool _projectLocked = false;
  String _lockReason = '';
  Timer? _lockPollTimer;
  HermesProjectInfo? _activeProject;
  HermesAppBridge? _bridge;

  ProjectsApi? _api() {
    final session = ref.read(userSessionProvider);
    if (session.token == null || session.token!.isEmpty) return null;
    return ProjectsApi.fromClient(ref.read(gatewayClientProvider));
  }

  AppsHistoryStore get _history => AppsHistoryStore(ref.read(sharedPreferencesProvider));

  String _pageUrl(String slug) {
    final base = ref.read(appConfigProvider).gatewayUrl.replaceAll(RegExp(r'/$'), '');
    return '$base/v1/projects/$slug/';
  }

  Future<void> _refreshProjects({bool autoOpenIfEmpty = false}) async {
    final api = _api();
    if (api == null) {
      if (mounted) {
        setState(() => _error = '请先登录后再加载应用列表');
      }
      return;
    }
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final list = await api.listProjects();
      if (!mounted) return;
      setState(() => _projects = list);
      if (autoOpenIfEmpty && _controller == null && list.isNotEmpty) {
        await _openLastOrFirst(skipRefresh: true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _openProject(HermesProjectInfo project) async {
    final api = _api();
    if (api == null) return;

    var fresh = project;
    if (project.id != _activeSlug) {
      try {
        fresh = await api.fetchMeta(project.id);
      } on Object {
        /* 列表数据可能过期，打开前尽量拉最新锁状态 */
      }
    }

    if (fresh.isLocked && fresh.id != _activeSlug) {
      if (mounted) {
        setState(() {
          _projects = _projects
              .map((p) => p.id == fresh.id ? fresh : p)
              .toList(growable: false);
        });
        AppMessage.info('「${fresh.title}」正在更新中，请稍候后再打开');
      }
      return;
    }

    if (fresh.id == _activeSlug && _controller != null) {
      _closeDrawerIfOpen();
      return;
    }
    setState(() {
      _loadingPage = true;
      _error = null;
      _activeSlug = fresh.id;
      _activeProject = fresh;
      _projectLocked = fresh.isLocked;
      _lockReason = fresh.lock?.reason ?? 'Hermes 正在更新';
    });
    ref.read(activeViewingProjectSlugProvider.notifier).set(fresh.id);
    try {
      if (fresh.needsStart) {
        await api.start(fresh.id);
        await _refreshProjects();
      }
      final url = _pageUrl(fresh.id);
      await _history.recordVisit(slug: fresh.id, title: fresh.title, url: url);
      await _loadWebView(fresh.id, url);
      _startLockPolling();
      if (mounted) _closeDrawerIfOpen();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loadingPage = false;
          _error = e.message;
        });
      }
    }
  }

  void _closeDrawerIfOpen() {
    if (!mounted) return;
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
    }
  }

  void _onDrawerOpened() {
    if (!_loadingList) {
      unawaited(_refreshProjects(autoOpenIfEmpty: false));
    }
  }

  void _syncChrome() {
    if (!widget.embedded || widget.onChromeChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final history = _history.loadHistory();
      final title = _activeProject?.title ?? '应用';
      final subtitle = _activeSlug ?? '选择 Hermes 项目运行';
      widget.onChromeChanged!(
        WorkspaceChrome(
          title: title,
          subtitle: subtitle,
          leading: IconButton(
            tooltip: '项目列表',
            icon: const Icon(Icons.menu),
            onPressed: widget.onOpenDrawer,
          ),
          actions: [
            if (_controller != null)
              IconButton(
                tooltip: '关闭应用',
                onPressed: _closeProject,
                icon: const Icon(Icons.close),
              ),
            IconButton(
              tooltip: '刷新列表',
              onPressed: _loadingList
                  ? null
                  : () => _refreshProjects(autoOpenIfEmpty: _controller == null),
              icon: const Icon(Icons.refresh),
            ),
          ],
          drawer: _buildDrawer(history),
        ),
      );
    });
  }

  void _closeProject() {
    _lockPollTimer?.cancel();
    ref.read(activeViewingProjectSlugProvider.notifier).set(null);
    setState(() {
      _controller = null;
      _activeSlug = null;
      _activeProject = null;
      _projectLocked = false;
      _lockReason = '';
      _loadingPage = false;
    });
  }

  Future<void> _loadWebView(String slug, String url) async {
    await _bridge?.dispose();
    _bridge = null;

    final token = ref.read(userSessionProvider).token ?? '';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    final bridge = HermesAppBridge(
      controller: controller,
      apiClient: ref.read(gatewayClientProvider),
      mounted: () => mounted,
    );
    bridge.attach();
    _bridge = bridge;

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          await bridge.notifyNativeReady();
          if (mounted) setState(() => _loadingPage = false);
        },
        onWebResourceError: (e) {
          if (mounted && !_projectLocked) {
            setState(() {
              _loadingPage = false;
              _error = e.description;
            });
          }
        },
      ),
    );

    await _loadProjectPage(controller, slug, url, token);
    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _loadProjectPage(WebViewController controller, String slug, String url, String token) async {
    if (bundledProjectHtmlSlugs.contains(slug)) {
      try {
        final raw = await rootBundle.loadString(bundledProjectAssetPath(slug));
        final gatewayBase = ref.read(appConfigProvider).gatewayUrl;
        final html = injectHermesProjectHtml(raw, slug, gatewayBase);
        await controller.loadHtmlString(html, baseUrl: url);
        return;
      } on Object {
        /* bundle 缺失时回退远端 HTML */
      }
    }
    await controller.loadRequest(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  void _startLockPolling() {
    _lockPollTimer?.cancel();
    _lockPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _pollProjectLock());
    _pollProjectLock();
  }

  Future<void> _pollProjectLock() async {
    final slug = _activeSlug;
    final api = _api();
    if (slug == null || api == null || !mounted) return;
    try {
      final meta = await api.fetchMeta(slug);
      final wasLocked = _projectLocked;
      final locked = meta.isLocked;
      if (!mounted) return;
      setState(() {
        _projectLocked = locked;
        _lockReason = meta.lock?.reason ?? 'Hermes 正在更新';
        _activeProject = meta;
        _projects = _projects
            .map((p) => p.id == slug ? meta : p)
            .toList(growable: false);
      });
      if (wasLocked && !locked && _controller != null) {
        final url = _pageUrl(slug);
        setState(() => _loadingPage = true);
        await _loadWebView(slug, url);
        if (mounted) AppMessage.success('应用已更新');
      }
    } on Object {
      /* ignore transient poll errors */
    }
  }

  Future<void> _openLastOrFirst({bool skipRefresh = false}) async {
    if (!skipRefresh) {
      await _refreshProjects();
    }
    if (!mounted || _projects.isEmpty) return;
    final last = _history.lastSlug;
    HermesProjectInfo? target;
    if (last != null) {
      for (final p in _projects) {
        if (p.id == last) {
          target = p;
          break;
        }
      }
    }
    target ??= _projects.first;
    await _openProject(target);
  }

  Future<void> _projectAction(HermesProjectInfo p, String action) async {
    if (p.isLocked && _activeSlug == p.id) {
      AppMessage.info('「${p.title}」正在更新中，请稍候');
      return;
    }
    final api = _api();
    if (api == null) return;
    try {
      switch (action) {
        case 'start':
          await api.start(p.id);
        case 'stop':
          await api.stop(p.id);
        case 'restart':
          await api.restart(p.id);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除项目'),
              content: Text('确定删除「${p.title}」？目录与数据不可恢复。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除', style: TextStyle(color: Color(0xFFB00020))),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await api.delete(p.id);
          if (_activeSlug == p.id) {
            _closeProject();
          }
      }
      AppMessage.success('已执行：$action');
      await _refreshProjects();
    } on ApiException catch (e) {
      AppMessage.error(e.message);
    }
  }

  @override
  void dispose() {
    _lockPollTimer?.cancel();
    unawaited(_bridge?.dispose());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshProjects();
      if (mounted) await _openLastOrFirst(skipRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      _syncChrome();
      return _buildBody();
    }

    final history = _history.loadHistory();
    final title = _activeProject?.title ?? '应用';
    final subtitle = _activeSlug ?? '选择 Hermes 项目运行';

    return Scaffold(
      onDrawerChanged: (opened) {
        if (opened && !_loadingList) {
          unawaited(_refreshProjects(autoOpenIfEmpty: false));
        }
      },
      drawer: _buildDrawer(history),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (_controller != null)
            IconButton(
              tooltip: '关闭应用',
              onPressed: _closeProject,
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: '刷新列表',
            onPressed: _loadingList ? null : () => _refreshProjects(autoOpenIfEmpty: _controller == null),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.grayLight),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 12)),
          ),
        if (_loadingPage)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildMainBody()),
      ],
    );
  }

  Widget _buildMainBody() {
    if (_controller != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller!),
          if (_projectLocked && _controller != null)
            AbsorbPointer(
              child: Container(
                color: Colors.white.withValues(alpha: 0.92),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _lockReason.isNotEmpty ? _lockReason : 'Hermes 正在更新此应用…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _activeProject?.title ?? _activeSlug ?? '',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '已锁定操作，请勿点击\n完成后将自动刷新',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.gray, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return _buildPlaceholderBody();
  }

  Widget _buildPlaceholderBody() {
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('暂无项目', style: TextStyle(color: AppColors.gray)),
              const SizedBox(height: 12),
              MonoButton(
                label: '刷新列表',
                outlined: true,
                onPressed: () => _refreshProjects(autoOpenIfEmpty: true),
              ),
              const SizedBox(height: 8),
              const Text(
                '在聊天中开启「创建 App」让 Hermes 生成',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_open, size: 40, color: AppColors.gray.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              '共 ${_projects.length} 个项目',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '从左上角打开列表，选择要运行的应用',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.gray, height: 1.45),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (ctx) => MonoButton(
                label: '打开列表',
                outlined: true,
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(List<AppsHistoryEntry> history) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('应用列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _loadingList
                        ? null
                        : () => _refreshProjects(autoOpenIfEmpty: _controller == null),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (_loadingList && _projects.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Text('历史', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    if (history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text('暂无历史', style: TextStyle(fontSize: 12, color: AppColors.gray)),
                      ),
                    ...history.map(
                      (h) => ListTile(
                        dense: true,
                        selected: h.slug == _activeSlug,
                        title: Text(h.title, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(h.slug, style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          if (h.slug != _activeSlug) {
                            final p = _projects.where((x) => x.id == h.slug).firstOrNull;
                            if (p != null && p.isLocked) {
                              AppMessage.info('「${p.title}」正在更新中，请稍候后再打开');
                              return;
                            }
                          }
                          final p = _projects.where((x) => x.id == h.slug).firstOrNull;
                          if (p != null) {
                            _openProject(p);
                          } else {
                            _openProject(
                              HermesProjectInfo(
                                id: h.slug,
                                title: h.title,
                                type: HermesProjectType.static,
                                version: '1.0.0',
                                status: HermesProjectStatus.running,
                                url: h.url,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 24),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Text('服务器项目', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    if (_projects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text('暂无项目', style: TextStyle(fontSize: 12, color: AppColors.gray)),
                      ),
                    ..._projects.map(_buildDrawerProjectTile),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerProjectTile(HermesProjectInfo p) {
    final typeLabel = p.isStatic ? '静态' : '动态';
    final selected = p.id == _activeSlug;
    return ListTile(
      dense: true,
      selected: selected,
      title: Text('${p.title} ($typeLabel)', style: const TextStyle(fontSize: 13)),
      subtitle: Text('${p.id} · ${p.status.name}', style: const TextStyle(fontSize: 11)),
      onTap: () => _openProject(p),
      trailing: p.isLocked
          ? const Icon(Icons.lock_outline, size: 18, color: AppColors.gray)
          : PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'open') {
                  _openProject(p);
                  return;
                }
                if (v == 'close' && selected) {
                  _closeProject();
                  return;
                }
                _projectAction(p, v);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'open', child: Text('打开')),
                if (selected) const PopupMenuItem(value: 'close', child: Text('关闭')),
                if (!p.isStatic) ...[
                  const PopupMenuItem(value: 'start', child: Text('启动')),
                  const PopupMenuItem(value: 'stop', child: Text('停止')),
                  const PopupMenuItem(value: 'restart', child: Text('重启')),
                ],
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: Color(0xFFB00020))),
                ),
              ],
            ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
