import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/docker_admin_api.dart';
import '../../core/ui/app_message.dart';

class DockerLogsPanel extends StatefulWidget {
  const DockerLogsPanel({
    super.key,
    required this.api,
    required this.container,
    required this.onClose,
  });

  final DockerAdminApi api;
  final DockerContainerInfo container;
  final VoidCallback onClose;

  @override
  State<DockerLogsPanel> createState() => _DockerLogsPanelState();
}

class _DockerLogsPanelState extends State<DockerLogsPanel> {
  static const _tailOptions = [100, 500, 2000];

  int _tail = 200;
  bool _loading = false;
  String? _logs;
  String? _error;

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
      final text = await widget.api.fetchLogs(widget.container.id, tail: _tail);
      if (mounted) setState(() => _logs = text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final text = _logs ?? '';
    if (text.isEmpty) {
      AppMessage.error('无日志可复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    AppMessage.success('已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('日志', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _tailOptions.contains(_tail) ? _tail : 200,
                isDense: true,
                items: _tailOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('tail $n', style: const TextStyle(fontSize: 11))))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _tail = v);
                        _load();
                      },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制',
                onPressed: _loading ? null : _copy,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _loading
                    ? '加载中…'
                    : (_error ?? _logs ?? '无日志'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFD4D4D4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
