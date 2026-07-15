import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

import '../model/mock_auth.dart';
import '../repository/authentication_repository.dart';
import '../../../constants/assets.dart';
import '../../../constants/constants.dart';
import '../../../extensions/build_context_extension.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../routing/routes.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/global_loading.dart';
import '../../../utils/validator.dart';
import '../../common/ui/widgets/common_text_form_field.dart';
import '../../common/ui/widgets/primary_button.dart';
import 'view_model/authentication_view_model.dart';
import 'widgets/sign_in_agreement.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;
  late final StreamSubscription<AuthState> _authSubscription;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();

    _nicknameController.addListener(_validateForm);
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
    _confirmPasswordController.addListener(_validateForm);

    _authSubscription = ref
        .read(authenticationRepositoryProvider)
        .onAuthStateChange
        .listen(_onAuthStateChange);
  }

  @override
  void dispose() {
    _nicknameController.removeListener(_validateForm);
    _emailController.removeListener(_validateForm);
    _passwordController.removeListener(_validateForm);
    _confirmPasswordController.removeListener(_validateForm);

    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _authSubscription.cancel();
    super.dispose();
  }

  void _onAuthStateChange(AuthState data) async {
    final AuthChangeEvent event = data.event;
    final Session? session = data.session;
    debugPrint(
        '${Constants.tag} [RegisterScreen._onAuthStateChange] Auth change: $event, session: $session');

    if (event == AuthChangeEvent.signedIn && session != null) {
      ref
          .read(authenticationViewModelProvider.notifier)
          .updateProfile(session.user);
      if (mounted) context.go(Routes.dashboard);
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid = _nicknameController.text.trim().isNotEmpty &&
          isValidEmail(_emailController.text.trim()) &&
          _passwordController.text.length >= 6 &&
          _passwordController.text == _confirmPasswordController.text;
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
      }

      if (next is AsyncData) {
        debugPrint(
            '${Constants.tag} [RegisterScreen.build] isRegisterSuccessfully = ${next.value?.isRegisterSuccessfully}, isSignInSuccessfully = ${next.value?.isSignInSuccessfully}');
        if (next.value?.isRegisterSuccessfully == true) {
          context.pushReplacement(Routes.onboarding);
        } else if (next.value?.isSignInSuccessfully == true) {
          context.pushReplacement(Routes.dashboard);
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
                      const SizedBox(height: 32),
                      Expanded(
                        child: SvgPicture.asset(
                          Assets.welcome,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          semanticsLabel: 'Welcome',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'register'.tr(),
                        style: AppTheme.title32,
                      ),
                      const SizedBox(height: 24),
                      CommonTextFormField(
                        label: 'nickname'.tr(),
                        controller: _nicknameController,
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'nicknameRequired'.tr()
                            : null,
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      CommonTextFormField(
                        label: 'confirmPassword'.tr(),
                        controller: _confirmPasswordController,
                        isPassword: true,
                        validator: (val) => confirmPasswordValidator(
                            _passwordController.text, val),
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        isEnable: _isFormValid,
                        text: LocaleKeys.continueText.tr(),
                        onPressed: () {
                          ref
                              .read(authenticationViewModelProvider.notifier)
                              .signUpWithEmailAndPassword(
                                email: _emailController.text.trim(),
                                password: _passwordController.text,
                                nickname: _nicknameController.text.trim(),
                              );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            LocaleKeys.alreadyHaveAccount.tr(),
                            style: AppTheme.body14,
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () {
                              context.push(Routes.login);
                            },
                            child: Text(
                              LocaleKeys.signIn.tr(),
                              style: AppTheme.title14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const SignInAgreement(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
