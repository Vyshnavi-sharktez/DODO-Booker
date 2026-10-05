// Firebase Messaging Service Worker for Admin Panel web push notifications.
// IMPORTANT: Replace all REPLACE_WITH_REAL_VALUE placeholders with real Firebase
// config values (same values as firebase_options.dart).
// This file is NOT updated by `flutterfire configure` — update manually.

importScripts('https://www.gstatic.com/firebasejs/10.14.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey:            'AIzaSyCZ2ad3pqaYjhs5hTDttn6mwX8yuxBBwlE',
  authDomain:        'dodo-booker-10507.firebaseapp.com',
  projectId:         'dodo-booker-10507',
  storageBucket:     'dodo-booker-10507.firebasestorage.app',
  messagingSenderId: '793067837126',
  appId:             '1:793067837126:web:05f0b1b51874e2a99f29c7',
});

const messaging = firebase.messaging();

// Show a notification when the app tab is in the background.
// When the app tab is in the foreground, DodoAdminApp.foregroundStream handles display.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification ?? {};
  const title = notification.title;
  const body  = notification.body;
  if (!title) return;
  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
  });
});
