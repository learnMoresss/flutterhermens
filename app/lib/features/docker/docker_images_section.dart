import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/docker_admin_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_message.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/mono_button.dart';

class DockerImagesSection extends ConsumerStatefulWidget {
  const DockerImagesSection({super.key});

  @override
  ConsumerState<DockerImagesSection> createState() => _DockerImagesSectionState();
}

class _DockerImagesSectionState extends ConsumerState<DockerImagesSection> {
  bool _expanded = false;
  bool _loading = false;
  List<DockerImageInfo> _images = const [];

  DockerAdminApi? _api() {
    final session = ref.read(userSessionProvider);
    if (session.token == null || session.token!.isEmpty) return null;
    return DockerAdminApi.fromClient(ref.read(gatewayClientProvider));
  }

  Future<void> _load() async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final list = await api.listImages();
      if (mounted) setState(() => _images = list);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmPruneImages() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理未使用镜像'),
        content: const Text('将删除所有悬空（dangling）镜像，不可恢复。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清理')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runPrune(['images']);
  }

  Future<void> _confirmPruneContainers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理已停止容器'),
        content: const Text('将删除所有已停止的容器，不可恢复。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清理')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runPrune(['containers']);
  }

  Future<void> _runPrune(List<String> targets) async {
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final result = await api.prune(targets);
      final summary = result.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      if (mounted) AppMessage.success(summary.isEmpty ? '清理完成' : summary);
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmRemoveImage(DockerImageInfo img) async {
    var force = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('删除镜像'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${img.fullName}\n${img.id}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('强制删除', style: TextStyle(fontSize: 13)),
                  value: force,
                  onChanged: (v) => setDialogState(() => force = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
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
    final api = _api();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final ref = img.id.isNotEmpty ? img.id : img.fullName;
      await api.removeImage(ref, force: force);
      if (mounted) AppMessage.success('已删除 ${img.fullName}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _images.isEmpty) _load();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                const SizedBox(width: 4),
                Text(
                  _expanded ? '镜像列表 (${_images.length})' : '镜像与清理',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (_loading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          ..._images.map(
            (img) => ListTile(
              dense: true,
              title: Text(img.fullName, style: const TextStyle(fontSize: 12)),
              subtitle: Text('${img.size} · ${img.id}', style: const TextStyle(fontSize: 10)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB00020)),
                onPressed: _loading ? null : () => _confirmRemoveImage(img),
              ),
            ),
          ),
          const SizedBox(height: 8),
          MonoButton(
            label: '清理未使用镜像',
            outlined: true,
            onPressed: _loading ? null : _confirmPruneImages,
          ),
          const SizedBox(height: 8),
          MonoButton(
            label: '清理已停止容器',
            outlined: true,
            onPressed: _loading ? null : _confirmPruneContainers,
          ),
          const SizedBox(height: 4),
          Text(
            '危险操作不可恢复，请确认无重要数据。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
