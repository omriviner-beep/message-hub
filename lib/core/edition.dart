/// "lite" build: no SMS access and no notification listener, so Google Play
/// Protect does not block installing it outside the Play Store.
/// Built with: flutter build apk --flavor lite --dart-define=LITE=true
const isLite = bool.fromEnvironment('LITE');

/// Message sources available in this edition.
const smsSupportedInEdition = !isLite;
const waNotificationsInEdition = !isLite;
