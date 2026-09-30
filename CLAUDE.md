# FLOW Arena

Live companion app for FLOW's internal company badminton tournament (an
anniversary sports event). Full context, goals, and the tournament-engine
roadmap: see the **FLOW Arena — PRD** doc:
https://claude.ai/code/artifact/dd15edcd-f14d-47b7-b39b-0bd18970826d
(a Claude Doc, kept here so it's reachable from any machine this repo is
cloned onto — not duplicated in full here since it changes independently
of the code and is meant to be edited in place, not copy-pasted).

- App ID: `com.flowglobal.flow_sports_app`
- Android only (no iOS, no web)
- Sideloaded via a WhatsApp-shared GitHub Releases link — not on Play Store

## Stack

- Flutter, `provider` for state, `go_router` for navigation (viewer screens
  share a floating chat button via a `ShellRoute`; `/chat` and `/bracket`
  stay outside it — see comments in `lib/routes/app_router.dart` for why)
- Firebase: Firestore (data), Firebase Auth (admin login only — viewers stay
  anonymous), Firebase Hosting (serves only `version.json`, see below)
- Firebase project: `flow-sports-2026`, **Spark (free) plan by design** —
  this is a one-off internal event, not a funded product

## Key constraint: Spark plan blocks serving .apk from Hosting

Firebase Hosting's free tier refuses to serve `.apk`/`.exe`/`.dll` files by
extension. That's why the release APK lives on GitHub Releases (stable
`latest` tag, same download URL every release) instead of Hosting —
Hosting only serves the small `version.json` update-check manifest.

## Commands

```
flutter analyze
flutter test
flutter build apk --debug      # for on-device testing
flutter build apk --release    # for actual releases (needs android/key.properties)
```

## Release process

`scripts/publish_release.sh` — bump `version:` in `pubspec.yaml` first,
then run `GITHUB_TOKEN=ghp_xxx scripts/publish_release.sh [--force]
[--changelog "..."]`. It builds the signed release APK, replaces the GitHub
Release asset, and deploys the new `version.json` to Hosting. `--force`
marks the update mandatory (blocks the app until updated); omit it for a
normal dismissible prompt.

Requires `android/key.properties` (gitignored, only exists on this
machine) — losing it breaks in-place updates for every existing install.

**No staging channel exists.** `version.json` is one global file every
installed copy of the app checks — there's no way to test the
optional/critical update flow against only one device without it being a
real release that every current user's app also sees. For a low-risk
change (like a cosmetic one), just do the real release and treat it as
the test. For testing a build on one person's phone *without* touching
the update pipeline at all, build the APK locally and send it to them
directly (bypasses GitHub Releases and `version.json` entirely, so no
other install is affected).

## Tournament / match logic

The codebase deliberately keeps each sport's rules self-contained (plain
string `Sport`/`Category` identifiers in `lib/core/constants.dart`, looped
over via `Sport.all`/`Category.all` — see the comments there) so adding a
new sport later means adding a new entry plus that sport's own logic
functions, **not** editing badminton's. If a new sport is added, give it
its own subsection below rather than folding it into badminton's rules.

### Badminton (current, only sport implemented)

- **League stage** (`lib/core/utils/standings_calculator.dart`): win = 2
  pts, tie = 1 pt, loss = 0. Ranked by points, then total points scored
  (own game score summed across matches) as the tiebreaker — same role as
  goal difference/run rate elsewhere.
- **League format — flat or sectioned** (admin's choice, driven purely by
  whether teams have a `section` assigned in Admin > Teams — no separate
  toggle): either one flat round-robin table (`generateLeagueMatches`), or
  teams split into league sections (e.g. Section A/B) that only play
  round-robin *within* their own section (`generateSectionedLeagueMatches`,
  `Team.section`/`Match.section`). Sectioned mode is currently fixed at
  exactly 2 sections, 2 qualifiers each, to fit the bracket below — see
  "Planned changes" for lifting that fixed shape.
- **Qualifying for the knockout stage**: top 4 by that ranking (flat mode),
  or each section's top 2 combined (sectioned mode — seeded as Section A's
  #1 vs Section B's #1, Section A's #2 vs Section B's #2, so KO1/KO2 never
  pit two teams from the same section against each other). A genuine tie
  (same points *and* same points scored) at the cutoff — the 4th-place
  cutoff in flat mode, the 2nd-place cutoff within each section in
  sectioned mode — triggers a tie-breaker match between just the tied
  teams (`resolveTieChain`, generalized via `cutoffCount`) rather than
  being guessed — can chain into further rounds if still tied after one.
- **Knockout bracket** (`lib/core/utils/bracket_resolver.dart`) — a fixed
  4-team "page playoff", not a generic bracket generator:
  - KO1: Seed 1 vs Seed 2 → winner goes **straight to the Final**
  - KO2: Seed 3 vs Seed 4 → winner advances to KO3
  - KO3: KO1's loser vs KO2's winner → winner is the Final's 2nd finalist
  - KOF (Final): KO1's winner vs KO3's winner
- **Podium** (`lib/core/utils/podium_resolver.dart`): 1st/2nd = KOF
  winner/loser; the two semifinalists = KO2 and KO3's losers. Derived
  entirely from the 4 knockout matches, no separate podium data.
- **Ties are never guessed** — a knockout match can't legitimately end
  level in badminton, so the admin's score-entry screen blocks entering a
  tied result there, and both `resolveDependentSlots` and `computePodium`
  throw/return-undecided rather than silently treating "not team A" as
  "team B won."

#### Planned changes (beyond what's shipped, as of 2026-09-30)

**Shipped** (2026-09-30): the "sections feed one shared knockout" format
described above — exactly 2 sections, 2 qualifiers each, admin assigns
teams to sections, schedule/standings/bracket all became section-aware.
This was the PRD's "Example Format 1"; Format 2 (sections resolve fully
independently, no shared knockout) is **not** built.

**Still not built** — the goal remains a fully configurable tournament
engine, not hardcoded badminton rules: admins define a tournament's
sections, qualification rules, bracket shape, tie-breakers, and stages
through configuration, per sport — not through code changes per format.
Concretely, still missing:
- Any section count/qualifier count other than the fixed "2 sections,
  2 each" shape (needed to fit the still-fixed 4-team bracket)
- Format 2 (sections resolving fully independently — no shared knockout)
- Alternate league scheduling (admin manually schedules matches / the
  system allocates them) as an alternative to round-robin
- A flexible stage/round sequence beyond the fixed KO1/KO2/KO3/KOF codes
- Any sport other than badminton

Full detail — including the worked example formats, the complete list of
dimensions to make configurable, a 4-phase suggested roadmap diagram, and
an architecture sketch — lives in the "Future Adaptation Plan" section of
the FLOW Arena PRD linked at the top of this file. This note is
intentionally a summary, not a duplicate — treat the PRD as the source of
truth for this plan, since it's a living doc the user may keep editing.

## Firestore rules

Deploy with `firebase deploy --only firestore:rules --project
flow-sports-2026` (add `,firestore:indexes` when indexes changed too).
Admin-only writes on match/team/season data; viewers can only write their
own reaction, prediction, or chat message — never arbitrary fields.

**Config-doc pattern** (`config/{docId}`, public read + admin-only write):
used for both the chat on/off toggle (`config/chatSettings`) and the
Home-screen announcement (`config/announcement`) — reuse this same shape
for any future single-value admin setting rather than inventing a new one.

**No analytics SDK — a custom `presence` collection instead.** Admin's
install/active-now counts (`admin_dashboard_screen.dart`) are *not* backed
by `firebase_analytics` (not a dependency, deliberately) — they're backed
by a lightweight `presence/{deviceId}` collection (doc id = the same
locally-generated device id already used for chat identity), written via
a fire-and-forget register-or-heartbeat call in `app.dart`, and read via
cheap Firestore `.count()` aggregation queries, admin-only. Don't suggest
adding an analytics package for usage-tracking asks — this pattern already
covers it and keeps everything inside the existing Firestore/Spark-plan
architecture.

## Git workflow (strict — follow exactly)

One feature/fix per branch, off `main`:

1. Implement → `flutter analyze` + `flutter test` → build debug APK →
   install on the physical test device → **user tests on-device**
2. Only on explicit **"tested, working — commit and push the branch"**:
   commit, push the branch, merge into local `main`
3. Only on explicit **"push main now"**: push local `main` to `origin/main`

Never skip the on-device test step. Never push `origin/main` without that
exact phrase, even right after merging to local `main`.
