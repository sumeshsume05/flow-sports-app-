import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/sports.dart';

/// Which sports viewers can see on Home, backed by a single
/// `config/enabledSports` doc shaped `{badminton: true, cricket: false}`.
/// Purely a watcher: it never writes on its own (writing needs admin auth,
/// enforced by firestore.rules). A sport the doc doesn't mention (or the doc
/// not existing at all) falls back to [SportConfig.enabledByDefault], so
/// nothing changes for existing installs until an admin sets a value.
class EnabledSportsState extends ChangeNotifier {
  final FirebaseFirestore _db;
  Map<String, bool> _flags = const {};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  EnabledSportsState({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance {
    _sub = _db.collection(configCollection).doc('enabledSports').snapshots().listen(_onChanged);
  }

  void _onChanged(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    _flags = {
      for (final e in data.entries)
        if (e.value is bool) e.key: e.value as bool,
    };
    notifyListeners();
  }

  bool isEnabled(String sport) => resolveSportEnabled(_flags, sport);

  /// Sports viewers should see, in [Sport.all] order.
  List<String> get viewerSports => Sport.all.where(isEnabled).toList();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Pure so it's unit-testable without Firestore: an explicit flag wins,
/// otherwise the sport's own default.
bool resolveSportEnabled(Map<String, bool> flags, String sport) =>
    flags[sport] ?? sportConfig(sport).enabledByDefault;
