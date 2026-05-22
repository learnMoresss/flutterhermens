import 'package:flutter/material.dart';

import '../../shared/widgets/app_scaffold.dart';
import 'docker_services_section.dart';

class DockerPage extends StatelessWidget {
  const DockerPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: EdgeInsets.fromLTRB(24, embedded ? 16 : 24, 24, 32),
      children: const [
        DockerServicesSection(showHeading: false),
      ],
    );

    if (embedded) return body;

    return AppScaffold(
      title: 'Docker',
      showDivider: true,
      body: body,
    );
  }
}
