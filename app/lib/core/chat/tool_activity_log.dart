import '../network/api_client.dart';

const kChatMetaToolLogKey = 'toolLog';

/// Hermes 工具执行记录（来自 SSE `event: hermes.tool.progress`）。
class ToolActivityEntry {
  const ToolActivityEntry({
    required this.toolCallId,
    required this.tool,
    required this.label,
    required this.status,
  });

  final String toolCallId;
  final String tool;
  final String label;
  final String status;

  bool get isRunning => status == 'running' || status == 'started';
  bool get isCompleted => status == 'completed' || status == 'complete' || status == 'done';

  String get displayLine {
    final icon = _toolIcon(tool);
    final suffix = isCompleted ? ' ✓' : ' …';
    return '$icon $tool · $label$suffix';
  }

  Map<String, dynamic> toJson() => {
        'toolCallId': toolCallId,
        'tool': tool,
        'label': label,
        'status': status,
      };

  factory ToolActivityEntry.fromJson(Map<String, dynamic> json) {
    return ToolActivityEntry(
      toolCallId: (json['toolCallId'] ?? json['call_id'] ?? '').toString(),
      tool: (json['tool'] ?? 'tool').toString(),
      label: (json['label'] ?? json['message'] ?? json['detail'] ?? '').toString(),
      status: (json['status'] ?? 'running').toString(),
    );
  }

  ToolActivityEntry copyWith({String? status, String? label}) {
    return ToolActivityEntry(
      toolCallId: toolCallId,
      tool: tool,
      label: label ?? this.label,
      status: status ?? this.status,
    );
  }
}

String _toolIcon(String tool) {
  switch (tool) {
    case 'terminal':
      return '⌨️';
    case 'web_search':
      return '🔍';
    case 'vision_analyze':
      return '👁️';
    case 'file':
    case 'read_file':
    case 'write_file':
      return '📄';
    default:
      return '🔧';
  }
}

List<ToolActivityEntry> parseToolLog(Map<String, dynamic>? metadata) {
  final raw = metadata?[kChatMetaToolLogKey];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => ToolActivityEntry.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

Map<String, dynamic>? buildToolLogMetadata(List<ToolActivityEntry> entries) {
  if (entries.isEmpty) return null;
  return {
    kChatMetaToolLogKey: entries.map((e) => e.toJson()).toList(growable: false),
  };
}

Map<String, dynamic>? mergeToolLogMetadata(
  Map<String, dynamic>? existing,
  List<ToolActivityEntry> entries,
) {
  final logMeta = buildToolLogMetadata(entries);
  if (logMeta == null) return existing;
  if (existing == null) return logMeta;
  return {...existing, ...logMeta};
}

List<ToolActivityEntry> upsertToolLogEntry(
  List<ToolActivityEntry> entries,
  ChatToolProgress event,
) {
  final id = event.toolCallId ?? '${event.tool ?? 'tool'}_${entries.length}';
  final next = List<ToolActivityEntry>.of(entries);
  final idx = next.indexWhere((e) => e.toolCallId == id);
  final entry = ToolActivityEntry(
    toolCallId: id,
    tool: event.tool ?? 'tool',
    label: event.label ?? event.detail,
    status: event.status ?? 'running',
  );
  if (idx >= 0) {
    next[idx] = entry;
  } else {
    next.add(entry);
  }
  return next;
}

String formatToolLogSummary(List<ToolActivityEntry> entries) {
  if (entries.isEmpty) return '';
  return entries.map((e) => e.displayLine).join('\n');
}
