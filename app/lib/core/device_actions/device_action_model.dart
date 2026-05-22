enum DeviceActionStatus { pending, approved, denied, executed, failed }

enum DeviceActionType {
  notificationSchedule('notification.schedule'),
  calendarEvent('calendar.event'),
  calendarPrefill('calendar.prefill'),
  shareText('share.text'),
  clipboardWrite('clipboard.write'),
  settingsOpen('settings.open'),
  unknown('unknown');

  const DeviceActionType(this.apiValue);
  final String apiValue;

  static DeviceActionType parse(String raw) {
    final t = raw.trim();
    for (final v in DeviceActionType.values) {
      if (v.apiValue == t) return v;
    }
    return DeviceActionType.unknown;
  }
}

class DeviceAction {
  const DeviceAction({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.params,
    this.status = DeviceActionStatus.pending,
    this.errorMessage,
  });

  final String id;
  final DeviceActionType type;
  final String title;
  final String summary;
  final Map<String, dynamic> params;
  final DeviceActionStatus status;
  final String? errorMessage;

  String get storageKey => id;

  DeviceAction copyWith({
    DeviceActionStatus? status,
    String? errorMessage,
  }) {
    return DeviceAction(
      id: id,
      type: type,
      title: title,
      summary: summary,
      params: params,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory DeviceAction.fromJson(Map<String, dynamic> json) {
    return DeviceAction(
      id: (json['id'] ?? '').toString(),
      type: DeviceActionType.parse((json['type'] ?? '').toString()),
      title: (json['title'] ?? '设备操作').toString(),
      summary: (json['summary'] ?? '').toString(),
      params: json['params'] is Map
          ? Map<String, dynamic>.from(json['params'] as Map)
          : const {},
      status: _parseStatus(json['status']),
      errorMessage: (json['error'] ?? json['errorMessage'])?.toString(),
    );
  }

  static DeviceActionStatus _parseStatus(dynamic raw) {
    final name = raw?.toString();
    if (name == null || name.isEmpty) return DeviceActionStatus.pending;
    return DeviceActionStatus.values.firstWhere(
      (v) => v.name == name,
      orElse: () => DeviceActionStatus.pending,
    );
  }

  Map<String, dynamic> toJson({bool includeRuntime = false}) {
    final map = <String, dynamic>{
      'id': id,
      'type': type.apiValue,
      'title': title,
      'summary': summary,
      'params': params,
    };
    if (includeRuntime && status != DeviceActionStatus.pending) {
      map['status'] = status.name;
    }
    if (includeRuntime && errorMessage != null && errorMessage!.isNotEmpty) {
      map['error'] = errorMessage;
    }
    return map;
  }
}
