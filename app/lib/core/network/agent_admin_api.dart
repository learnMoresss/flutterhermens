import 'package:dio/dio.dart';

import 'api_client.dart';

class HermesSavedModel {
  const HermesSavedModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.model,
    this.baseUrl = '',
  });

  final String id;
  final String name;
  final String provider;
  final String model;
  final String baseUrl;

  factory HermesSavedModel.fromJson(Map<String, dynamic> json) {
    return HermesSavedModel(
      id: (json['id'] ?? json['model'] ?? '').toString(),
      name: (json['name'] ?? json['model'] ?? '未命名').toString(),
      provider: (json['provider'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
    );
  }

  String get displayLabel => name.isNotEmpty ? name : model;
}

class AgentToolset {
  const AgentToolset({
    required this.key,
    required this.label,
    required this.description,
    required this.enabled,
  });

  final String key;
  final String label;
  final String description;
  final bool enabled;

  factory AgentToolset.fromJson(Map<String, dynamic> json) {
    return AgentToolset(
      key: json['key'].toString(),
      label: (json['label'] ?? json['key']).toString(),
      description: (json['description'] ?? '').toString(),
      enabled: json['enabled'] == true,
    );
  }
}

class AgentSkill {
  const AgentSkill({
    required this.name,
    required this.category,
    required this.description,
    this.id,
  });

  final String name;
  final String category;
  final String description;
  final String? id;

  factory AgentSkill.fromJson(Map<String, dynamic> json) {
    return AgentSkill(
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      id: json['id']?.toString(),
    );
  }
}

class BundledSkill {
  const BundledSkill({
    required this.name,
    required this.category,
    required this.description,
    required this.source,
    required this.installed,
    required this.id,
  });

  final String name;
  final String category;
  final String description;
  final String source;
  final bool installed;
  final String id;

  factory BundledSkill.fromJson(Map<String, dynamic> json) {
    return BundledSkill(
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      installed: json['installed'] == true,
      id: (json['id'] ?? '').toString(),
    );
  }
}

class MemoryEntry {
  const MemoryEntry({required this.index, required this.content});
  final int index;
  final String content;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      index: json['index'] is num ? (json['index'] as num).toInt() : 0,
      content: (json['content'] ?? '').toString(),
    );
  }
}

class AgentMemoryData {
  const AgentMemoryData({
    required this.memoryEntries,
    required this.memoryCharCount,
    required this.memoryCharLimit,
    required this.userContent,
    required this.userCharCount,
    required this.userCharLimit,
    required this.totalSessions,
    required this.totalMessages,
  });

  final List<MemoryEntry> memoryEntries;
  final int memoryCharCount;
  final int memoryCharLimit;
  final String userContent;
  final int userCharCount;
  final int userCharLimit;
  final int totalSessions;
  final int totalMessages;

  factory AgentMemoryData.fromJson(Map<String, dynamic> json) {
    final memory = json['memory'];
    final user = json['user'];
    final stats = json['stats'];
    final memMap = memory is Map ? Map<String, dynamic>.from(memory) : <String, dynamic>{};
    final userMap = user is Map ? Map<String, dynamic>.from(user) : <String, dynamic>{};
    final statsMap = stats is Map ? Map<String, dynamic>.from(stats) : <String, dynamic>{};
    final entries = memMap['entries'];
    return AgentMemoryData(
      memoryEntries: entries is List
          ? entries
              .whereType<Map>()
              .map((e) => MemoryEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
      memoryCharCount: memMap['charCount'] is num ? (memMap['charCount'] as num).toInt() : 0,
      memoryCharLimit: memMap['charLimit'] is num ? (memMap['charLimit'] as num).toInt() : 2200,
      userContent: (userMap['content'] ?? '').toString(),
      userCharCount: userMap['charCount'] is num ? (userMap['charCount'] as num).toInt() : 0,
      userCharLimit: userMap['charLimit'] is num ? (userMap['charLimit'] as num).toInt() : 1375,
      totalSessions: statsMap['totalSessions'] is num ? (statsMap['totalSessions'] as num).toInt() : 0,
      totalMessages: statsMap['totalMessages'] is num ? (statsMap['totalMessages'] as num).toInt() : 0,
    );
  }
}

class AgentProfile {
  const AgentProfile({
    required this.name,
    required this.isDefault,
    required this.isActive,
    required this.model,
    required this.provider,
    required this.hasEnv,
    required this.hasSoul,
    required this.skillCount,
  });

  final String name;
  final bool isDefault;
  final bool isActive;
  final String model;
  final String provider;
  final bool hasEnv;
  final bool hasSoul;
  final int skillCount;

  factory AgentProfile.fromJson(Map<String, dynamic> json) {
    return AgentProfile(
      name: json['name'].toString(),
      isDefault: json['isDefault'] == true,
      isActive: json['isActive'] == true,
      model: (json['model'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      hasEnv: json['hasEnv'] == true,
      hasSoul: json['hasSoul'] == true,
      skillCount: json['skillCount'] is num ? (json['skillCount'] as num).toInt() : 0,
    );
  }

  String get displayName => isDefault ? '默认档案' : name;
}

class EnvKeyInfo {
  const EnvKeyInfo({
    required this.key,
    required this.label,
    required this.category,
    required this.configured,
    required this.maskedValue,
  });

  final String key;
  final String label;
  final String category;
  final bool configured;
  final String maskedValue;

  factory EnvKeyInfo.fromJson(Map<String, dynamic> json) {
    return EnvKeyInfo(
      key: json['key'].toString(),
      label: (json['label'] ?? json['key']).toString(),
      category: (json['category'] ?? '其他').toString(),
      configured: json['configured'] == true,
      maskedValue: (json['maskedValue'] ?? '').toString(),
    );
  }
}

class AgentAdminApi {
  AgentAdminApi(this._dio);

  factory AgentAdminApi.fromClient(ApiClient client) => AgentAdminApi(client.dio);

  final Dio _dio;

  Future<List<HermesSavedModel>> listModels() async {
    final data = await _get('/v1/admin/agent/models');
    final list = data['models'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => HermesSavedModel.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.model.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<AgentToolset>> listToolsets() async {
    final data = await _get('/v1/admin/agent/toolsets');
    final list = data['toolsets'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AgentToolset.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<AgentToolset>> setToolset(String key, bool enabled) async {
    final data = await _put('/v1/admin/agent/toolsets/$key', {'enabled': enabled});
    final list = data['toolsets'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AgentToolset.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<String> getSoul() async {
    final data = await _get('/v1/admin/agent/soul');
    return (data['content'] ?? '').toString();
  }

  Future<void> saveSoul(String content) async {
    await _put('/v1/admin/agent/soul', {'content': content});
  }

  Future<String> resetSoul() async {
    final response = await _dio.post<Map<String, dynamic>>('/v1/admin/agent/soul/reset');
    return (response.data?['content'] ?? '').toString();
  }

  Future<List<AgentSkill>> listSkills() async {
    final data = await _get('/v1/admin/agent/skills');
    final list = data['skills'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AgentSkill.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<AgentProfile>> listProfiles() async {
    final data = await _get('/v1/admin/agent/profiles');
    final list = data['profiles'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AgentProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<AgentProfile>> activateProfile(String name) async {
    final data = await _post('/v1/admin/agent/profiles/$name/activate');
    final list = data['profiles'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AgentProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<({List<EnvKeyInfo> keys, String provider, String model, String baseUrl})> listProviders() async {
    final data = await _get('/v1/admin/agent/providers');
    final list = data['keys'];
    final config = data['config'];
    final keys = list is List
        ? list
            .whereType<Map>()
            .map((e) => EnvKeyInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : <EnvKeyInfo>[];
    final cfg = config is Map ? Map<String, dynamic>.from(config) : <String, dynamic>{};
    return (
      keys: keys,
      provider: (cfg['provider'] ?? '').toString(),
      model: (cfg['model'] ?? '').toString(),
      baseUrl: (cfg['baseUrl'] ?? '').toString(),
    );
  }

  Future<Map<String, dynamic>> getStatus() async => _get('/v1/admin/agent/status');

  Future<HermesSavedModel> addModel({
    required String name,
    required String provider,
    required String model,
    String baseUrl = '',
  }) async {
    final data = await _postBody('/v1/admin/agent/models', {
      'name': name,
      'provider': provider,
      'model': model,
      'baseUrl': baseUrl,
    });
    final m = data['model'];
    if (m is Map) return HermesSavedModel.fromJson(Map<String, dynamic>.from(m));
    throw ApiException('添加模型失败');
  }

  Future<List<HermesSavedModel>> updateModel(
    String id, {
    String? name,
    String? provider,
    String? model,
    String? baseUrl,
  }) async {
    await _put('/v1/admin/agent/models/$id', {
      if (name != null) 'name': name,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
    });
    return listModels();
  }

  Future<List<HermesSavedModel>> removeModel(String id) async {
    await _delete('/v1/admin/agent/models/$id');
    return listModels();
  }

  Future<List<EnvKeyInfo>> setEnvKey(String key, String value) async {
    final data = await _put('/v1/admin/agent/providers/env', {'key': key, 'value': value});
    final list = data['keys'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => EnvKeyInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<({List<EnvKeyInfo> keys, String provider, String model, String baseUrl})> setProviderConfig({
    String? provider,
    String? model,
    String? baseUrl,
  }) async {
    final data = await _put('/v1/admin/agent/providers/config', {
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
    });
    final list = data['keys'];
    final config = data['config'];
    final keys = list is List
        ? list
            .whereType<Map>()
            .map((e) => EnvKeyInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : <EnvKeyInfo>[];
    final cfg = config is Map ? Map<String, dynamic>.from(config) : <String, dynamic>{};
    return (
      keys: keys,
      provider: (cfg['provider'] ?? '').toString(),
      model: (cfg['model'] ?? '').toString(),
      baseUrl: (cfg['baseUrl'] ?? '').toString(),
    );
  }

  Future<List<AgentProfile>> createProfile(String name, {bool clone = false}) async {
    final data = await _postBody('/v1/admin/agent/profiles', {'name': name, 'clone': clone});
    return _parseProfiles(data['profiles']);
  }

  Future<List<AgentProfile>> deleteProfile(String name) async {
    final data = await _delete('/v1/admin/agent/profiles/$name');
    return _parseProfiles(data['profiles']);
  }

  Future<List<BundledSkill>> listBundledSkills() async {
    final data = await _get('/v1/admin/agent/skills/bundled');
    final list = data['skills'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => BundledSkill.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<String> getSkillContent(String id) async {
    final encoded = Uri.encodeComponent(id);
    final data = await _get('/v1/admin/agent/skills/$encoded/content');
    return (data['content'] ?? '').toString();
  }

  Future<List<AgentSkill>> installSkill(String id) async {
    final encoded = Uri.encodeComponent(id);
    await _post('/v1/admin/agent/skills/$encoded');
    return listSkills();
  }

  Future<List<AgentSkill>> uninstallSkill(String id) async {
    final encoded = Uri.encodeComponent(id);
    final data = await _delete('/v1/admin/agent/skills/$encoded');
    return _parseSkills(data['skills']);
  }

  Future<AgentMemoryData> getMemory() async {
    final data = await _get('/v1/admin/agent/memory');
    return AgentMemoryData.fromJson(data);
  }

  Future<AgentMemoryData> addMemoryEntry(String content) async {
    final data = await _postBody('/v1/admin/agent/memory/entries', {'content': content});
    return AgentMemoryData.fromJson(data);
  }

  Future<AgentMemoryData> updateMemoryEntry(int index, String content) async {
    final data = await _put('/v1/admin/agent/memory/entries/$index', {'content': content});
    return AgentMemoryData.fromJson(data);
  }

  Future<AgentMemoryData> removeMemoryEntry(int index) async {
    final data = await _delete('/v1/admin/agent/memory/entries/$index');
    return AgentMemoryData.fromJson(data);
  }

  Future<AgentMemoryData> saveUserProfile(String content) async {
    final data = await _put('/v1/admin/agent/memory/user', {'content': content});
    return AgentMemoryData.fromJson(data);
  }

  Future<Map<String, bool>> listPlatforms() async {
    final data = await _get('/v1/admin/agent/platforms');
    final platforms = data['platforms'];
    if (platforms is! Map) return {};
    return platforms.map((k, v) => MapEntry(k.toString(), v == true));
  }

  Future<Map<String, bool>> setPlatform(String key, bool enabled) async {
    final data = await _put('/v1/admin/agent/platforms/$key', {'enabled': enabled});
    final platforms = data['platforms'];
    if (platforms is! Map) return {};
    return platforms.map((k, v) => MapEntry(k.toString(), v == true));
  }

  List<AgentProfile> _parseProfiles(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AgentProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  List<AgentSkill> _parseSkills(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AgentSkill.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      return response.data ?? {};
    } on DioException catch (e) {
      throw _wrap(e, '请求失败');
    }
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(path, data: body);
      return response.data ?? {};
    } on DioException catch (e) {
      throw _wrap(e, '保存失败');
    }
  }

  Future<Map<String, dynamic>> _post(String path) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path);
      return response.data ?? {};
    } on DioException catch (e) {
      throw _wrap(e, '操作失败');
    }
  }

  Future<Map<String, dynamic>> _postBody(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return response.data ?? {};
    } on DioException catch (e) {
      throw _wrap(e, '操作失败');
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(path);
      return response.data ?? {};
    } on DioException catch (e) {
      throw _wrap(e, '删除失败');
    }
  }

  ApiException _wrap(DioException e, String fallback) {
    return ApiException(
      e.response?.data?['message'] as String? ?? e.message ?? fallback,
      statusCode: e.response?.statusCode,
    );
  }
}
