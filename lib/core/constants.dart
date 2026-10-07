/// Sport/category identifiers used across the app. Kept as plain strings
/// (not hardcoded into logic) so adding another sport later — Cricket, Carrom,
/// Chess, Dartboard, all present in the source tracking sheet — means adding
/// entries here, not rewriting screens or Firestore queries. Screens loop
/// over `.all` instead of hand-writing one block per sport/category.
class Sport {
  static const badminton = 'badminton';
  static const all = [badminton];
}

class Category {
  static const boys = 'boys';
  static const girls = 'girls';
  static const all = [boys, girls];
}

/// Human-readable label for a category — single source of truth, replacing
/// the `category == Category.boys ? 'Boys' : 'Girls'` ternary that used to be
/// duplicated across several screens.
String categoryLabel(String category) => switch (category) {
      Category.boys => 'Boys',
      Category.girls => 'Girls',
      _ => category,
    };

const teamsCollection = 'teams';
const matchesCollection = 'matches';
const adminsCollection = 'admins';
const configCollection = 'config';
const seasonsCollection = 'seasons';
const chatMessagesCollection = 'chatMessages';
const presenceCollection = 'presence';

/// Bounds the live chat query so reads stay cheap regardless of how many
/// messages accumulate over the event.
const chatWindowSize = 50;
const chatMessageMaxLength = 280;
const chatDisplayNameMaxLength = 24;

/// Enforced on the trimmed name — a name that's just spaces padded out to
/// this length (or beyond) still doesn't count, since trimming collapses it
/// away first.
const chatDisplayNameMinLength = 4;

/// Subcollection name under `matches/{matchId}` for live commentary entries.
const commentaryCollection = 'commentary';
const commentaryMaxLength = 200;

/// Subcollection name under `matches/{matchId}` for the live-score +/- point
/// log — append-only, mirrors [commentaryCollection]'s shape.
const pointLogCollection = 'pointLog';

/// Reaction keys viewers can tap on a match — single source of truth for
/// both the Firestore field names (`match.reactionCounts[key]`) and the
/// emoji glyphs shown in the UI.
class ReactionEmoji {
  static const thumbsUp = 'thumbsUp';
  static const fire = 'fire';
  static const wow = 'wow';
  static const all = [thumbsUp, fire, wow];
}

String reactionEmojiGlyph(String key) => switch (key) {
      ReactionEmoji.thumbsUp => '👍',
      ReactionEmoji.fire => '🔥',
      ReactionEmoji.wow => '😮',
      _ => '❔',
    };

/// Keys viewers can pick when predicting a match's winner — single source
/// of truth for the Firestore field names (`match.predictionCounts[key]`)
/// and which `TeamRef` on `Match` each one maps to.
class PredictionChoice {
  static const teamA = 'teamA';
  static const teamB = 'teamB';
  static const all = [teamA, teamB];
}

/// The season id used to seed the very first `Season` doc on first run, and
/// to match every pre-existing team/match doc written before seasons existed
/// (they all carry `season: '2026'` already — using the same string as the
/// first season's id means no backfill/migration is needed).
const legacySeasonId = '2026';
