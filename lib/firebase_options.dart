// PLACEHOLDER — replace this entire file by running `flutterfire configure`
// from the project root once the Firebase project exists (see SETUP.md).
// That command requires an interactive Google/Firebase login and regenerates
// this file with real project credentials. The app will not connect to
// Firebase until that's done.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          '$defaultTargetPlatform is not configured for this app — Android only for V1.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCPHbFZcYHlZ8fjBCN1dxrmlbmqgG2MpJo',
    appId: '1:590945144660:android:b8ca54c6e8dd5e4e9c82c1',
    messagingSenderId: '590945144660',
    projectId: 'flow-sports-2026',
    storageBucket: 'flow-sports-2026.firebasestorage.app',
  );
}
