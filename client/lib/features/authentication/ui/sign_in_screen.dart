import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

import '../../../constants/assets.dart';
import '../../../features/authentication/ui/view_model/authentication_view_model.dart';
import '../../../features/authentication/repository/authentication_repository.dart';
import '../../../extensions/build_context_extension.dart';
import '../../../utils/global_loading.dart';
import '../../../features/common/ui/widgets/common_back_button.dart';
import '../../../features/common/ui/widgets/common_text_form_field.dart';
import '../../../features/common/ui/widgets/primary_button.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../routing/routes.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/validator.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _isFormValid = false;
  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
    
    // Check if there is an existing lockout on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLockout();
    });
  }

  @override
  void dispose() {
    _emailController.removeListener(_validateForm);
    _passwordController.removeListener(_validateForm);
    _emailController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _checkLockout() {
    final repo = ref.read(authenticationRepositoryProvider);
    final remaining = repo.getLockoutTimeRemaining();
    if (remaining > 0) {
      setState(() {
        _lockoutSecondsRemaining = remaining;
      });
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final repo = ref.read(authenticationRepositoryProvider);
      final remaining = repo.getLockoutTimeRemaining();
      setState(() {
        _lockoutSecondsRemaining = remaining;
      });
      if (remaining <= 0) {
        _lockoutTimer?.cancel();
      }
    });
  }

  void _validateForm() {
    setState(() {
      _isFormValid = isValidEmail(_emailController.text.trim()) &&
          _passwordController.text.length >= 6;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authenticationViewModelProvider, (previous, next) {
      if (next.isLoading != previous?.isLoading) {
        if (next.isLoading) {
          Global.showLoading(context);
        } else {
          Global.hideLoading();
        }
      }

      if (next is AsyncError) {
        context.showErrorSnackBar(next.error.toString());
        _checkLockout();
      }

      if (next is AsyncData) {
        if (next.value?.isSignInSuccessfully == true) {
          context.go(Routes.dashboard);
        }
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 64),
                      Expanded(
                        child: SvgPicture.asset(
                          Assets.login,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          semanticsLabel: 'Sign in',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        LocaleKeys.signIn.tr(),
                        style: AppTheme.title32,
                      ),
                      const SizedBox(height: 24),
                      CommonTextFormField(
                        label: 'Email',
                        controller: _emailController,
                        validator: notEmptyEmailValidator,
                      ),
                      const SizedBox(height: 16),
                      CommonTextFormField(
                        label: 'password'.tr(),
                        controller: _passwordController,
                        isPassword: true,
                        validator: (val) => val == null || val.isEmpty
                            ? 'passwordRequired'.tr()
                            : (val.length < 6
                                ? 'passwordMinLength'.tr()
                                : null),
                      ),
                      if (_lockoutSecondsRemaining > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock, color: Colors.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'tooManyAttempts'.tr(args: [
                                    _lockoutSecondsRemaining.toString()
                                  ]),
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      PrimaryButton(
                        isEnable: _isFormValid && _lockoutSecondsRemaining == 0,
                        text: LocaleKeys.signIn.tr(),
                        onPressed: () {
                          ref
                              .read(authenticationViewModelProvider.notifier)
                              .signInWithEmailAndPassword(
                                email: _emailController.text.trim(),
                                password: _passwordController.text,
                              );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'dontHaveAccount'.tr(),
                            style: AppTheme.body14,
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () {
                              context.push(Routes.register);
                            },
                            child: Text(
                              LocaleKeys.register.tr(),
                              style: AppTheme.title14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: CommonBackButton(),
            ),
          ],
        ),
      ),
    );
  }
}
