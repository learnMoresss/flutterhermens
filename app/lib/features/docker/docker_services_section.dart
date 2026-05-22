import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/docker_admin_api.dart';
import '../../core/storage/docker_container_notes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_message.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';
import 'docker_container_detail_sheet.dart';
import 'docker_images_section.dart';
import 'docker_logs_panel.dart';

class DockerServicesSection extends ConsumerStatefulWidget {
  const DockerServicesSection({super.key, this.showHeading = true});

  final bool showHeading;

  @override
  ConsumerState<DockerServicesSection> createState() => _DockerServicesSectionState();
}

class _DockerServicesSectionState extends ConsumerState<DockerServicesSection> {
  bool _loading = false;
  bool _dockerOk = false;
  String? _error;
  List<DockerContainerInfo> _containers = const [];
  Map<String, DockerContainerNote> _notes = {};
  String? _expandedLogsId;
  String? _searchText = '';
  String _stateFilter = 'all';
  String? _projectFilter = 'all';
  final _searchController = TextEditingController();

  DockerAdminApi? _api() {
    final session = ref.read(userSessionProvider);
    if (session.token == null || session.token!.isEmpty) return null;
    return DockerAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  DockerContainerNotesStore get _notesStore =>
      DockerContainerNotesStore(ref.read(sharedPreferencesProvider));

  void _loadNotes() {
    _notes = _notesStore.loadAll();
  }

  String _displayTitle(DockerContainerInfo c) {
    final note = _notes[c.id];
    if (note?.alias != null && note!.alias!.trim().isNotEmpty) {
      return note.alias!.trim();
    }
    return c.name;
  }

  Future<void> _refresh() async {
    final api = _api();
    if (api == null) {
      setState(() {
        _error = '请先完成初始化并登录';
        _containers = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _loadNotes();
    try {
      final ok = await api.dockerAvailable();
      final search = _searchText?.trim();
      final query = DockerListQuery(
        // 备注仅本机存储，搜索在客户端合并过滤
        search: null,
        state: _stateFilter == 'all' ? null : _stateFilter,
        project: _projectFilter == 'all' ? null : _projectFilter,
      );
      var list = ok ? await api.listContainers(query: query) : <DockerContainerInfo>[];
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        list = list.where((c) {
          final note = _notes[c.id];
          final hay =
              '${c.name} ${c.image} ${c.id} ${c.composeProject ?? ''} ${note?.alias ?? ''} ${note?.note ?? ''}'
                  .toLowerCase();
          return hay.contains(q);
        }).toList(growable: false);
      }
      if (mounted) {
        setState(() {
          _dockerOk = ok;
          _containers = list;
          _loading = false;
          if (!ok) _error = 'Docker 不可用：请确认网关容器已挂载 docker.sock';
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
          _containers = const [];
        });
      }
    }
  }

  List<String> get _composeProjects {
    final set = <String>{};
    for (final c in _containers) {
      final p = c.composeProject;
      if (p != null && p.isNotEmpty) set.add(p);
    }
    return set.toList()..sort();
  }

  Future<void> _runAction(DockerContainerInfo c, Future<void> Function() fn, String label) async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      await fn();
      if (mounted) AppMessage.success('$label 已执行');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _dialogRename(DockerContainerInfo c) async {
    final controller = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名容器'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Docker 名称',
            hintText: '字母数字、_、.、-',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final api = _api();
    if (api == null) return;
    await _runAction(c, () => api.rename(c.id, name), '重命名');
  }

  Future<void> _dialogEditNote(DockerContainerInfo c) async {
    final existing = _notes[c.id];
    final aliasCtrl = TextEditingController(text: existing?.alias ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑备注'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aliasCtrl,
                decoration: const InputDecoration(
                  labelText: '展示名称（仅本机）',
                  hintText: '如：Hermes 网关',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注说明'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final alias = aliasCtrl.text.trim();
    final note = noteCtrl.text.trim();
    if (alias.isEmpty && note.isEmpty) {
      await _notesStore.remove(c.id);
    } else {
      await _notesStore.save(
        DockerContainerNote(
          containerId: c.id,
          alias: alias.isEmpty ? null : alias,
          note: note.isEmpty ? null : note,
        ),
      );
    }
    _loadNotes();
    setState(() {});
    AppMessage.success('备注已保存');
  }

  Future<void> _dialogDelete(DockerContainerInfo c) async {
    var force = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('删除容器'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定删除「${c.name}」？此操作不可恢复。', style: const TextStyle(fontSize: 13)),
                if (c.isRunning) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('强制删除（运行中）', style: TextStyle(fontSize: 13)),
                    value: force,
                    onChanged: (v) => setDialogState(() => force = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除', style: TextStyle(color: Color(0xFFB00020))),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    if (c.isRunning && !force) {
      AppMessage.error('容器正在运行，请勾选强制删除或先停止');
      return;
    }
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      await api.remove(c.id, force: force);
      await _notesStore.remove(c.id);
      if (mounted) AppMessage.success('已删除 ${c.name}');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clearAllNotes() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除本机备注'),
        content: const Text('将删除所有容器本地备注，不影响 Docker 真名。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok != true) return;
    await _notesStore.clearAll();
    _loadNotes();
    setState(() {});
    AppMessage.success('备注已清除');
  }

  void _showMoreMenu(DockerContainerInfo c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名（Docker）'),
              onTap: () {
                Navigator.pop(ctx);
                _dialogRename(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('编辑备注'),
              onTap: () {
                Navigator.pop(ctx);
                _dialogEditNote(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFB00020)),
              title: const Text('删除容器', style: TextStyle(color: Color(0xFFB00020))),
              onTap: () {
                Navigator.pop(ctx);
                _dialogDelete(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadNotes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _composeProjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          const SectionLabel('Docker 服务'),
          const SizedBox(height: 8),
        ],
        Text(
          '自动发现服务器上全部容器。备注名仅保存在本机；重命名会修改 Docker 真名。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索名称、镜像、备注…',
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchText?.isNotEmpty == true
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchText = '');
                      _refresh();
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            setState(() => _searchText = v);
            _refresh();
          },
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('全部', 'all'),
              _filterChip('运行中', 'running'),
              _filterChip('已停止', 'stopped'),
              _filterChip('已暂停', 'paused'),
            ],
          ),
        ),
        if (projects.isNotEmpty) ...[
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _projectFilter ?? 'all',
            decoration: const InputDecoration(labelText: 'Compose 项目', isDense: true),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('全部项目')),
              ...projects.map((p) => DropdownMenuItem(value: p, child: Text(p))),
            ],
            onChanged: _loading
                ? null
                : (v) {
                    setState(() => _projectFilter = v);
                    _refresh();
                  },
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MonoButton(
                label: _loading ? '加载中…' : '刷新',
                outlined: true,
                onPressed: _loading ? null : _refresh,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _clearAllNotes, child: const Text('清除备注', style: TextStyle(fontSize: 12))),
          ],
        ),
        if (_dockerOk) ...[
          const SizedBox(height: 8),
          Text('共 ${_containers.length} 个容器', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
        ],
        const SizedBox(height: 8),
        ..._containers.map(_buildCard),
        const SizedBox(height: 16),
        const Divider(),
        const DockerImagesSection(),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _stateFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: _loading
            ? null
            : (_) {
                setState(() => _stateFilter = value);
                _refresh();
              },
      ),
    );
  }

  Widget _buildCard(DockerContainerInfo c) {
    final title = _displayTitle(c);
    final note = _notes[c.id];
    final showLogs = _expandedLogsId == c.id;
    final api = _api();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.grayLight),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != c.name)
                  Text(c.name, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                Text(c.image, style: const TextStyle(fontSize: 11)),
                if (c.ports.isNotEmpty) Text(c.ports, style: const TextStyle(fontSize: 10)),
                if (c.composeProject != null)
                  Text('项目 ${c.composeProject}', style: const TextStyle(fontSize: 10, color: AppColors.gray)),
                if (c.createdAt != null)
                  Text(c.createdAt!, style: const TextStyle(fontSize: 10, color: AppColors.gray)),
                if (note?.note != null && note!.note!.isNotEmpty)
                  Text(note.note!, style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
            trailing: _statusBadge(c),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                if (!c.isRunning && !c.isPaused)
                  _actionBtn('启动', () => _runAction(c, () => _api()!.start(c.id), '启动')),
                if (c.isRunning && !c.isPaused) ...[
                  _actionBtn('停止', () => _runAction(c, () => _api()!.stop(c.id), '停止')),
                  _actionBtn('重启', () => _runAction(c, () => _api()!.restart(c.id), '重启')),
                  _actionBtn('暂停', () => _runAction(c, () => _api()!.pause(c.id), '暂停')),
                ],
                if (c.isPaused)
                  _actionBtn('继续', () => _runAction(c, () => _api()!.unpause(c.id), '继续')),
                _actionBtn(
                  '日志',
                  () => setState(() => _expandedLogsId = showLogs ? null : c.id),
                ),
                if (api != null)
                  _actionBtn(
                    '详情',
                    () => showDockerContainerDetailSheet(context: context, api: api, container: c),
                  ),
                _actionBtn('更多', () => _showMoreMenu(c)),
              ],
            ),
          ),
          if (showLogs && api != null)
            DockerLogsPanel(
              api: api,
              container: c,
              onClose: () => setState(() => _expandedLogsId = null),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(DockerContainerInfo c) {
    Color bg;
    Color fg;
    if (c.isPaused) {
      bg = const Color(0xFFFFF3E0);
      fg = Colors.orange.shade900;
    } else if (c.isRunning) {
      bg = const Color(0xFFE8F5E9);
      fg = Colors.green.shade800;
    } else {
      bg = const Color(0xFFF5F5F5);
      fg = AppColors.gray;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(c.state, style: TextStyle(fontSize: 11, color: fg)),
    );
  }

  Widget _actionBtn(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: _loading ? null : onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
