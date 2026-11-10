import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';
import '../widgets/auth_form_widgets.dart';
import 'sign_up_screen.dart';

/// Login screen (Figma 01 · Login).
///
/// After a successful sign-in, [AuthGate] routes by the verified profile
/// role, so this screen never navigates by itself.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final auth = context.read<AuthProvider>();
    auth.clearActionError();
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    await auth.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  void _togglePassword() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  Future<void> _createAccount() async {
    final auth = context.read<AuthProvider>();
    auth.clearActionError();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
    // Don't carry a sign-up error back onto the login form.
    if (mounted) auth.clearActionError();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.isBusy;
    final error = auth.actionErrorMessage;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome back',
                        style: text.headlineSmall?.copyWith(
                          color: AuthColors.heading,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your daily care, made simple',
                        style: text.bodyMedium?.copyWith(
                          color: AuthColors.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _BrandCard(),
                      const SizedBox(height: 16),
                      AuthFieldCard(
                        child: TextFormField(
                          controller: _emailController,
                          enabled: !busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: authFieldDecoration(
                            label: 'Email',
                            icon: Icons.people_outline,
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Enter your email';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      AuthFieldCard(
                        child: TextFormField(
                          controller: _passwordController,
                          enabled: !busy,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => busy ? null : _signIn(),
                          decoration: authFieldDecoration(
                            label: 'Password',
                            icon: _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter your password';
                            }
                            if (value.length < 6) {
                              return 'Use at least 6 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      AuthTonalButton(
                        onPressed: _togglePassword,
                        icon: _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        label: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        AuthErrorBanner(message: error),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 42,
                        child: FilledButton(
                          onPressed: busy ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: AuthColors.primary,
                            disabledBackgroundColor:
                                AuthColors.primary.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AuthTonalButton(
                        onPressed: busy ? null : _createAccount,
                        label: 'Create an account',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AuthColors.tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 36,
            color: AuthColors.primary,
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MedFollow',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AuthColors.heading,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  'Stay on track, every day',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AuthColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
