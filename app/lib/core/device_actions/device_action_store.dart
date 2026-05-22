import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_action_model.dart';

/// 持久化设备操作卡片状态（scopeKey::actionId → status）。
/// scopeKey 优先使用 Hermes sessionId，新对话尚未分配 session 时用 msg:{messageId}。
class DeviceActionStore {
  DeviceActionStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'device_action_states_v1';

  String _compoundKey(String scopeKey, String actionId) => '$scopeKey::$actionId';

  Map<String, dynamic> _loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on Object {
      return {};
    }
  }

  Future<void> _saveAll(Map<String, dynamic> data) async {
    await _prefs.setString(_key, jsonEncode(data));
  }

  DeviceActionStatus getStatus(String scopeKey, String actionId) {
    final all = _loadAll();
    final entry = all[_compoundKey(scopeKey, actionId)];
    if (entry is! Map) return DeviceActionStatus.pending;
    final s = entry['status']?.toString();
    return DeviceActionStatus.values.firstWhere(
      (v) => v.name == s,
      orElse: () => DeviceActionStatus.pending,
    );
  }

  String? getError(String scopeKey, String actionId) {
    final all = _loadAll();
    final entry = all[_compoundKey(scopeKey, actionId)];
    if (entry is! Map) return null;
    return entry['error']?.toString();
  }

  Future<void> setStatus(
    String scopeKey,
    String actionId,
    DeviceActionStatus status, {
    String? error,
  }) async {
    final all = _loadAll();
    all[_compoundKey(scopeKey, actionId)] = {
      'status': status.name,
      if (error != null && error.isNotEmpty) 'error': error,
    };
    await _saveAll(all);
  }

  Future<void> migrateScope({
    required String fromScope,
    required String toScope,
    required String actionId,
  }) async {
    if (fromScope == toScope) return;
    final all = _loadAll();
    final fromKey = _compoundKey(fromScope, actionId);
    final toKey = _compoundKey(toScope, actionId);
    if (!all.containsKey(fromKey)) return;
    final existing = all[toKey];
    if (existing == null) {
      all[toKey] = all[fromKey];
    }
    all.remove(fromKey);
    await _saveAll(all);
  }

  DeviceAction applyStoredStatus(String scopeKey, DeviceAction action) {
    final storedStatus = getStatus(scopeKey, action.id);
    final storedError = getError(scopeKey, action.id);
    final resolvedStatus = storedStatus != DeviceActionStatus.pending
        ? storedStatus
        : action.status;
    final resolvedError = storedError ?? action.errorMessage;
    if (resolvedStatus == action.status && resolvedError == action.errorMessage) {
      return action;
    }
    return action.copyWith(status: resolvedStatus, errorMessage: resolvedError);
  }
}
