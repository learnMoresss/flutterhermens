import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/agent_admin_api.dart';
import '../../core/network/api_client.dart';
import '../../core/network/message_gateway_api.dart';
import '../../core/ui/app_message.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';

const _platformLabels = {
  'telegram': 'Telegram',
  'discord': 'Discord',
  'slack': 'Slack',
  'whatsapp': 'WhatsApp',
  'signal': 'Signal',
};

class MessageGatewayPage extends ConsumerStatefulWidget {
  const MessageGatewayPage({super.key});

  @override
  ConsumerState<MessageGatewayPage> createState() => _MessageGatewayPageState();
}

class _MessageGatewayPageState extends ConsumerState<MessageGatewayPage> {
  bool _running = false;
  bool _loading = false;
  String? _error;
  Map<String, bool> _platforms = {};
  Timer? _poll;

  MessageGatewayApi _gwApi() =>
      MessageGatewayApi.fromClient(ref.read(gatewayClientProvider));

  AgentAdminApi _agentApi() =>
      AgentAdminApi.fromClient(ref.read(gatewayClientProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (ref.read(userSessionProvider).token == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final status = await _gwApi().status();
      final platforms = await _agentApi().listPlatforms();
      if (mounted) {
        setState(() {
          _running = status.running;
          _platforms = platforms;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _toggleGateway() async {
    setState(() => _loading = true);
    try {
      if (_running) {
        await _gwApi().stop();
      } else {
        await _gwApi().start();
      }
      await _refresh(quiet: true);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlatform(String key, bool value) async {
    try {
      final next = await _agentApi().setPlatform(key, value);
      if (mounted) setState(() => _platforms = next);
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '消息网关',
      showDivider: true,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '管理 Hermes 消息网关进程与各聊天平台开关。启停命令需在服务器 Gateway 环境变量中配置。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
          ],
          const SizedBox(height: 20),
          const SectionLabel('网关进程'),
          const SizedBox(height: 8),
          Text('状态：${_running ? '运行中' : '已停止'}', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          MonoButton(
            label: _running ? '停止网关' : '启动网关',
            onPressed: _loading ? null : _toggleGateway,
          ),
          const SizedBox(height: 28),
          const SectionLabel('平台开关'),
          const SizedBox(height: 8),
          if (_platforms.isEmpty)
            const Text('未读取到平台配置', style: TextStyle(color: AppColors.gray))
          else
            ..._platforms.entries.map(
              (e) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_platformLabels[e.key] ?? e.key),
                value: e.value,
                onChanged: (v) => _togglePlatform(e.key, v),
              ),
            ),
        ],
      ),
    );
  }
}
