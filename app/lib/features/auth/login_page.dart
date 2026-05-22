import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/mono_button.dart';
import '../../shared/widgets/mono_text_field.dart';
import '../../shared/widgets/section_label.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final config = ref.read(appConfigProvider);
      final client = ApiClient(
        baseUrl: config.gatewayUrl,
      );

      final session = await client.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      await ref.read(userSessionProvider.notifier).save(session);
      await ensureFreshSession(ref);

      if (!mounted) return;
      final next = GoRouterState.of(context).uri.queryParameters['next']?.trim();
      if (next != null && next.startsWith('/') && !next.startsWith('//')) {
        context.go(next);
      } else {
        context.go('/home/chat');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);

    return AppScaffold(
      title: '登录',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '账户登录',
                  style: GoogleFonts.notoSerifSc(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppColors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  config.gatewayUrl,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
                const SizedBox(height: 40),
                const SectionLabel('凭据'),
                const SizedBox(height: 12),
                MonoTextField(
                  controller: _usernameController,
                  label: '用户名',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入用户名';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                MonoTextField(
                  controller: _passwordController,
                  label: '密码',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _login(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.black,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                MonoButton(
                  label: '登录',
                  isLoading: _isLoading,
                  onPressed: _login,
                ),
                const SizedBox(height: 16),
                MonoButton(
                  label: '返回配置',
                  outlined: true,
                  onPressed: _isLoading ? null : () => context.go('/setup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
