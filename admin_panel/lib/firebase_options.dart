import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'Admin panel only supports web.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCZ2ad3pqaYjhs5hTDttn6mwX8yuxBBwlE',
    appId: '1:793067837126:web:05f0b1b51874e2a99f29c7',
    messagingSenderId: '793067837126',
    projectId: 'dodo-booker-10507',
    storageBucket: 'dodo-booker-10507.firebasestorage.app',
    authDomain: 'dodo-booker-10507.firebaseapp.com',
    measurementId: 'G-TG4RNFPXQY',
  );
}
