import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/app_config.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/mono_text_field.dart';
import '../../shared/widgets/section_label.dart';

/// 仅填写 Gateway 与是否需登录；Hermes 地址与备份请在服务器网关 `.env` 中配置（或通过部署脚本上传），保存后进入登录或首页。
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _requireLogin = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(appConfigProvider);
      if (config.gatewayUrlSafe.isNotEmpty) {
        _urlController.text = config.gatewayUrlSafe;
      }
      setState(() => _requireLogin = config.requireLogin);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return '请输入 Gateway 地址';
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '请输入有效的 http/https 地址';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '仅支持 http 或 https';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final url = _urlController.text.trim();
      await ref.read(appConfigProvider.notifier).save(
            gatewayUrl: url,
            requireLogin: _requireLogin,
          );

      if (!mounted) return;

      if (_requireLogin) {
        context.go('/login?next=${Uri.encodeComponent('/home/chat')}');
        return;
      }
      context.go('/home/chat');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '连接向导',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '连接',
                  style: GoogleFonts.notoSerifSc(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: AppColors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '填写网关地址与访问方式。Hermes 地址、备份路径请在服务器网关 `.env` 中配置，或通过部署脚本上传。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.gray,
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('Gateway 地址'),
                const SizedBox(height: 10),
                MonoTextField(
                  controller: _urlController,
                  label: 'Base URL',
                  hint: 'http://119.45.30.73:3000',
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  validator: _validateUrl,
                ),
                const SizedBox(height: 24),
                const SectionLabel('访问控制'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.grayLight),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SwitchListTile(
                    title: const Text('此服务器需要登录'),
                    subtitle: Text(
                      _requireLogin ? '保存后进入登录页' : '保存后进入首页',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray),
                    ),
                    value: _requireLogin,
                    onChanged: (v) => setState(() => _requireLogin = v),
                  ),
                ),
                const SizedBox(height: 32),
                MonoButton(
                  label: '保存并继续',
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
