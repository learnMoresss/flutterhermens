import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户当前在「应用 Tab」中打开的项目 slug（供聊天修改时锁定）。
class ActiveViewingProjectNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? slug) => state = slug;
}

final activeViewingProjectSlugProvider =
    NotifierProvider<ActiveViewingProjectNotifier, String?>(ActiveViewingProjectNotifier.new);
