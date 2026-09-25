import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/utils/podium_resolver.dart';
import '../../models/match.dart';
import '../../services/firestore_service.dart';
import '../../widgets/bracket_tree.dart';
import '../../widgets/podium_card.dart';

class BracketScreen extends StatelessWidget {
  final String category;
  final String season;
  final _firestoreService = FirestoreService();
  late final _matchesStream =
      _firestoreService.watchMatches(sport: Sport.badminton, category: category, season: season);

  BracketScreen({super.key, required this.category, required this.season});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knockout Bracket')),
      body: StreamBuilder<List<Match>>(
        stream: _matchesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final knockoutMatches =
              snapshot.data!.where((m) => m.stage == MatchStage.knockout).toList();
          final podium = computePodium(knockoutMatches);
          return SingleChildScrollView(
            child: Column(
              children: [
                if (podium != null) PodiumCard(podium: podium),
                BracketTree(
                  knockoutMatches: knockoutMatches,
                  onTapMatch: (m) => context.push('/matches/${m.id}'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
