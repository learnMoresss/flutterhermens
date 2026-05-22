import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/setup/setup_page.dart';
import '../../features/splash/splash_page.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/app_config.dart';
import '../../shared/models/user_session.dart';
import 'deferred_route.dart';

import '../../features/agent/agent_hub_page.dart' deferred as agent_hub;
import '../../features/agent/agent_memory_page.dart' deferred as agent_memory;
import '../../features/agent/agent_models_page.dart' deferred as agent_models;
import '../../features/agent/agent_profiles_page.dart' deferred as agent_profiles;
import '../../features/agent/agent_providers_page.dart' deferred as agent_providers;
import '../../features/agent/agent_skills_page.dart' deferred as agent_skills;
import '../../features/agent/agent_soul_page.dart' deferred as agent_soul;
import '../../features/agent/agent_toolsets_page.dart' deferred as agent_toolsets;
import '../../features/chat/chat_page.dart' deferred as chat;
import '../../features/gateway/message_gateway_page.dart' deferred as message_gateway;
import '../../features/main/workspace_page.dart' deferred as workspace;
import '../../features/main/main_shell.dart' deferred as main_shell;
import '../../features/profile/profile_page.dart' deferred as profile;
import '../../features/schedules/schedules_page.dart' deferred as schedules;
import '../../features/sessions/sessions_page.dart' deferred as sessions;

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(
      location: state.matchedLocation,
      config: ref.read(appConfigProvider),
      session: ref.read(userSessionProvider),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return deferredPage(
            loadLibrary: main_shell.loadLibrary,
            builder: () => main_shell.MainShell(navigationShell: navigationShell),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/chat',
                builder: (context, state) => deferredPage(
                  loadLibrary: chat.loadLibrary,
                  builder: () => chat.ChatPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'sessions',
                    builder: (context, state) => deferredPage(
                      loadLibrary: sessions.loadLibrary,
                      builder: () => sessions.SessionsPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/workspace',
                builder: (context, state) => deferredPage(
                  loadLibrary: workspace.loadLibrary,
                  builder: () => workspace.WorkspacePage(),
                ),
                routes: [
                  GoRoute(
                    path: 'schedules',
                    builder: (context, state) => deferredPage(
                      loadLibrary: schedules.loadLibrary,
                      builder: () => schedules.SchedulesPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'message-gateway',
                    builder: (context, state) => deferredPage(
                      loadLibrary: message_gateway.loadLibrary,
                      builder: () => message_gateway.MessageGatewayPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'agent',
                    builder: (context, state) => deferredPage(
                      loadLibrary: agent_hub.loadLibrary,
                      builder: () => agent_hub.AgentHubPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'models',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_models.loadLibrary,
                          builder: () => agent_models.AgentModelsPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'providers',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_providers.loadLibrary,
                          builder: () => agent_providers.AgentProvidersPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'toolsets',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_toolsets.loadLibrary,
                          builder: () => agent_toolsets.AgentToolsetsPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'skills',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_skills.loadLibrary,
                          builder: () => agent_skills.AgentSkillsPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'soul',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_soul.loadLibrary,
                          builder: () => agent_soul.AgentSoulPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'profiles',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_profiles.loadLibrary,
                          builder: () => agent_profiles.AgentProfilesPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'memory',
                        builder: (context, state) => deferredPage(
                          loadLibrary: agent_memory.loadLibrary,
                          builder: () => agent_memory.AgentMemoryPage(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/profile',
                builder: (context, state) => deferredPage(
                  loadLibrary: profile.loadLibrary,
                  builder: () => profile.ProfilePage(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/home',
        redirect: (context, state) => '/home/chat',
      ),
      GoRoute(
        path: '/home/apps',
        redirect: (context, state) => '/home/workspace',
      ),
      GoRoute(
        path: '/home/config',
        redirect: (context, state) => '/home/workspace?tab=1',
      ),
      GoRoute(
        path: '/home/docker',
        redirect: (context, state) => '/home/workspace?tab=2',
      ),
    ],
  );
});

String? _redirect({
  required String location,
  required AppConfig config,
  required UserSession session,
}) {
  final isSplash = location == '/splash';
  final isSetup = location == '/setup';
  final isLogin = location == '/login';
  final isHomeArea = location == '/home' || location.startsWith('/home/');

  if (isSplash) return null;

  if (!config.isConfigured) {
    return isSetup ? null : '/setup';
  }

  if (config.requireLogin && (!session.isLoggedIn || session.isExpired)) {
    if (isLogin || isSetup) return null;
    return '/login';
  }

  if (isSetup || isLogin) return '/home/chat';
  if (isHomeArea) return null;

  return '/home/chat';
}

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen(appConfigProvider, (_, _) => notifyListeners());
    _ref.listen(userSessionProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}
