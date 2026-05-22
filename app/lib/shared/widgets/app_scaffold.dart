import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.showDivider = true,
    this.actions,
    this.leading,
    this.body,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
  });

  final String? title;
  final bool showDivider;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
              leading: leading,
              bottom: showDivider
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(1),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.grayLight,
                      ),
                    )
                  : null,
            ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
