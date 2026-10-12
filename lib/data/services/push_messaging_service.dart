// Foxfin: Firebase Cloud Messaging removed. This no-op keeps the public API
// that the rest of the app calls, so push registration simply never happens.
// Modified from Moonfin (GPL-2.0-or-later); see NOTICE.
import 'dart:async';

class PushMessagingService {
  Future<void> initialize() async {}
  Future<void> registerWithCurrentToken() async {}
  Future<void> unregister() async {}
}
