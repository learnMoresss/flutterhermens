import '../network/hermes_sessions_api.dart';

enum SessionDateGroup { today, yesterday, thisWeek, earlier }

const sessionDateGroupLabels = {
  SessionDateGroup.today: '今天',
  SessionDateGroup.yesterday: '昨天',
  SessionDateGroup.thisWeek: '本周',
  SessionDateGroup.earlier: '更早',
};

SessionDateGroup sessionDateGroup(DateTime? updatedAt) {
  if (updatedAt == null) return SessionDateGroup.earlier;
  final now = DateTime.now();
  final local = updatedAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final sessionDay = DateTime(local.year, local.month, local.day);
  final diff = today.difference(sessionDay).inDays;
  if (diff == 0) return SessionDateGroup.today;
  if (diff == 1) return SessionDateGroup.yesterday;
  if (diff < 7) return SessionDateGroup.thisWeek;
  return SessionDateGroup.earlier;
}

Map<SessionDateGroup, List<HermesSessionSummary>> groupSessions(
  List<HermesSessionSummary> sessions,
) {
  final grouped = {
    SessionDateGroup.today: <HermesSessionSummary>[],
    SessionDateGroup.yesterday: <HermesSessionSummary>[],
    SessionDateGroup.thisWeek: <HermesSessionSummary>[],
    SessionDateGroup.earlier: <HermesSessionSummary>[],
  };
  for (final s in sessions) {
    grouped[sessionDateGroup(s.updatedAt)]!.add(s);
  }
  return grouped;
}
