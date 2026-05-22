import 'dart:convert';

import 'package:dio/dio.dart';

import '../../shared/models/user_session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// SSE 流式回调
sealed class ChatStreamEvent {
  const ChatStreamEvent();

  bool get isText => this is ChatTextDelta;
  bool get isToolProgress => this is ChatToolProgress;
}

class ChatTextDelta extends ChatStreamEvent {
  const ChatTextDelta(this.text);
  final String text;
}

class ChatToolProgress extends ChatStreamEvent {
  const ChatToolProgress({
    required this.detail,
    this.tool,
    this.label,
    this.status,
    this.toolCallId,
  });

  final String detail;
  final String? tool;
  final String? label;
  final String? status;
  final String? toolCallId;
}

class ChatUsageStats extends ChatStreamEvent {
  const ChatUsageStats({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.cost,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double? cost;
}

class GatewayUploadedFile {
  const GatewayUploadedFile({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.downloadPath,
    this.base64,
    this.url,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int size;
  final String downloadPath;
  final String? base64;
  final String? url;
}

/// 所有请求发往配置的 Gateway（由 Gateway 再转发 Hermes）。
class ApiClient {
  ApiClient({
    required String baseUrl,
    String? token,
    Future<String?> Function()? onRefreshToken,
  }) : _onRefreshToken = onRefreshToken,
       _dio = Dio(
          BaseOptions(
            baseUrl: normalizeBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(minutes: 5),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final method = options.method.toUpperCase();
          final hasBody = options.data != null;

          if ((method == 'POST' || method == 'PUT' || method == 'PATCH') && !hasBody) {
            final ct = options.contentType ?? options.headers['Content-Type']?.toString() ?? '';
            if (ct.contains('application/json')) {
              options.data = const <String, dynamic>{};
            }
          }

          // DELETE/GET 无 body 时勿带 application/json，避免 Fastify 报 empty body
          if ((method == 'DELETE' || method == 'GET' || method == 'HEAD') && !hasBody) {
            options.data = null;
            options.contentType = null;
            options.headers.remove('Content-Type');
          }

          handler.next(options);
        },
      ),
    );
    final refreshToken = _onRefreshToken;
    if (refreshToken != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) async {
            if (error.response?.statusCode != 401) {
              return handler.next(error);
            }
            if (_refreshInFlight != null) {
              try {
                final newToken = await _refreshInFlight;
                if (newToken != null && newToken.isNotEmpty) {
                  error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
                  final response = await _dio.fetch<dynamic>(error.requestOptions);
                  return handler.resolve(response);
                }
              } on Object {
                /* fall through */
              }
              return handler.next(error);
            }
            _refreshInFlight = refreshToken();
            try {
              final newToken = await _refreshInFlight;
              if (newToken != null && newToken.isNotEmpty) {
                updateToken(newToken);
                error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
                final response = await _dio.fetch<dynamic>(error.requestOptions);
                return handler.resolve(response);
              }
            } finally {
              _refreshInFlight = null;
            }
            return handler.next(error);
          },
        ),
      );
    }
  }

  final Dio _dio;
  final Future<String?> Function()? _onRefreshToken;
  Future<String?>? _refreshInFlight;

  Dio get dio => _dio;

  static String normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  void updateToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<UserSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/login',
        data: {'username': username, 'password': password},
      );
      final data = response.data ?? {};
      final token = data['token'] as String? ?? data['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw ApiException('登录响应缺少 token');
      }
      final expiresAtRaw = data['expiresAt'] as String? ?? data['expires_at'] as String?;
      return UserSession(
        token: token,
        username: (data['username'] as String?) ?? username,
        expiresAt: expiresAtRaw != null ? DateTime.tryParse(expiresAtRaw) : null,
      );
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '登录失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 上传附件到 Gateway（最大 8MB），返回公网可访问 URL。
  Future<GatewayUploadedFile> uploadFile({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/upload',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = response.data ?? {};
      return GatewayUploadedFile(
        id: data['id'].toString(),
        filename: (data['filename'] ?? filename).toString(),
        mimeType: (data['mimeType'] ?? mimeType).toString(),
        size: data['size'] is num ? (data['size'] as num).toInt() : bytes.length,
        downloadPath: (data['downloadPath'] ?? '').toString(),
        url: data['url']?.toString(),
        base64: data['base64']?.toString(),
      );
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '上传失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 将 Hermes 本地 file:// 路径签名为公网可访问 URL（需登录）。
  Future<String?> signMediaUrl(String pathOrFileUrl) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/media/sign',
        data: {'path': pathOrFileUrl},
      );
      final url = response.data?['url']?.toString();
      return url != null && url.isNotEmpty ? url : null;
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/health');
      return response.data ?? {'status': 'ok'};
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '连接失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 发送多轮对话（OpenAI 兼容 messages），默认 SSE 流式。
  Future<String> streamChat({
    required List<Map<String, dynamic>> messages,
    void Function(ChatStreamEvent event)? onEvent,
    void Function(String sessionId)? onSessionId,
    bool stream = true,
    String? model,
    String? sessionId,
    CancelToken? cancelToken,
    bool createAppMode = false,
    String? targetProjectSlug,
  }) async {
    try {
      final response = await _dio.post<ResponseBody>(
        '/v1/chat/completions',
        data: {
          'messages': messages,
          'stream': stream,
          if (model != null && model.isNotEmpty) 'model': model,
          if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
          if (createAppMode) 'create_app_mode': true,
          if (targetProjectSlug != null && targetProjectSlug.isNotEmpty)
            'target_project_slug': targetProjectSlug,
        },
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
          headers: {'Accept': 'text/event-stream, application/json'},
        ),
        cancelToken: cancelToken,
      );

      final newSessionId = response.headers.value('x-hermes-session-id');
      if (newSessionId != null && newSessionId.isNotEmpty) {
        onSessionId?.call(newSessionId);
      }

      final ct = response.headers.value('content-type') ?? '';
      if (!stream || !ct.contains('text/event-stream')) {
        final bytes = await response.data?.stream.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        final txt = utf8.decode(bytes ?? const []);
        final json = jsonDecode(txt) as Map<String, dynamic>;
        final content = _extractMessageContent(json);
        onEvent?.call(ChatTextDelta(content));
        return content;
      }

      final buffer = StringBuffer();
      var sseBuffer = '';
      var currentEvent = '';

      void handleSseData(String payload) {
        if (payload.isEmpty || payload == '[DONE]') return;

        Map<String, dynamic>? data;
        try {
          data = jsonDecode(payload) as Map<String, dynamic>;
        } on Object {
          return;
        }

        if (currentEvent == 'hermes.tool.progress') {
          final progress = _parseToolProgressPayload(data);
          if (progress != null) onEvent?.call(progress);
          currentEvent = '';
          return;
        }

        final toolProgress = _extractToolProgress(data);
        if (toolProgress != null) {
          onEvent?.call(toolProgress);
          return;
        }

        final usage = _extractUsage(data);
        if (usage != null) {
          onEvent?.call(usage);
          return;
        }

        final delta = _extractDeltaText(data);
        if (delta != null && delta.isNotEmpty) {
          buffer.write(delta);
          onEvent?.call(ChatTextDelta(delta));
        }
      }

      await for (final chunk in response.data?.stream ?? const Stream.empty()) {
        sseBuffer += utf8.decode(chunk, allowMalformed: true);
        final parts = sseBuffer.split('\n');
        sseBuffer = parts.removeLast();

        for (final line in parts) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            currentEvent = '';
            continue;
          }
          if (trimmed.startsWith('event:')) {
            currentEvent = trimmed.substring(6).trim();
            continue;
          }
          if (!trimmed.startsWith('data:')) continue;
          handleSseData(trimmed.substring(5).trim());
        }
      }

      if (sseBuffer.trim().isNotEmpty) {
        final trimmed = sseBuffer.trim();
        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          handleSseData(trimmed.substring(5).trim());
        }
      }

      return buffer.toString();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw ApiException('已停止生成');
      }
      if (e.response?.data is ResponseBody) {
        final body = e.response!.data as ResponseBody;
        final bytes = await body.stream.fold<List<int>>(<int>[], (p, c) => p..addAll(c));
        final txt = utf8.decode(bytes);
        try {
          final j = jsonDecode(txt) as Map<String, dynamic>;
          throw ApiException(j['message']?.toString() ?? txt, statusCode: e.response?.statusCode);
        } on FormatException {
          throw ApiException(txt.isNotEmpty ? txt : '聊天请求失败', statusCode: e.response?.statusCode);
        }
      }
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '聊天请求失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// 构建 OpenAI 多模态 user content（文本 + image_url http URL；文本内附带 URL 供 vision_analyze）
  static dynamic buildUserContent({
    required String text,
    List<({String mimeType, String url})>? images,
    List<({String name, String mimeType, String base64, bool isText})>? files,
  }) {
    final hasImages = images != null && images.isNotEmpty;
    final hasFiles = files != null && files.isNotEmpty;
    if (!hasImages && !hasFiles) return text;

    final parts = <Map<String, dynamic>>[];
    final buffer = StringBuffer(text);
    final fileList = files;
    if (fileList != null && fileList.isNotEmpty) {
      for (final f in fileList) {
        if (f.isText) {
          buffer.writeln('\n\n--- ${f.name} ---\n${utf8.decode(base64Decode(f.base64))}');
        } else {
          buffer.writeln('\n[文件: ${f.name}]');
        }
      }
    }
    final imageList = images;
    if (imageList != null && imageList.isNotEmpty) {
      for (final img in imageList) {
        final url = img.url.trim();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          buffer.writeln('\n[图片 URL: $url]');
        }
      }
    }
    parts.add({
      'type': 'text',
      'text': buffer.toString().trim().isEmpty ? '请分析附件' : buffer.toString().trim(),
    });
    if (imageList != null && imageList.isNotEmpty) {
      for (final img in imageList) {
        final url = img.url.trim();
        if (url.isEmpty || url.startsWith('data:')) continue;
        parts.add({
          'type': 'image_url',
          'image_url': {'url': url, 'detail': 'high'},
        });
      }
    }
    return parts;
  }

  static String? _extractDeltaText(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is Map && delta['content'] != null) {
      return delta['content'].toString();
    }
    final message = first['message'];
    if (message is Map && message['content'] != null) {
      return message['content'].toString();
    }
    return null;
  }

  static ChatUsageStats? _extractUsage(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage is! Map) return null;
    final prompt = usage['prompt_tokens'];
    final completion = usage['completion_tokens'];
    final total = usage['total_tokens'];
    if (prompt == null && completion == null && total == null) return null;
    final costRaw = usage['cost'];
    return ChatUsageStats(
      promptTokens: prompt is num ? prompt.toInt() : 0,
      completionTokens: completion is num ? completion.toInt() : 0,
      totalTokens: total is num ? total.toInt() : 0,
      cost: costRaw is num ? costRaw.toDouble() : double.tryParse('$costRaw'),
    );
  }

  static ChatToolProgress? _parseToolProgressPayload(Map<String, dynamic> data) {
    final tool = data['tool']?.toString();
    final label = data['label']?.toString();
    final status = data['status']?.toString();
    final toolCallId = data['toolCallId']?.toString() ?? data['call_id']?.toString();
    final detail = (label?.trim().isNotEmpty == true)
        ? label!.trim()
        : (data['message'] ?? data['detail'] ?? tool)?.toString() ?? '';
    if (detail.isEmpty && tool == null) return null;
    return ChatToolProgress(
      detail: detail,
      tool: tool,
      label: label,
      status: status,
      toolCallId: toolCallId,
    );
  }

  static ChatToolProgress? _extractToolProgress(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'hermes.tool.progress') {
      return _parseToolProgressPayload(data);
    }
    return null;
  }

  static String _extractMessageContent(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] != null) {
          return message['content'].toString();
        }
      }
    }
    return json['content']?.toString() ?? '';
  }
}
