import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'gmail_service.dart';

/// Runs GmailService.diagnose and shows each step; results can be copied and sent for support.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final steps = <DiagStep>[];
  bool running = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.gmail.diagnose(s.settings.gmailQuery, onStep: (d) {
      if (mounted) setState(() => steps.add(d));
    }).whenComplete(() {
      if (mounted) setState(() => running = false);
    });
  }

  String get report => ['בדיקת חיבור Gmail · ${DateTime.now()}', ...steps.map((s) => '$s')].join('\n');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('בדיקת חיבור'),
        actions: [
          IconButton(
            tooltip: 'העתקה',
            icon: const Icon(Icons.copy),
            onPressed: steps.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: report));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('התוצאות הועתקו')));
                  },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (running) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        for (final d in steps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(d.ok ? Icons.check_circle : Icons.error,
                color: d.ok ? Colors.green : Theme.of(context).colorScheme.error),
            title: Text(d.name),
            subtitle: SelectableText(d.detail, textDirection: TextDirection.ltr),
          ),
        if (!running) ...[
          const SizedBox(height: 16),
          Text('לחץ על סמל ההעתקה למעלה ושלח את התוצאות.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}
