import 'package:flutter/material.dart';

import '../../theme/dehla_theme.dart';
import '../../util/legal_consent.dart';
import '../../util/legal_copy.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocScaffold(
      title: 'Terms of Use',
      body: termsOfUseBody(),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocScaffold(
      title: 'Privacy Policy',
      body: privacyPolicyBody(),
    );
  }
}

class _LegalDocScaffold extends StatelessWidget {
  final String title;
  final String body;

  const _LegalDocScaffold({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Agreement version $kLegalAgreementVersion',
                style: TextStyle(
                  color: goldAccent.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                body.trim(),
                style: TextStyle(
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
