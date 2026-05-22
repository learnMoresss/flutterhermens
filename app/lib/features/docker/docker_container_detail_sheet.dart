import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/network/docker_admin_api.dart';
import '../../core/theme/app_colors.dart';

Future<void> showDockerContainerDetailSheet({
  required BuildContext context,
  required DockerAdminApi api,
  required DockerContainerInfo container,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _DockerContainerDetailSheet(api: api, container: container),
    ),
  );
}

class _DockerContainerDetailSheet extends StatefulWidget {
  const _DockerContainerDetailSheet({required this.api, required this.container});

  final DockerAdminApi api;
  final DockerContainerInfo container;

  @override
  State<_DockerContainerDetailSheet> createState() => _DockerContainerDetailSheetState();
}

class _DockerContainerDetailSheetState extends State<_DockerContainerDetailSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _detail = {};
  DockerContainerStatsInfo? _stats;
  bool _showRawJson = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.inspect(widget.container.id);
      DockerContainerStatsInfo? stats;
      if (widget.container.isRunning) {
        try {
          stats = await widget.api.fetchStats(widget.container.id);
        } on Object {
          stats = null;
        }
      }
      if (mounted) {
        setState(() {
          _detail = detail;
          _stats = stats;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grayLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.container.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020))))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
                        children: [
                            if (_stats != null) _buildStatsRow(_stats!),
                            ..._buildParsedSections(),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => setState(() => _showRawJson = !_showRawJson),
                              child: Row(
                                children: [
                                  Icon(
                                    _showRawJson ? Icons.expand_less : Icons.expand_more,
                                    size: 18,
                                    color: AppColors.gray,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text('查看原始 JSON', style: TextStyle(fontSize: 12, color: AppColors.gray)),
                                ],
                              ),
                            ),
                            if (_showRawJson) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  const JsonEncoder.withIndent('  ').convert(_detail),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: Color(0xFFD4D4D4),
                                  ),
                                ),
                              ),
                            ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(DockerContainerStatsInfo s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.grayLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('资源占用', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('CPU ${s.cpuPercent}  ·  内存 ${s.memUsage} (${s.memPercent})', style: const TextStyle(fontSize: 11)),
          if (s.netIO.isNotEmpty)
            Text('网络 ${s.netIO}  ·  磁盘 ${s.blockIO}', style: const TextStyle(fontSize: 11, color: AppColors.gray)),
        ],
      ),
    );
  }

  List<Widget> _buildParsedSections() {
    final config = _map(_detail['Config']);
    final state = _map(_detail['State']);
    final network = _map(_detail['NetworkSettings']);
    final ports = network['Ports'];
    final mounts = _detail['Mounts'];
    final labels = config['Labels'];

    return [
      _section('状态', [
        _row('运行', state['Running']?.toString() ?? ''),
        _row('状态', state['Status']?.toString() ?? widget.container.status),
        _row('启动于', state['StartedAt']?.toString() ?? ''),
        _row('镜像', config['Image']?.toString() ?? widget.container.image),
      ]),
      if (ports != null) _section('端口映射', _formatPorts(ports)),
      if (mounts is List && mounts.isNotEmpty)
        _section(
          '挂载',
          mounts.whereType<Map>().map((m) {
            final mm = Map<String, dynamic>.from(m);
            return _row(
              mm['Destination']?.toString() ?? '',
              '${mm['Type'] ?? ''} ${mm['Source'] ?? ''}',
            );
          }).toList(),
        ),
      if (config['Env'] is List && (config['Env'] as List).isNotEmpty)
        _ExpandableEnvSection(env: List<String>.from(config['Env'] as List)),
      if (labels is Map && labels.isNotEmpty)
        _section(
          'Labels',
          labels.entries.map((e) => _row(e.key.toString(), e.value.toString())).toList(),
        ),
    ];
  }

  List<Widget> _formatPorts(dynamic ports) {
    if (ports is! Map) return [_row('—', ports.toString())];
    final rows = <Widget>[];
    for (final entry in ports.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val is List) {
        for (final b in val) {
          if (b is Map) {
            final host = b['HostIp'] != null && '${b['HostIp']}' != ''
                ? '${b['HostIp']}:'
                : '';
            rows.add(_row(key, '$host${b['HostPort'] ?? ''}'));
          }
        }
      } else {
        rows.add(_row(key, val?.toString() ?? ''));
      }
    }
    return rows.isEmpty ? [_row('—', '无')] : rows;
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }
}

class _ExpandableEnvSection extends StatefulWidget {
  const _ExpandableEnvSection({required this.env});

  final List<String> env;

  @override
  State<_ExpandableEnvSection> createState() => _ExpandableEnvSectionState();
}

class _ExpandableEnvSectionState extends State<_ExpandableEnvSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final shown = _expanded ? widget.env : widget.env.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('环境变量', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (widget.env.length > 5)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? '收起' : '展开全部 (${widget.env.length})'),
                ),
            ],
          ),
          ...shown.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}
