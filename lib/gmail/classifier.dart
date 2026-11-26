/// Rule-based e-mail classifier (Hebrew + English). First matching rule wins.
library;

enum MailCategory {
  family('משפחה'),
  friends('חברים'),
  receipts('קבלות'),
  finance('כספים'),
  travel('נסיעות'),
  social('רשתות חברתיות'),
  promotions('פרסומות'),
  newsletters('ניוזלטרים'),
  notifications('התראות'),
  personal('אנשים אחרים'),
  other('אחר');

  final String label;
  const MailCategory(this.label);

  /// Categories that hold real people's mail - bulk cleanup needs extra confirmation.
  bool get isProtected =>
      this == MailCategory.family || this == MailCategory.friends || this == MailCategory.personal;
}

class MailMeta {
  final String id;
  final String sender; // lower-case address
  final String senderName;
  final String subject;
  final String snippet;
  final DateTime date;
  final List<String> labels; // growable copy, so archive can drop INBOX
  final String listUnsubscribe;
  final int size;
  MailCategory? category;

  MailMeta({
    required this.id,
    required this.sender,
    this.senderName = '',
    this.subject = '',
    this.snippet = '',
    required this.date,
    List<String> labels = const [],
    this.listUnsubscribe = '',
    this.size = 0,
    this.category,
  }) : labels = [...labels];

  bool get isSent => labels.contains('SENT');
  bool get isUnread => labels.contains('UNREAD');
  bool get isStarred => labels.contains('STARRED');
  bool get isImportant => labels.contains('IMPORTANT');
  bool get inInbox => labels.contains('INBOX');
}

const personalDomains = {
  'gmail.com', 'googlemail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'live.com',
  'icloud.com', 'me.com', 'walla.co.il', 'walla.com', 'bezeqint.net', '012.net.il',
  'netvision.net.il', 'zahav.net.il', 'protonmail.com', 'proton.me', 'aol.com', 'msn.com',
};

final _automated = RegExp(
  r'(no-?reply|do-?not-?reply|notifications?|alerts?|mailer|news(letter)?|info|'
  r'support|updates?|marketing|hello|team|service|billing|accounts?|bounce)',
  caseSensitive: false,
);

class Rules {
  final List<String> keywords;
  final List<String> domains;
  const Rules({this.keywords = const [], this.domains = const []});

  Rules merge(Rules o) => Rules(keywords: [...keywords, ...o.keywords], domains: [...domains, ...o.domains]);
}

const defaultRules = <MailCategory, Rules>{
  MailCategory.receipts: Rules(keywords: [
    'receipt', 'invoice', 'order confirmation', 'your order', 'order #', 'payment received',
    'payment confirmation', 'purchase', 'תודה על הזמנתך', 'קבלה', 'חשבונית', 'אישור הזמנה',
    'אישור תשלום', 'הזמנתך', 'ההזמנה שלך', 'תשלום התקבל', 'אישור רכישה', 'חשבון עסקה',
  ], domains: [
    'paypal.com', 'aliexpress.com', 'amazon.com', 'ebay.com', 'apple.com', 'wolt.com',
    '10bis.co.il', 'greeninvoice.co.il', 'icount.co.il',
  ]),
  MailCategory.finance: Rules(keywords: [
    'bank', 'statement', 'credit card', 'transaction', 'transfer', 'investment', 'dividend',
    'tax', 'pension', 'insurance', 'loan', 'mortgage', 'בנק', 'דף חשבון', 'כרטיס אשראי',
    'חיוב', 'העברה', 'השקעות', 'מס הכנסה', 'פנסיה', 'ביטוח', 'הלוואה', 'משכנתא',
    'קרן השתלמות', 'ביטוח לאומי', 'תיק השקעות', 'יתרה',
  ], domains: [
    'bankhapoalim.co.il', 'leumi.co.il', 'discountbank.co.il', 'mizrahi-tefahot.co.il',
    'fibi.co.il', 'isracard.co.il', 'max.co.il', 'cal-online.co.il', 'americanexpress.com',
    'btl.gov.il', 'taxes.gov.il', 'gov.il', 'harel-group.co.il', 'migdal.co.il',
    'clalbit.co.il', 'menoramivt.co.il', 'phoenix.co.il', 'altshul.co.il', 'meitav.co.il',
    'interactivebrokers.com', 'revolut.com', 'wise.com', 'payboxapp.com',
  ]),
  MailCategory.travel: Rules(keywords: [
    'flight', 'boarding pass', 'booking confirmation', 'itinerary', 'reservation', 'check-in',
    'טיסה', 'כרטיס עלייה למטוס', 'הזמנת מלון', "צ'ק אין",
  ], domains: [
    'booking.com', 'airbnb.com', 'expedia.com', 'elal.com', 'elal.co.il', 'ryanair.com',
    'wizzair.com', 'easyjet.com', 'israir.co.il', 'arkia.co.il', 'agoda.com', 'hotels.com',
    'trip.com', 'skyscanner.net',
  ]),
  MailCategory.social: Rules(domains: [
    'facebook.com', 'facebookmail.com', 'linkedin.com', 'instagram.com', 'twitter.com', 'x.com',
    'tiktok.com', 'pinterest.com', 'reddit.com', 'redditmail.com', 'youtube.com',
    'whatsapp.com', 'meetup.com', 'quora.com',
  ]),
  MailCategory.promotions: Rules(keywords: [
    'sale', '% off', 'discount', 'coupon', 'deal', 'limited time', 'free shipping',
    'black friday', 'cyber monday', 'offer', 'מבצע', 'הנחה', 'קופון', 'מבצעים', 'סייל',
    'משלוח חינם', 'לזמן מוגבל', 'בלעדי', 'הטבה', 'הטבות',
  ]),
};

class ClassifierConfig {
  final Set<String> myAddresses;
  final Set<String> familyAddresses;
  final List<String> familyNames;
  final Set<String> friendAddresses;
  final bool friendsFromSent;
  final Map<MailCategory, Rules> extraRules;

  const ClassifierConfig({
    this.myAddresses = const {},
    this.familyAddresses = const {},
    this.familyNames = const [],
    this.friendAddresses = const {},
    this.friendsFromSent = true,
    this.extraRules = const {},
  });
}

String domainOf(String addr) => addr.contains('@') ? addr.substring(addr.lastIndexOf('@') + 1) : '';

bool _domainMatches(String domain, List<String> domains) =>
    domains.any((d) => domain == d || domain.endsWith('.$d'));

bool _hasKeyword(String text, List<String> keywords) =>
    keywords.any((k) => text.contains(k.toLowerCase()));

class MailClassifier {
  final ClassifierConfig cfg;
  final Set<String> contacted;
  late final Map<MailCategory, Rules> rules;

  MailClassifier(this.cfg, {Set<String> contacted = const {}})
      : contacted = contacted.difference(cfg.myAddresses) {
    rules = {
      for (final c in MailCategory.values)
        c: (defaultRules[c] ?? const Rules()).merge(cfg.extraRules[c] ?? const Rules()),
    };
  }

  bool isHumanSender(MailMeta m) {
    final local = m.sender.split('@').first;
    return m.listUnsubscribe.isEmpty &&
        !_automated.hasMatch(local) &&
        !m.labels.contains('CATEGORY_PROMOTIONS');
  }

  MailCategory classify(MailMeta m) {
    final addr = m.sender, dom = domainOf(addr);
    final name = m.senderName.toLowerCase();
    final subject = m.subject.toLowerCase();
    final text = '$subject ${m.snippet.toLowerCase()}';
    final labels = m.labels.toSet();
    Rules r(MailCategory c) => rules[c]!;

    if (labels.contains('SENT') || cfg.myAddresses.contains(addr)) return MailCategory.other;

    if (cfg.familyAddresses.contains(addr) ||
        (isHumanSender(m) && cfg.familyNames.any((n) => name.contains(n) || addr.contains(n)))) {
      return MailCategory.family;
    }
    if (cfg.friendAddresses.contains(addr)) return MailCategory.friends;
    if (cfg.friendsFromSent &&
        contacted.contains(addr) &&
        personalDomains.contains(dom) &&
        isHumanSender(m)) {
      return MailCategory.friends;
    }

    if (_hasKeyword(subject, r(MailCategory.receipts).keywords)) return MailCategory.receipts;
    if (_domainMatches(dom, r(MailCategory.finance).domains)) return MailCategory.finance;
    if (_domainMatches(dom, r(MailCategory.travel).domains) ||
        _hasKeyword(subject, r(MailCategory.travel).keywords)) {
      return MailCategory.travel;
    }
    if (_domainMatches(dom, r(MailCategory.receipts).domains) &&
        _hasKeyword(text, r(MailCategory.receipts).keywords)) {
      return MailCategory.receipts;
    }
    if (_hasKeyword(subject, r(MailCategory.finance).keywords) && m.listUnsubscribe.isEmpty) {
      return MailCategory.finance;
    }

    if (_domainMatches(dom, r(MailCategory.social).domains) || labels.contains('CATEGORY_SOCIAL')) {
      return MailCategory.social;
    }
    if (labels.contains('CATEGORY_PROMOTIONS') ||
        _domainMatches(dom, r(MailCategory.promotions).domains) ||
        (m.listUnsubscribe.isNotEmpty && _hasKeyword(text, r(MailCategory.promotions).keywords))) {
      return MailCategory.promotions;
    }
    if (m.listUnsubscribe.isNotEmpty || labels.contains('CATEGORY_FORUMS')) {
      return MailCategory.newsletters;
    }
    if (labels.contains('CATEGORY_UPDATES') || _automated.hasMatch(addr.split('@').first)) {
      return MailCategory.notifications;
    }
    if (isHumanSender(m)) return MailCategory.personal;
    return MailCategory.other;
  }
}
