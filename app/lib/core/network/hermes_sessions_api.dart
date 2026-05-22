import 'package:dio/dio.dart';

import '../chat/session_display_sanitize.dart';
import 'api_client.dart';

class HermesSessionSummary {
  const HermesSessionSummary({
    required this.id,
    required this.title,
    this.model,
    this.messageCount = 0,
    this.updatedAt,
    this.preview,
    this.snippet,
  });

  final String id;
  final String title;
  final String? model;
  final int messageCount;
  final DateTime? updatedAt;
  final String? preview;
  final String? snippet;

  factory HermesSessionSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    final id = (json['id'] ?? json['session_id'] ?? json['sessionId'] ?? '').toString();
    final titleRaw = json['title'] ?? json['name'] ?? json['preview'];
    final rawTitle = (titleRaw?.toString().trim().isNotEmpty == true)
        ? titleRaw.toString()
        : '会话 $id';
    return HermesSessionSummary(
      id: id,
      title: sanitizeSessionTitle(rawTitle, sessionId: id),
      model: json['model']?.toString(),
      messageCount: HermesSessionsApi.asInt(json['message_count'] ?? json['messageCount'] ?? 0),
      updatedAt: parseTime(json['updated_at'] ?? json['updatedAt'] ?? json['last_active'] ?? json['startedAt']),
      preview: sanitizeSessionSnippet(json['preview']?.toString()),
      snippet: sanitizeSessionSnippet(json['snippet']?.toString()),
    );
  }
}

class HermesSessionMessage {
  const HermesSessionMessage({
    required this.role,
    required this.content,
    this.createdAt,
  });

  final String role;
  final String content;
  final DateTime? createdAt;

  factory HermesSessionMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    String extractContent(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) return raw;
      if (raw is List) {
        final parts = <String>[];
        for (final item in raw) {
          if (item is Map) {
            if (item['type'] == 'text' && item['text'] != null) {
              parts.add(item['text'].toString());
            } else if (item['type'] == 'image_url') {
              final imageUrl = item['image_url'];
              if (imageUrl is Map && imageUrl['url'] != null) {
                final url = imageUrl['url'].toString();
                if (url.startsWith('http://') || url.startsWith('https://')) {
                  parts.add('![图片]($url)');
                } else if (url.startsWith('data:')) {
                  parts.add('[图片]');
                } else {
                  parts.add('[图片: $url]');
                }
              } else {
                parts.add('[图片]');
              }
            }
          }
        }
        return parts.join('\n');
      }
      return raw.toString();
    }

    return HermesSessionMessage(
      role: (json['role'] ?? 'user').toString(),
      content: extractContent(json['content']),
      createdAt: parseTime(json['created_at'] ?? json['createdAt'] ?? json['timestamp']),
    );
  }
}

class HermesSessionsApi {
  HermesSessionsApi(this._dio);

  final Dio _dio;

  factory HermesSessionsApi.fromClient(ApiClient client) =>
      HermesSessionsApi(client.dio);

  Future<List<HermesSessionSummary>> listSessions() async {
    try {
      final response = await _dio.get<Object?>('/v1/sessions');
      return _parseSessionList(response.data);
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data is Map && (e.response!.data as Map)['message'] != null
            ? (e.response!.data as Map)['message'].toString()
            : (e.message ?? '加载会话列表失败'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<HermesSessionSummary>> searchSessions(String query) async {
    try {
      final response = await _dio.get<Object?>(
        '/v1/sessions/search',
        queryParameters: {'q': query},
      );
      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => HermesSessionSummary.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }
      if (data is Map && data['results'] is List) {
        return (data['results'] as List)
            .whereType<Map>()
            .map((e) => HermesSessionSummary.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }
      return _parseSessionList(data);
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data is Map && (e.response!.data as Map)['message'] != null
            ? (e.response!.data as Map)['message'].toString()
            : (e.message ?? '搜索会话失败'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<HermesSessionMessage>> loadMessages(String sessionId) async {
    try {
      final response = await _dio.get<Object?>('/v1/sessions/$sessionId/messages');
      final data = response.data;
      final list = data is Map && data['messages'] is List
          ? data['messages'] as List
          : data is List
              ? data
              : const [];
      return list
          .whereType<Map>()
          .map((e) => HermesSessionMessage.fromJson(Map<String, dynamic>.from(e)))
          .where(
            (m) =>
                (m.role == 'user' || m.role == 'assistant') &&
                !shouldHideHistoryMessage(m.role, m.content),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data is Map && (e.response!.data as Map)['message'] != null
            ? (e.response!.data as Map)['message'].toString()
            : (e.message ?? '加载历史消息失败'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    try {
      await _dio.patch<Object?>(
        '/v1/sessions/$sessionId',
        data: {'title': title},
      );
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data is Map && (e.response!.data as Map)['message'] != null
            ? (e.response!.data as Map)['message'].toString()
            : (e.message ?? '重命名会话失败'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _dio.delete<Object?>('/v1/sessions/$sessionId');
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data is Map && (e.response!.data as Map)['message'] != null
            ? (e.response!.data as Map)['message'].toString()
            : (e.message ?? '删除会话失败'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  static int asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  List<HermesSessionSummary> _parseSessionList(Object? data) {
    final list = data is Map && data['sessions'] is List
        ? data['sessions'] as List
        : data is List
            ? data
            : const [];
    return list
        .whereType<Map>()
        .map((e) => HermesSessionSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
