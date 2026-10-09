import 'dart:math';

enum PlayerRole { bat, bowl, all, wk }

extension PlayerRoleLabel on PlayerRole {
  String get label => switch (this) {
        PlayerRole.bat => 'Batter',
        PlayerRole.bowl => 'Bowler',
        PlayerRole.all => 'All-rounder',
        PlayerRole.wk => 'Wicket-keeper',
      };
}

/// A member of a cricket team's player list (`teams/{id}.players`). The [id]
/// is stable for the player's lifetime: match lineups and ball events store
/// ids, never names, so renaming a player can't leave stale copies anywhere.
/// A player is never hard-deleted once they might have history — they are
/// deactivated ([active] = false) instead.
class Player {
  final String id;
  final String name;
  final PlayerRole? role;
  final bool active;

  const Player({required this.id, required this.name, this.role, this.active = true});

  static final _rng = Random();
  static var _counter = 0;

  /// Locally generated id, unique across a bulk add and across devices.
  static String newId() =>
      'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_counter++).toRadixString(36)}${_rng.nextInt(1 << 20).toRadixString(36)}';

  Player copyWith({String? name, PlayerRole? role, bool clearRole = false, bool? active}) => Player(
        id: id,
        name: name ?? this.name,
        role: clearRole ? null : (role ?? this.role),
        active: active ?? this.active,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role?.name,
        'active': active,
      };

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        id: map['id'] as String,
        name: map['name'] as String,
        role: PlayerRole.values.where((r) => r.name == map['role']).firstOrNull,
        active: map['active'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is Player &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, name, role, active);
}
