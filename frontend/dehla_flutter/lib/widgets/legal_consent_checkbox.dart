import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/legal/legal_screens.dart';
import '../util/legal_consent.dart';

/// Required Terms + Privacy acceptance with tappable doc links.
class LegalConsentCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
        );
      };
    _privacyTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
        );
      };
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.tertiary,
      decoration: TextDecoration.underline,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final baseStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: 13,
      height: 1.35,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: widget.value,
          onChanged: (v) {
            final accepted = v ?? false;
            if (accepted) {
              acceptCurrentLegalAgreement();
            } else {
              clearLegalAgreementAcceptance();
            }
            widget.onChanged(accepted);
          },
          title: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms of Use',
                  style: linkStyle,
                  recognizer: _termsTap,
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: linkStyle,
                  recognizer: _privacyTap,
                ),
              ],
            ),
          ),
        ),
        Text(
          'Voice and reactions are shared with players at your table only for this game.',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Agreement version $kLegalAgreementVersion',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Footer links that open legal docs (does not accept consent).
class LegalFooterLinks extends StatelessWidget {
  const LegalFooterLinks({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
            );
          },
          child: const Text('Terms'),
        ),
        Text(
          '·',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            );
          },
          child: const Text('Privacy'),
        ),
      ],
    );
  }
}
