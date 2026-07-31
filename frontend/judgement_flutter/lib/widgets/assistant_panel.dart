import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';

/// Lightweight rules assistant: curated FAQ + reason-code explanations.
class AssistantPanel extends StatefulWidget {
  final ApiClient api;
  final String? initialQuestion;
  final String? reasonCode;
  final Map<String, dynamic>? facts;

  const AssistantPanel({
    super.key,
    required this.api,
    this.initialQuestion,
    this.reasonCode,
    this.facts,
  });

  static Future<void> open(
    BuildContext context, {
    required ApiClient api,
    String? question,
    String? reasonCode,
    Map<String, dynamic>? facts,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AssistantPanel(
          api: api,
          initialQuestion: question,
          reasonCode: reasonCode,
          facts: facts,
        ),
      ),
    );
  }

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  late final TextEditingController _controller;
  ExplanationResponse? _response;
  String? _error;
  bool _loading = false;

  static const _suggestions = [
    'Must I follow suit?',
    'How do points work?',
    'How is trump chosen?',
    'What can I bid?',
    'Does trump beat ace?',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuestion ?? '');
    if (widget.reasonCode != null ||
        (widget.initialQuestion != null && widget.initialQuestion!.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask({String? overrideQuestion}) async {
    final question = overrideQuestion ?? _controller.text.trim();
    if (overrideQuestion != null) {
      _controller.text = overrideQuestion;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.queryRules(
        question: question.isEmpty ? null : question,
        reasonCode: widget.reasonCode,
        facts: widget.facts,
      );
      if (!mounted) return;
      setState(() {
        _response = response;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Assistant unavailable. Gameplay is unaffected.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Rules assistant',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Answers cite curated rules. The server never exposes hidden cards.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tip in _suggestions)
                  ActionChip(
                    label: Text(tip, style: const TextStyle(fontSize: 12)),
                    onPressed: _loading ? null : () => _ask(overrideQuestion: tip),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: 'Ask about bidding, trump, follow suit…',
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.25),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : () => _ask(),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFFB4A8))),
            ],
            if (_response != null) ...[
              const SizedBox(height: 16),
              Text(_response!.answer, style: const TextStyle(height: 1.35)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ref in _response!.ruleReferences)
                    Chip(
                      label: Text(ref, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.teal.withValues(alpha: 0.25),
                    ),
                  Chip(
                    label: Text(
                      'confidence ${(_response!.confidence * 100).round()}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
