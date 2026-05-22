import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DockerContainerNote {
  const DockerContainerNote({
    required this.containerId,
    this.alias,
    this.note,
    this.updatedAt,
  });

  final String containerId;
  final String? alias;
  final String? note;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'note': note,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory DockerContainerNote.fromJson(String containerId, Map<String, dynamic> json) {
    DateTime? updated;
    final raw = json['updatedAt']?.toString();
    if (raw != null && raw.isNotEmpty) {
      updated = DateTime.tryParse(raw);
    }
    return DockerContainerNote(
      containerId: containerId,
      alias: json['alias']?.toString(),
      note: json['note']?.toString(),
      updatedAt: updated,
    );
  }
}

/// 本机容器备注（alias 仅 App 展示；不改 Docker 真名）。
class DockerContainerNotesStore {
  DockerContainerNotesStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'docker_container_notes_v1';

  Map<String, DockerContainerNote> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, DockerContainerNote>{};
      for (final entry in map.entries) {
        if (entry.value is Map) {
          out[entry.key] = DockerContainerNote.fromJson(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
      return out;
    } on Object {
      return {};
    }
  }

  DockerContainerNote? get(String containerId) => loadAll()[containerId];

  Future<void> save(DockerContainerNote note) async {
    final all = loadAll();
    all[note.containerId] = note.copyWith(updatedAt: DateTime.now());
    await _persist(all);
  }

  Future<void> remove(String containerId) async {
    final all = loadAll();
    all.remove(containerId);
    await _persist(all);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_key);
  }

  Future<void> _persist(Map<String, DockerContainerNote> all) async {
    final encoded = <String, dynamic>{};
    for (final e in all.entries) {
      encoded[e.key] = e.value.toJson();
    }
    await _prefs.setString(_key, jsonEncode(encoded));
  }
}

extension DockerContainerNoteCopy on DockerContainerNote {
  DockerContainerNote copyWith({
    String? alias,
    String? note,
    DateTime? updatedAt,
  }) {
    return DockerContainerNote(
      containerId: containerId,
      alias: alias ?? this.alias,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
