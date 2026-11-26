/// Shared, source-independent data model.
library;

enum Source { gmail, whatsapp, sms }

extension SourceLabel on Source {
  String get label => switch (this) {
        Source.gmail => 'Gmail',
        Source.whatsapp => 'וואטסאפ',
        Source.sms => 'SMS',
      };
}

/// One message, reduced to what the statistics need. Never holds message text.
class MsgEvent {
  final DateTime time;
  final bool outgoing;
  final Source source;
  final String contact;
  final int bytes;

  const MsgEvent({
    required this.time,
    required this.outgoing,
    required this.source,
    this.contact = '',
    this.bytes = 0,
  });
}

class DailyStat {
  final DateTime day;
  final int incoming;
  final int outgoing;

  const DailyStat(this.day, this.incoming, this.outgoing);

  int get total => incoming + outgoing;
}

class ContactStat {
  final String contact;
  final int incoming;
  final int outgoing;
  final int bytes;

  const ContactStat(this.contact, this.incoming, this.outgoing, this.bytes);

  int get total => incoming + outgoing;
}

class Summary {
  final int incoming;
  final int outgoing;
  final int bytes;
  final int days;
  final DailyStat? busiestDay;
  final int today;

  const Summary({
    required this.incoming,
    required this.outgoing,
    required this.bytes,
    required this.days,
    required this.busiestDay,
    required this.today,
  });

  int get total => incoming + outgoing;
  double get avgPerDay => days == 0 ? 0 : total / days;
}

/// A slice of storage, e.g. "WhatsApp Images" or "Gmail promotions".
class StorageSlice {
  final String label;
  final int bytes;
  final int count;

  const StorageSlice(this.label, this.bytes, this.count);
}
