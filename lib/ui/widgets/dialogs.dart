import '../../core/format.dart';
import '../../core/material.dart';

/// Asks for a line of text. Returns null if cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.confirmLabel,
    this.initial,
    this.hint,
  });

  final String title;
  final String confirmLabel;
  final String? initial;
  final String? hint;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Asks for a time like `1:23.4`. Returns milliseconds, or null if cancelled.
Future<int?> promptTime(
  BuildContext context, {
  required String title,
  required int initialMs,
  required int maxMs,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _TimePrompt(title: title, initialMs: initialMs, maxMs: maxMs),
  );
}

class _TimePrompt extends StatefulWidget {
  const _TimePrompt({
    required this.title,
    required this.initialMs,
    required this.maxMs,
  });

  final String title;
  final int initialMs;
  final int maxMs;

  @override
  State<_TimePrompt> createState() => _TimePromptState();
}

class _TimePromptState extends State<_TimePrompt> {
  late final TextEditingController _controller =
      TextEditingController(text: formatMs(widget.initialMs, tenths: true));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final ms = parseTime(_controller.text);
    if (ms == null || ms > widget.maxMs) {
      setState(() => _error = 'Enter a time up to ${formatMs(widget.maxMs)}, '
          'like 1:23.4');
      return;
    }
    Navigator.of(context).pop(ms);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Minutes:seconds',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
