import 'dart:convert';

import 'device_action_model.dart';

final _blockPattern = RegExp(
  r'```hermes-device-action\s*\r?\n([\s\S]*?)\r?\n```',
  multiLine: true,
);

class ParsedAssistantContent {
  const ParsedAssistantContent({
    required this.displayText,
    required this.actions,
  });

  final String displayText;
  final List<DeviceAction> actions;
}

ParsedAssistantContent parseAssistantContent(String raw) {
  final actions = <DeviceAction>[];
  var display = raw;

  for (final match in _blockPattern.allMatches(raw)) {
    final jsonStr = match.group(1)?.trim();
    if (jsonStr == null || jsonStr.isEmpty) continue;
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final action = DeviceAction.fromJson(json);
      if (action.id.isNotEmpty && action.type != DeviceActionType.unknown) {
        actions.add(action);
      }
    } on Object {
      /* skip invalid block */
    }
    display = display.replaceFirst(match.group(0)!, '').trim();
  }

  display = display.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return ParsedAssistantContent(displayText: display, actions: actions);
}

String stripDeviceActionBlocks(String raw) => parseAssistantContent(raw).displayText;

/// 将消息内指定 action 的 JSON 块更新为最新状态（写回 assistant 消息正文）。
String patchDeviceActionInMessage(String raw, DeviceAction action) {
  var changed = false;
  final result = raw.replaceAllMapped(_blockPattern, (match) {
    final jsonStr = match.group(1)?.trim();
    if (jsonStr == null || jsonStr.isEmpty) return match.group(0)!;
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if ((json['id'] ?? '').toString() != action.id) return match.group(0)!;
      changed = true;
      final encoded = jsonEncode(action.toJson(includeRuntime: true));
      return '```hermes-device-action\n$encoded\n```';
    } on Object {
      return match.group(0)!;
    }
  });
  return changed ? result : raw;
}
