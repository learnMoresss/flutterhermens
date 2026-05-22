import 'package:flutter/material.dart';

import '../../shared/widgets/app_scaffold.dart';
import 'docker_services_section.dart';

class DockerPage extends StatelessWidget {
  const DockerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Docker',
      showDivider: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: const [
          DockerServicesSection(showHeading: false),
        ],
      ),
    );
  }
}
