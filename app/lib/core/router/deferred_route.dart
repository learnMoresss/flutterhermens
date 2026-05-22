import 'package:flutter/material.dart';

/// 延迟加载路由页面，避免冷启动时一次性 link 全部 feature 库。
class DeferredRoutePage extends StatefulWidget {
  const DeferredRoutePage({
    super.key,
    required this.loader,
    required this.builder,
  });

  final Future<void> Function() loader;
  final Widget Function() builder;

  @override
  State<DeferredRoutePage> createState() => _DeferredRoutePageState();
}

class _DeferredRoutePageState extends State<DeferredRoutePage> {
  late final Future<void> _loadFuture = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Colors.black);
        }
        return widget.builder();
      },
    );
  }
}

Widget deferredPage({
  required Future<void> Function() loadLibrary,
  required Widget Function() builder,
}) {
  return DeferredRoutePage(loader: loadLibrary, builder: builder);
}
