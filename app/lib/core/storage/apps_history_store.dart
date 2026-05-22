import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppsHistoryEntry {
  const AppsHistoryEntry({
    required this.slug,
    required this.title,
    required this.url,
    required this.visitedAt,
  });

  final String slug;
  final String title;
  final String url;
  final DateTime visitedAt;

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'title': title,
        'url': url,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory AppsHistoryEntry.fromJson(Map<String, dynamic> json) {
    return AppsHistoryEntry(
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      visitedAt: DateTime.tryParse(json['visitedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class AppsHistoryStore {
  AppsHistoryStore(this._prefs);

  final SharedPreferences _prefs;
  static const _historyKey = 'apps_history_v1';
  static const _lastSlugKey = 'apps_last_slug';

  String? get lastSlug => _prefs.getString(_lastSlugKey);

  Future<void> setLastSlug(String slug) async {
    await _prefs.setString(_lastSlugKey, slug);
  }

  List<AppsHistoryEntry> loadHistory({int limit = 30}) {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => AppsHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    } on Object {
      return [];
    }
  }

  Future<void> recordVisit({required String slug, required String title, required String url}) async {
    await setLastSlug(slug);
    final all = loadHistory(limit: 100);
    final filtered = all.where((e) => e.slug != slug).toList();
    filtered.insert(
      0,
      AppsHistoryEntry(slug: slug, title: title, url: url, visitedAt: DateTime.now()),
    );
    final trimmed = filtered.take(30).map((e) => e.toJson()).toList();
    await _prefs.setString(_historyKey, jsonEncode(trimmed));
  }
}
