import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doctor_link.dart';
import '../state/doctor_link_provider.dart';
import '../widgets/auth_form_widgets.dart';

/// Patient "Doctor Linking" screen (Figma 03 · Doctor Linking and
/// Link Consent Off). Flow: code -> doctor preview -> explicit consent ->
/// link. All work goes through [DoctorLinkProvider].
///
/// Also renders Figma 03b (Link Error) and 03c (Link Success) from the
/// provider's [PatientLinkStatus], plus a small "Your doctors" section.
class DoctorLinkingScreen extends StatefulWidget {
  const DoctorLinkingScreen({super.key});

  @override
  State<DoctorLinkingScreen> createState() => _DoctorLinkingScreenState();
}

class _DoctorLinkingScreenState extends State<DoctorLinkingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  /// Local, explicit consent. Starts unchecked; never set automatically.
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final links = context.read<DoctorLinkProvider>();
      if (!links.canLinkDoctors) return;
      // A reopened screen starts fresh; it never repeats a finished link.
      links.resetLinkFlow();
      links.loadPatientLinks();
    });
  }

  Future<void> _retry() async {
    final links = context.read<DoctorLinkProvider>();
    if (links.doctorPreview != null && _consent) {
      await _link();
    } else {
      await _findDoctor();
    }
  }

  Future<void> _confirmRevoke(DoctorLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: Text(
          '${link.doctorName} will no longer be able to view your records. '
          'You can link again later with a valid code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<DoctorLinkProvider>().revokeDoctorLink(link);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    final links = context.read<DoctorLinkProvider>();
    final before = links.codeInput;
    links.setCodeInput(value);
    // A different code means a different doctor: consent must be re-given.
    if (links.codeInput != before && _consent) {
      setState(() => _consent = false);
    }
  }

  Future<void> _findDoctor() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _consent = false);
    await context.read<DoctorLinkProvider>().lookupDoctor(_codeController.text);
  }

  Future<void> _link() async {
    FocusScope.of(context).unfocus();
    await context
        .read<DoctorLinkProvider>()
        .linkToPreviewedDoctor(consentGiven: _consent);
  }

  @override
  Widget build(BuildContext context) {
    final links = context.watch<DoctorLinkProvider>();
    final text = Theme.of(context).textTheme;
    final status = links.linkStatus;
    final busy = links.isBusy;
    final preview = links.doctorPreview;
    final linked = status == PatientLinkStatus.linked;
    final last = links.lastLinked;
    // Success only when the refreshed, persisted list contains the link.
    final confirmed = linked &&
        last != null &&
        links.activeDoctorLinks.any((l) => l.id == last.id);
    if (confirmed) {
      return _SuccessView(
        doctorName: links.activeDoctorLinks
            .firstWhere((l) => l.id == last.id)
            .doctorName,
        onContinue: () => Navigator.of(context).maybePop(),
      );
    }
    final isError = const {
      PatientLinkStatus.invalidCode,
      PatientLinkStatus.alreadyLinked,
      PatientLinkStatus.newCodeRequired,
      PatientLinkStatus.error,
    }.contains(status);

    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    title: isError ? 'Link Error' : 'Doctor Linking',
                    subtitle: isError
                        ? 'MedFollow • Medication care'
                        : 'Secure record sharing',
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Connect your doctor',
                    style: text.titleLarge?.copyWith(
                      color: AuthColors.heading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sharing requires your clear consent',
                    style: text.bodyMedium?.copyWith(color: AuthColors.muted),
                  ),
                  const SizedBox(height: 14),
                  const _SharingCard(),
                  const SizedBox(height: 14),
                  if (!links.canLinkDoctors)
                    const AuthErrorBanner(
                      message: 'Only patient accounts can link to a doctor.',
                    )
                  else ...[
                    Form(
                      key: _formKey,
                      child: _CodeFieldCard(
                        invalid: status == PatientLinkStatus.invalidCode,
                        child: TextFormField(
                          controller: _codeController,
                          enabled: !busy && !linked,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.search,
                          onChanged: _onCodeChanged,
                          onFieldSubmitted: (_) =>
                              busy || linked ? null : _findDoctor(),
                          decoration: authFieldDecoration(
                            label: 'Doctor linking code',
                            icon: Icons.link_rounded,
                          ).copyWith(
                            hintText: 'ABCD-EFGH-23',
                            prefixIcon: Icon(
                              Icons.link_rounded,
                              size: 20,
                              color: status == PatientLinkStatus.invalidCode
                                  ? _errorRed
                                  : AuthColors.muted,
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter the code from your doctor';
                            }
                            return DoctorLinkProvider.validateCodeInput(
                              value!,
                            );
                          },
                        ),
                      ),
                    ),
                    if (status == PatientLinkStatus.lookingUp) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(),
                    ],
                    if (preview != null) ...[
                      const SizedBox(height: 14),
                      _DoctorPreview(name: preview.doctorName),
                    ],
                    if (preview != null && !linked) ...[
                      const SizedBox(height: 14),
                      _ConsentTile(
                        value: _consent,
                        enabled: !busy,
                        onChanged: (v) => setState(() => _consent = v),
                      ),
                    ],
                    if (links.linkMessage != null) ...[
                      const SizedBox(height: 14),
                      _WarningBanner(message: links.linkMessage!),
                    ],
                    if (linked) ...[
                      // Link reported but not found after refresh: never
                      // show false success.
                      const SizedBox(height: 14),
                      const _WarningBanner(
                        message: 'We could not confirm the link yet. Check '
                            'Your doctors below or try again.',
                      ),
                    ],
                    const SizedBox(height: 14),
                    _primaryAction(links, busy, preview != null, linked),
                    if (status == PatientLinkStatus.error) ...[
                      const SizedBox(height: 12),
                      AuthTonalButton(
                        label: 'Try again',
                        onPressed: busy ? null : _retry,
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  AuthTonalButton(
                    label: 'Not now',
                    onPressed:
                        busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                  if (links.canLinkDoctors) ...[
                    const SizedBox(height: 24),
                    _LinkedDoctorsSection(
                      links: links,
                      onRevoke: _confirmRevoke,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryAction(
    DoctorLinkProvider links,
    bool busy,
    bool hasPreview,
    bool linked,
  ) {
    if (linked) return const SizedBox.shrink();
    if (hasPreview && !_consent) {
      // Figma "Link Consent Off": disabled until consent is given.
      return const AuthTonalButton(
        label: 'Enable consent to continue',
        onPressed: null,
      );
    }
    final label = hasPreview ? 'Link doctor' : 'Find doctor';
    return SizedBox(
      height: 42,
      child: FilledButton(
        onPressed: busy ? null : (hasPreview ? _link : _findDoctor),
        style: FilledButton.styleFrom(
          backgroundColor: AuthColors.primary,
          disabledBackgroundColor: AuthColors.primary.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.headlineSmall?.copyWith(
                  color: AuthColors.heading,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(color: AuthColors.muted),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 1,
          shadowColor: const Color(0x22000000),
          child: IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left, color: AuthColors.primary),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          ),
        ),
      ],
    );
  }
}

class _SharingCard extends StatelessWidget {
  const _SharingCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuthColors.tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: AuthColors.primary,
            size: 26,
          ),
          const SizedBox(height: 10),
          Text(
            'Secure sharing',
            style: text.titleLarge?.copyWith(
              color: AuthColors.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Doctors may review adherence and recorded dose history. '
            'They cannot edit your medications or confirm doses.',
            style: text.bodyMedium?.copyWith(color: AuthColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DoctorPreview extends StatelessWidget {
  const _DoctorPreview({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return AuthFieldCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are linking to',
              style: TextStyle(color: AuthColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                color: AuthColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Coursework prototype: doctor accounts are self-registered and '
              'not professionally verified.',
              style: TextStyle(color: AuthColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? const Color(0xFFE6F6EF) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AuthColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'I consent to share dose records with this doctor',
          style: TextStyle(color: AuthColors.heading, fontSize: 14.5),
        ),
      ),
    );
  }
}

// Figma 03b / 03c colours.
const _errorRed = Color(0xFFC0404A);
const _errorTint = Color(0xFFFDEEEE);
const _warnText = Color(0xFF9A6A12);
const _warnTint = Color(0xFFFFF4E5);
const _successTint = Color(0xFFE6F6EF);
const _successIcon = Color(0xFF16897A);

/// Code field card; red-tinted with a red border for an invalid code.
class _CodeFieldCard extends StatelessWidget {
  const _CodeFieldCard({required this.invalid, required this.child});

  final bool invalid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!invalid) return AuthFieldCard(child: child);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _errorTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _errorRed),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _errorRed),
        child: child,
      ),
    );
  }
}

/// Figma 03b warning banner (amber, with a warning icon and text).
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Error: $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _warnTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _warnText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _warnText, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma 03c: shown only after the link is confirmed in Firestore.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.doctorName, required this.onContinue});

  final String doctorName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    title: 'Link Success',
                    subtitle: 'MedFollow • Medication care',
                    onBack: onContinue,
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      decoration: BoxDecoration(
                        color: _successTint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: _successIcon,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Doctor linked successfully',
                            style: text.headlineSmall?.copyWith(
                              color: AuthColors.heading,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You have approved medication record sharing '
                            'with $doctorName.',
                            style: text.bodyMedium?.copyWith(
                              color: AuthColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 42,
                    child: FilledButton(
                      onPressed: onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: AuthColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      child: const Text('Continue to Today'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your doctors": persisted links with Revoke for active ones.
class _LinkedDoctorsSection extends StatelessWidget {
  const _LinkedDoctorsSection({required this.links, required this.onRevoke});

  final DoctorLinkProvider links;
  final ValueChanged<DoctorLink> onRevoke;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final active = links.activeDoctorLinks;
    final revoked = links.revokedDoctorLinks;

    Widget content;
    if (!links.hasLoadedPatientLinks && links.isLoadingPatientLinks) {
      content = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (active.isEmpty && revoked.isEmpty) {
      content = const Text(
        'No linked doctors yet.',
        style: TextStyle(color: AuthColors.muted),
      );
    } else {
      content = Column(
        children: [
          for (final link in active)
            _DoctorRow(
              name: link.doctorName,
              detail: 'Can view your records',
              action: TextButton(
                onPressed: links.isBusy ? null : () => onRevoke(link),
                child: const Text('Revoke'),
              ),
            ),
          for (final link in revoked)
            _DoctorRow(
              name: link.doctorName,
              detail: link.revokedBy == link.doctorId
                  ? 'Access ended by doctor. Ask for a new code to reconnect.'
                  : 'Access ended. Enter a valid code to reconnect.',
              muted: true,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your doctors',
          style: text.titleMedium?.copyWith(
            color: AuthColors.heading,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        content,
        if (links.patientLinksError != null) ...[
          const SizedBox(height: 10),
          _WarningBanner(message: links.patientLinksError!),
          const SizedBox(height: 8),
          AuthTonalButton(
            label: 'Reload doctors',
            onPressed: links.isLoadingPatientLinks || links.isBusy
                ? null
                : links.loadPatientLinks,
          ),
        ],
      ],
    );
  }
}

class _DoctorRow extends StatelessWidget {
  const _DoctorRow({
    required this.name,
    required this.detail,
    this.action,
    this.muted = false,
  });

  final String name;
  final String detail;
  final Widget? action;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AuthFieldCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: muted ? AuthColors.muted : AuthColors.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: AuthColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      ),
    );
  }
}
