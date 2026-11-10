import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../state/auth_provider.dart';
import '../widgets/auth_form_widgets.dart';

/// Registration screen (Figma 02 · Sign Up), pushed over the login screen.
///
/// On success it pops itself so [AuthGate] can show the interface for the
/// saved role. A self-selected Doctor role is not proof of verification;
/// data access must be enforced by Firestore Security Rules.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _role = UserRole.patient;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    auth.clearActionError();
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    final ok = await auth.signUp(
      displayName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: _role,
    );
    // Reveal AuthGate, which now shows the role-specific interface.
    if (ok && mounted) Navigator.of(context).pop();
  }

  // Hide an outdated authentication error once the user edits the form.
  void _clearAuthError() => context.read<AuthProvider>().clearActionError();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.isBusy;
    final error = auth.actionErrorMessage;
    final text = Theme.of(context).textTheme;
    final roleLabel = _role == UserRole.doctor ? 'doctor' : 'patient';

    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign Up',
                                  style: text.headlineSmall?.copyWith(
                                    color: AuthColors.heading,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'MedFollow • Medication care',
                                  style: text.bodyMedium?.copyWith(
                                    color: AuthColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _BackSquare(
                            onPressed:
                                busy ? null : () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Create your account',
                        style: text.titleLarge?.copyWith(
                          color: AuthColors.heading,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Choose your role for a personalized experience',
                        style: text.bodyMedium?.copyWith(
                          color: AuthColors.muted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RoleSelector(
                        role: _role,
                        onChanged: busy
                            ? null
                            : (role) {
                                _clearAuthError();
                                setState(() => _role = role);
                              },
                      ),
                      const SizedBox(height: 14),
                      AuthFieldCard(
                        child: TextFormField(
                          controller: _nameController,
                          enabled: !busy,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: authFieldDecoration(
                            label: 'Full name',
                            icon: Icons.people_outline,
                          ),
                          onChanged: (_) => _clearAuthError(),
                          validator: validateAuthName,
                        ),
                      ),
                      const SizedBox(height: 14),
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
                          onChanged: (_) => _clearAuthError(),
                          validator: validateAuthEmail,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AuthFieldCard(
                        child: TextFormField(
                          controller: _passwordController,
                          enabled: !busy,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => busy ? null : _submit(),
                          decoration: authFieldDecoration(
                            label: 'Password',
                            icon: Icons.lock_outline,
                          ).copyWith(
                            prefixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AuthColors.muted,
                                size: 20,
                              ),
                            ),
                          ),
                          onChanged: (_) => _clearAuthError(),
                          validator: validateAuthPassword,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        AuthErrorBanner(message: error),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 42,
                        child: FilledButton(
                          onPressed: busy ? null : _submit,
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
                              : Text('Create $roleLabel account'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AuthTonalButton(
                        onPressed:
                            busy ? null : () => Navigator.of(context).pop(),
                        label: 'Back to login',
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

class _BackSquare extends StatelessWidget {
  const _BackSquare({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      shadowColor: const Color(0x22000000),
      child: IconButton(
        tooltip: 'Back',
        onPressed: onPressed,
        icon: const Icon(Icons.chevron_left, color: AuthColors.primary),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.role, required this.onChanged});

  final UserRole role;
  final ValueChanged<UserRole>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AuthColors.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final option in UserRole.values)
            Expanded(
              child: Semantics(
                selected: option == role,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onChanged == null ? null : () => onChanged!(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option == role ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      option == UserRole.patient ? 'Patient' : 'Doctor',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: option == role
                            ? AuthColors.primary
                            : AuthColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
