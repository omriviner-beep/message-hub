import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/db.dart';
import 'core/settings.dart';
import 'dashboard/dashboard_screen.dart';
import 'gmail/gmail_screen.dart';
import 'gmail/gmail_service.dart';
import 'settings/settings_screen.dart';
import 'sms/sms_screen.dart';
import 'whatsapp/whatsapp_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('he');
  final settings = await Settings.load();
  final state = AppState(await AppDb.open(), settings, GmailService(webClientId: () => settings.googleWebClientId));
  runApp(ChangeNotifierProvider.value(value: state, child: const MessageHubApp()));
  state.init();
}

class MessageHubApp extends StatelessWidget {
  const MessageHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A6FDB), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'ניהול הודעות',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('he'),
      supportedLocales: const [Locale('he'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  static const titles = ['סקירה', 'Gmail', 'וואטסאפ', 'SMS', 'הגדרות'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android settings (notification / file access) - re-check permissions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().refreshWhatsAppNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        bottom: s.progress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Column(children: [
                  Text(s.progress!.text, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: s.progress!.fraction),
                ]),
              ),
      ),
      body: Column(children: [
        if (s.error != null)
          MaterialBanner(
            content: Text(s.error!),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            actions: [
              TextButton(
                onPressed: s.clearError,
                child: const Text('סגירה'),
              ),
            ],
          ),
        Expanded(
          child: IndexedStack(index: tab, children: const [
            DashboardScreen(),
            GmailScreen(),
            WhatsAppScreen(),
            SmsScreen(),
            SettingsScreen(),
          ]),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'סקירה'),
          NavigationDestination(icon: Icon(Icons.mail_outline), label: 'Gmail'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'וואטסאפ'),
          NavigationDestination(icon: Icon(Icons.sms_outlined), label: 'SMS'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'הגדרות'),
        ],
      ),
    );
  }
}
