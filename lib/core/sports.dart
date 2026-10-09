import 'package:flutter/material.dart';

import 'constants.dart';

/// Everything about a sport that screens need for *presentation* — one place
/// to add the next sport's label/icon/blurb instead of hunting for hardcoded
/// strings across screens. Rules/scoring logic does NOT live here: each
/// sport keeps its own self-contained logic files (see the Tournament /
/// match logic section of CLAUDE.md).
class SportConfig {
  final String id;
  final String label;
  final IconData icon;

  /// Home-screen card title for one category of this sport, e.g.
  /// "Boys Doubles" for badminton.
  final String Function(String category) categoryTitle;

  /// Home-screen card subtitle.
  final String subtitle;

  /// Whether viewers see this sport when `config/enabledSports` doesn't say
  /// either way. A sport still being built ships `false` so it can be in a
  /// release without being visible to viewers; admin always sees every
  /// sport (marked "hidden from viewers") and flips it on when it's ready.
  final bool enabledByDefault;

  const SportConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.categoryTitle,
    required this.subtitle,
    this.enabledByDefault = true,
  });
}

/// Registry keyed by sport id. Keep in step with [Sport.all].
final Map<String, SportConfig> sportConfigs = {
  Sport.badminton: SportConfig(
    id: Sport.badminton,
    label: 'Badminton',
    icon: Icons.sports_tennis,
    categoryTitle: (category) => '${categoryLabel(category)} Doubles',
    subtitle: 'Standings, live scores & the knockout bracket',
  ),
};

/// Falls back to a bare config for an unknown id (e.g. a doc written by a
/// newer app version) so a screen never crashes on it.
SportConfig sportConfig(String id) =>
    sportConfigs[id] ??
    SportConfig(
      id: id,
      label: id,
      icon: Icons.sports,
      categoryTitle: categoryLabel,
      subtitle: '',
    );

/// Reads the `sport` query parameter the router passes to sport-scoped
/// screens. A missing/unknown value means badminton, so every link and
/// bookmark that predates the sport parameter keeps working.
String sportFromQuery(String? value) =>
    value != null && Sport.all.contains(value) ? value : Sport.badminton;
