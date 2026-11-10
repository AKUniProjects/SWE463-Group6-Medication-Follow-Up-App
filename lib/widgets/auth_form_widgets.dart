import 'package:flutter/material.dart';

// Shared building blocks for the Login and Sign Up screens (Figma 01/02).

/// Colors taken from the Phase 2 Figma Login and Sign Up frames.
class AuthColors {
  static const background = Color(0xFFF5FAFC);
  static const heading = Color(0xFF16324F);
  static const muted = Color(0xFF5F7383);
  static const primary = Color(0xFF176B9A);
  static const tint = Color(0xFFE6F2F8);
  static const fieldBorder = Color(0xFFDCE6EC);

  /// Muted dark red for field messages (about 7:1 contrast on white).
  static const errorText = Color(0xFF8A3B3B);
  static const bannerBorder = Color(0xFFC9DDE8);
}

/// Shared form rules so Login and Sign Up validate identically.
const int kMinPasswordLength = 6;
const int kMaxNameLength = 100;

// Deliberately permissive: one "@", no spaces, a dot in the domain.
// Firebase performs the authoritative check.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateAuthEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
  return null;
}

String? validateAuthPassword(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  if (value.length < kMinPasswordLength) {
    return 'Use at least $kMinPasswordLength characters';
  }
  return null;
}

String? validateAuthName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter your full name';
  if (name.length > kMaxNameLength) {
    return 'Use $kMaxNameLength characters or fewer';
  }
  return null;
}

/// Borderless field decoration used inside [AuthFieldCard].
InputDecoration authFieldDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: const TextStyle(color: AuthColors.muted, fontSize: 14),
    prefixIcon: Icon(icon, color: AuthColors.muted, size: 20),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    // Subtle, readable field errors instead of bright red.
    errorStyle: const TextStyle(
      color: AuthColors.errorText,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
    ),
    errorMaxLines: 2,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
  );
}

class AuthFieldCard extends StatelessWidget {
  const AuthFieldCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuthColors.fieldBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthTonalButton extends StatelessWidget {
  const AuthTonalButton({
    required this.onPressed,
    required this.label,
    this.icon,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AuthColors.tint,
          foregroundColor: AuthColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (icon != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(icon, size: 20),
              ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Soft light-blue banner with navy text; the icon and wording carry the
    // meaning, so it does not rely on color alone.
    return Semantics(
      liveRegion: true,
      label: 'Error: $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AuthColors.tint,
          border: Border.all(color: AuthColors.bannerBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 18,
              color: AuthColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AuthColors.heading,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
