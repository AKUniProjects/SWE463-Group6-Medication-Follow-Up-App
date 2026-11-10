import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/doctor_link.dart';
import '../state/doctor_link_provider.dart';
import '../widgets/auth_form_widgets.dart';

/// Opens the Doctor Code overlay (Figma "Prototype · Doctor Code").
Future<void> showDoctorCodeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const DoctorCodeDialog(),
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Shows and manages the signed-in doctor's linking code. All work goes
/// through [DoctorLinkProvider]; this widget holds no business logic.
class DoctorCodeDialog extends StatefulWidget {
  const DoctorCodeDialog({super.key});

  @override
  State<DoctorCodeDialog> createState() => _DoctorCodeDialogState();
}

class _DoctorCodeDialogState extends State<DoctorCodeDialog> {
  String? _notice; // short success feedback

  @override
  void initState() {
    super.initState();
    // One read per opening; restores the existing code from Firestore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final links = context.read<DoctorLinkProvider>();
      if (links.canManageCodes) links.loadCodes();
    });
  }

  Future<void> _run(Future<bool> Function() action, String success) async {
    setState(() => _notice = null);
    final ok = await action();
    if (mounted && ok) setState(() => _notice = success);
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _copy(DoctorCode code) async {
    // Copy the canonical stored value; display uses the grouped format.
    String notice;
    try {
      await Clipboard.setData(ClipboardData(text: code.code));
      notice = 'Code copied';
    } on PlatformException {
      // Browsers may block clipboard access; the code text is selectable.
      notice = 'Could not copy automatically. Select the code to copy it.';
    }
    if (mounted) setState(() => _notice = notice);
  }

  Future<void> _replace(DoctorLinkProvider links) async {
    if (!await _confirm(
      'Replace code?',
      'Patients will no longer be able to use the current code. '
          'Existing links are not affected.',
      'Replace',
    )) {
      return;
    }
    await _run(links.replaceCurrentCode, 'New code created');
  }

  Future<void> _deactivate(DoctorLinkProvider links, String code) async {
    if (!await _confirm(
      'Deactivate code?',
      'Patients will no longer be able to link with '
          '${formatDoctorCodeForDisplay(code)}. Existing links are not '
          'affected.',
      'Deactivate',
    )) {
      return;
    }
    await _run(() => links.deactivateCode(code), 'Code deactivated');
  }

  @override
  Widget build(BuildContext context) {
    final links = context.watch<DoctorLinkProvider>();
    final text = Theme.of(context).textTheme;
    final busy = links.isBusy || links.isLoading;
    final current = links.currentCode;
    final now = DateTime.now();
    final otherActive = [
      for (final c in links.codes)
        if (c.isUsableAt(now) && c.code != current?.code) c,
    ];

    Widget body;
    if (!links.canManageCodes) {
      body = const AuthErrorBanner(
        message: 'Only doctor accounts can manage linking codes.',
      );
    } else if (!links.hasLoaded && links.errorMessage == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CodeCard(code: current),
          if (links.errorMessage != null) ...[
            const SizedBox(height: 12),
            AuthErrorBanner(message: links.errorMessage!),
          ],
          if (_notice != null && links.errorMessage == null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _notice!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AuthColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (current == null && links.hasLoaded)
            _PrimaryButton(
              label: 'Generate code',
              onPressed:
                  busy ? null : () => _run(links.createCode, 'Code created'),
            )
          else if (current != null) ...[
            _PrimaryButton(
              label: 'Copy code',
              icon: Icons.copy_rounded,
              onPressed: busy ? null : () => _copy(current),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AuthTonalButton(
                    label: 'Replace',
                    onPressed: busy ? null : () => _replace(links),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AuthTonalButton(
                    label: 'Deactivate',
                    onPressed:
                        busy ? null : () => _deactivate(links, current.code),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Changed your display name? Replace the code so patients '
              'can still link.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AuthColors.muted),
            ),
          ],
          if (otherActive.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Other active codes',
              style: text.titleSmall?.copyWith(color: AuthColors.heading),
            ),
            for (final c in otherActive)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDoctorCodeForDisplay(c.code),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AuthColors.heading,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _deactivate(links, c.code),
                    child: const Text('Deactivate'),
                  ),
                ],
              ),
          ],
          if (links.errorMessage != null) ...[
            const SizedBox(height: 10),
            AuthTonalButton(
              label: 'Retry loading',
              onPressed: busy
                  ? null
                  : () {
                      setState(() => _notice = null);
                      links.loadCodes();
                    },
            ),
          ],
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your linking code',
                style: text.titleLarge?.copyWith(
                  color: AuthColors.heading,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Share with a patient who requests access',
                style: text.bodyMedium?.copyWith(color: AuthColors.muted),
              ),
              const SizedBox(height: 16),
              body,
              const SizedBox(height: 12),
              AuthTonalButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final DoctorCode? code;

  @override
  Widget build(BuildContext context) {
    final c = code;
    final expires = c?.expiresAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AuthColors.tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c == null)
            const Text(
              'No active code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AuthColors.heading,
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SelectableText(
                formatDoctorCodeForDisplay(c.code),
                semanticsLabel: 'Linking code ${c.code.split('').join(' ')}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AuthColors.primary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (c == null)
            const Text(
              'Generate a code to let a patient link to you.',
              style: TextStyle(color: AuthColors.muted),
            )
          else if (expires != null)
            Text(
              'Expires ${_formatDate(expires)}',
              style: const TextStyle(
                color: AuthColors.heading,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Patient consent is always required.',
            style: TextStyle(color: AuthColors.muted),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AuthColors.primary,
      minimumSize: const Size.fromHeight(42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}
