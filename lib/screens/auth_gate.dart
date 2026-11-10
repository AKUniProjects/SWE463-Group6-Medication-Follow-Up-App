import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';
import 'app_shell.dart';
import 'auth_screen.dart';

/// Chooses the visible screen from the verified authentication state.
///
/// UI routing is convenience only; Firestore Security Rules must enforce
/// data access independently.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.loading:
        return const _LoadingView();
      case AuthStatus.signedOut:
        return const AuthScreen();
      case AuthStatus.signedIn:
        final role = auth.userProfile!.role;
        return AppShell(
          key: ValueKey('shell-${auth.userId}-${role.name}'),
          role: role,
        );
      case AuthStatus.missingProfile:
        return const _RecoveryView(
          title: 'Profile not found',
          message: 'Your account has no user profile. Try again, or sign out '
              'and contact support if this continues.',
        );
      case AuthStatus.error:
        return _RecoveryView(
          title: 'Something went wrong',
          message: auth.errorMessage ?? 'Authentication failed.',
        );
    }
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecoveryView extends StatelessWidget {
  const _RecoveryView({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: auth.retry,
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: auth.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
