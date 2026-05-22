import 'package:dio/dio.dart';

import 'api_client.dart';

class MessageGatewayApi {
  MessageGatewayApi(this._dio);

  factory MessageGatewayApi.fromClient(ApiClient client) => MessageGatewayApi(client.dio);

  final Dio _dio;

  Future<({bool running, bool pidFileExists})> status() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/admin/message-gateway/status');
    return (
      running: r.data?['running'] == true,
      pidFileExists: r.data?['pidFileExists'] == true,
    );
  }

  Future<({bool running, bool pidFileExists})> start() async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/admin/message-gateway/start');
    return (
      running: r.data?['running'] == true,
      pidFileExists: r.data?['pidFileExists'] == true,
    );
  }

  Future<({bool running, bool pidFileExists})> stop() async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/admin/message-gateway/stop');
    return (
      running: r.data?['running'] == true,
      pidFileExists: r.data?['pidFileExists'] == true,
    );
  }
}
