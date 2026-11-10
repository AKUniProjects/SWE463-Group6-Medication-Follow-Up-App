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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
