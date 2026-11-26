import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState s = context.read<AppState>();
  late final family = TextEditingController(text: s.settings.familyAddresses.join('\n'));
  late final familyNames = TextEditingController(text: s.settings.familyNames.join(', '));
  late final friends = TextEditingController(text: s.settings.friendAddresses.join('\n'));
  late final query = TextEditingController(text: s.settings.gmailQuery);
  late final max = TextEditingController(text: '${s.settings.gmailMax}');
  late final waName = TextEditingController(text: s.settings.waMyName);
  late final clientId = TextEditingController(text: s.settings.googleWebClientId);
  late bool fromSent = s.settings.friendsFromSent;

  Future<void> _save() async {
    final st = s.settings;
    st.familyAddresses = splitList(family.text);
    st.familyNames = splitList(familyNames.text);
    st.friendAddresses = splitList(friends.text);
    st.friendsFromSent = fromSent;
    st.gmailQuery = query.text.trim();
    st.gmailMax = int.tryParse(max.text) ?? 5000;
    st.waMyName = waName.text.trim();
    st.googleWebClientId = clientId.text.trim();
    await s.reclassify();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('נשמר והסיווג עודכן')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final guess = s.effectiveWaName;
    InputDecoration dec(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());
    return ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
      SectionCard(
        title: 'סיווג מיילים',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: family, maxLines: 3, textDirection: TextDirection.ltr,
              decoration: dec('כתובות של בני משפחה', 'mom@gmail.com (כתובת בכל שורה)')),
          const SizedBox(height: 12),
          TextField(controller: familyNames, decoration: dec('שם משפחה בשם השולח', 'כהן, cohen')),
          const SizedBox(height: 12),
          TextField(controller: friends, maxLines: 3, textDirection: TextDirection.ltr,
              decoration: dec('כתובות של חברים', 'friend@gmail.com')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: fromSent,
            onChanged: (v) => setState(() => fromSent = v),
            title: const Text('זיהוי חברים אוטומטי'),
            subtitle: const Text('אנשים פרטיים ששלחת אליהם מייל בעבר יסווגו כ"חברים"'),
          ),
        ]),
      ),
      SectionCard(
        title: 'סריקת Gmail',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: query, textDirection: TextDirection.ltr,
              decoration: dec('שאילתת חיפוש', 'newer_than:1y  /  in:inbox  /  larger:5M')),
          const SizedBox(height: 12),
          TextField(controller: max, keyboardType: TextInputType.number, decoration: dec('מספר הודעות מקסימלי')),
          if (s.isAndroid) ...[
            const SizedBox(height: 12),
            TextField(
              controller: clientId,
              textDirection: TextDirection.ltr,
              decoration: dec('Google Web Client ID', '1234-abc.apps.googleusercontent.com'),
            ),
            const SizedBox(height: 4),
            Text('נדרש פעם אחת להתחברות ל-Gmail. הוראות ב-README.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
      SectionCard(
        title: 'וואטסאפ',
        child: TextField(
          controller: waName,
          decoration: dec('השם שלך בצ\'אטים מיוצאים',
              guess != null && s.settings.waMyName.isEmpty ? 'זוהה אוטומטית: $guess' : 'כפי שמופיע בקובץ הייצוא'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton(onPressed: _save, child: const Text('שמירה')),
      ),
      const SizedBox(height: 16),
      const InfoBox(
        icon: Icons.privacy_tip_outlined,
        title: 'פרטיות',
        body: 'כל הנתונים נשמרים רק בטלפון הזה. האפליקציה לא שולחת מידע לשום שרת, '
            'מלבד הבקשות ל-Gmail עצמו. מהמיילים נשמרים רק כותרות ותקציר קצר; '
            'מ-SMS ומוואטסאפ נשמרים רק זמנים, כיוון ושם איש הקשר, בלי תוכן ההודעות.',
      ),
    ]);
  }
}
