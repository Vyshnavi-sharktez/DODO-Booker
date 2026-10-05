import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../firebase_options.dart';

// Must be a top-level function annotated with @pragma('vm:entry-point').
// Runs in a separate isolate — do not touch Navigator or UI state here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // The OS shows the notification automatically when the app is in background/closed.
  // Nothing else to do here.
}
