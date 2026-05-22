import 'package:dio/dio.dart';

import '../../shared/models/user_session.dart';
import 'api_client.dart';

/// Gateway JWT 续期（无需重新输入密码）
class SessionAuth {
  static const refreshThreshold = Duration(hours: 2);

  static Future<UserSession?> refreshSession({
    required String gatewayUrl,
    required String token,
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiClient.normalizeBaseUrl(gatewayUrl),
        connectTimeout: const Duration(seconds: 15),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    );
    try {
      final response = await dio.post<Map<String, dynamic>>('/v1/auth/refresh');
      final data = response.data;
      if (data == null || data['token'] == null) return null;
      return UserSession(
        token: data['token'].toString(),
        expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
        username: data['username']?.toString(),
      );
    } on DioException {
      return null;
    }
  }
}

extension UserSessionRefresh on UserSession {
  bool get isExpiringSoon {
    if (expiresAt == null || !isLoggedIn) return false;
    return DateTime.now().isAfter(expiresAt!.subtract(SessionAuth.refreshThreshold));
  }
}
