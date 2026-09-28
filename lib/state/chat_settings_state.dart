import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Tracks whether chat is currently open, backed by a single
/// `config/chatSettings` doc holding `{enabled}`. Purely a watcher: it never
/// writes on its own (writing needs admin auth, enforced by
/// firestore.rules). The doc not existing yet means "never toggled off" —
/// `chatEnabled` defaults to true so nothing changes for existing installs
/// until an admin explicitly flips it from Admin Dashboard.
class ChatSettingsState extends ChangeNotifier {
  final FirebaseFirestore _db;
  bool chatEnabled = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  ChatSettingsState({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance {
    _sub = _db
        .collection(configCollection)
        .doc('chatSettings')
        .snapshots()
        .listen(_onChanged);
  }

  void _onChanged(DocumentSnapshot<Map<String, dynamic>> doc) {
    chatEnabled = doc.exists ? (doc.data()?['enabled'] as bool? ?? true) : true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
