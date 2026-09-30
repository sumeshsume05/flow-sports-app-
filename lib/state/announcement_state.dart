import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Tracks the admin's current Home-screen announcement (a schedule change,
/// an important circular, etc.), backed by a single `config/announcement`
/// doc holding `{text}`. Purely a watcher: it never writes on its own
/// (writing needs admin auth, enforced by firestore.rules). Empty/missing
/// text means "no announcement" — the Home screen shows nothing.
class AnnouncementState extends ChangeNotifier {
  final FirebaseFirestore _db;
  String text = '';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  AnnouncementState({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance {
    _sub = _db.collection(configCollection).doc('announcement').snapshots().listen(_onChanged);
  }

  void _onChanged(DocumentSnapshot<Map<String, dynamic>> doc) {
    text = doc.exists ? (doc.data()?['text'] as String? ?? '') : '';
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
