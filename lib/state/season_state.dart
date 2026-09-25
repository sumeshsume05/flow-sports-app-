import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Tracks which season is currently "active" — the one every screen reads
/// and writes against. Backed by a single `config/activeSeason` doc holding
/// `{seasonId}`. Purely a watcher: it never writes on its own (writing needs
/// admin auth, enforced by firestore.rules), so `activeSeasonId` is `null`
/// until an admin creates the first season from Admin > Seasons.
class SeasonState extends ChangeNotifier {
  final FirebaseFirestore _db;
  String? activeSeasonId;
  bool isLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  SeasonState({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance {
    _sub = _db
        .collection(configCollection)
        .doc('activeSeason')
        .snapshots()
        .listen(_onChanged);
  }

  void _onChanged(DocumentSnapshot<Map<String, dynamic>> doc) {
    activeSeasonId = doc.exists ? (doc.data()?['seasonId'] as String?) : null;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
