import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/chat/gateway_media_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_message.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/divider_line.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/section_label.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const _version = '1.0.0';
  String? _healthStatus;
  bool _checking = false;
  GatewayMediaCacheStats? _cacheStats;
  bool _loadingCacheStats = false;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadCacheStats();
  }

  Future<void> _loadCacheStats() async {
    setState(() => _loadingCacheStats = true);
    try {
      final stats = await GatewayMediaCache.instance.getStats();
      if (mounted) setState(() => _cacheStats = stats);
    } finally {
      if (mounted) setState(() => _loadingCacheStats = false);
    }
  }

  Future<void> _clearMediaCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理媒体缓存'),
        content: const Text(
          '将删除本机已缓存的图片、视频和文件预览数据。下次打开会重新下载，确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingCache = true);
    try {
      await GatewayMediaCache.instance.clearAll();
      if (mounted) {
        AppMessage.success('媒体缓存已清理');
        await _loadCacheStats();
      }
    } on Object catch (e) {
      if (mounted) AppMessage.error('清理失败：$e');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _healthStatus = null;
    });

    try {
      final client = ref.read(gatewayClientProvider);
      final result = await client.healthCheck();
      setState(() => _healthStatus = result['status']?.toString() ?? 'ok');
    } on ApiException catch (e) {
      setState(() => _healthStatus = '失败：${e.message}');
    } catch (e) {
      setState(() => _healthStatus = '失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _reconfigure() async {
    context.go('/setup');
  }

  Future<void> _logout() async {
    await ref.read(userSessionProvider.notifier).clear();
    if (!mounted) return;
    final config = ref.read(appConfigProvider);
    if (config.requireLogin) {
      context.go('/login');
    } else {
      context.go('/home/chat');
    }
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有数据'),
        content: const Text('将清除本机服务器配置与登录状态，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(userSessionProvider.notifier).clear();
    await ref.read(appConfigProvider.notifier).clear();
    if (!mounted) return;
    context.go('/setup');
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final session = ref.watch(userSessionProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          session.username ?? '访客',
          style: GoogleFonts.notoSerifSc(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          session.isLoggedIn ? '已登录' : '无需登录 / 未登录',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.gray,
              ),
        ),
        const SizedBox(height: 32),
        const SectionLabel('服务器'),
        const SizedBox(height: 12),
        Text(
          '备份、重启在「配置」页；Docker 容器管理在「Docker」页。Hermes 地址与备份路径请在服务器网关 `.env` 中维护，或通过部署脚本上传 `gateway-deploy.env.local`。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 12),
        _InfoTile(label: 'Gateway', value: config.gatewayUrl),
        _InfoTile(label: '需要登录', value: config.requireLogin ? '是' : '否'),
        const SizedBox(height: 8),
        if (_healthStatus != null) ...[
          const SizedBox(height: 8),
          _InfoTile(label: '连接状态', value: _healthStatus!),
        ],
        const SizedBox(height: 24),
        MonoButton(
          label: '检查连接',
          isLoading: _checking,
          outlined: true,
          onPressed: _checkConnection,
        ),
        const SizedBox(height: 32),
        const SectionLabel('外观'),
        const SizedBox(height: 8),
        DropdownButtonFormField<ThemeMode>(
          value: ref.watch(themeModeProvider),
          decoration: const InputDecoration(
            labelText: '主题',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
          ],
          onChanged: (mode) {
            if (mode != null) ref.read(themeModeProvider.notifier).set(mode);
          },
        ),
        const SizedBox(height: 32),
        const SectionLabel('存储'),
        const SizedBox(height: 8),
        Text(
          '聊天中的图片、视频和文件预览会缓存到本机（按服务器路径识别，重新签名链接仍可命中）。上限约 512MB，超过后自动淘汰最久未用的文件。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 12),
        _InfoTile(
          label: '媒体缓存',
          value: _loadingCacheStats
              ? '计算中…'
              : _cacheStats == null
                  ? '—'
                  : '${_cacheStats!.sizeLabel} · ${_cacheStats!.fileCount} 个文件',
        ),
        const SizedBox(height: 12),
        MonoButton(
          label: '清理媒体缓存',
          outlined: true,
          isLoading: _clearingCache,
          onPressed: _clearingCache ? null : _clearMediaCache,
        ),
        const SizedBox(height: 32),
        const SectionLabel('操作'),
        const SizedBox(height: 12),
        MonoButton(
          label: '重新配置',
          outlined: true,
          onPressed: _reconfigure,
        ),
        if (config.requireLogin) ...[
          const SizedBox(height: 12),
          MonoButton(
            label: '退出登录',
            outlined: true,
            onPressed: _logout,
          ),
        ],
        const SizedBox(height: 12),
        MonoButton(
          label: '清除所有数据',
          outlined: true,
          onPressed: _resetAll,
        ),
        const SizedBox(height: 40),
        const DividerLine(),
        const SizedBox(height: 24),
        const SectionLabel('关于'),
        const SizedBox(height: 12),
        Text(
          'Hermes Mobile Client\n通过 Node Gateway 连接 Hermes Web API 的轻量移动端。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.gray,
                height: 1.6,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '版本 $_version',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray,
              ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.grayLight),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
