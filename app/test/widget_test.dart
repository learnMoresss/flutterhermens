import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_chat/shared/models/app_config.dart';
import 'package:hermes_chat/shared/models/user_session.dart';

void main() {
  test('AppConfig serializes correctly', () {
    const config = AppConfig(
      gatewayUrl: 'http://localhost:3000',
      requireLogin: true,
      isConfigured: true,
    );

    final restored = AppConfig.fromJson(config.toJson());
    expect(restored.gatewayUrl, config.gatewayUrl);
    expect(restored.requireLogin, true);
    expect(restored.isConfigured, true);
  });

  test('UserSession detects login state', () {
    const session = UserSession(token: 'abc', username: 'test');
    expect(session.isLoggedIn, true);

    const empty = UserSession.empty;
    expect(empty.isLoggedIn, false);
  });
}
