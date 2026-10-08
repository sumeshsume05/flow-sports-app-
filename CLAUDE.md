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

Client side, `AppUpdateGate` (`lib/widgets/app_update_gate.dart`, mounted
once around the whole app) checks `version.json` on launch *and* on every
app resume (not just launch) — a release published while the app was
backgrounded still prompts without waiting for a relaunch. A dismissible
prompt is shown once per distinct `latestVersionCode`, not once per
app-open, so dismissing it doesn't mean never seeing it again, just not
re-nagging about the same version repeatedly.

## Seasons

Every team/match/standing doc carries a `season` id
(`lib/models/season.dart`, `admin_seasons_screen.dart`) — this event runs
multiple times a year, and each run gets its own Season rather than
colliding with the previous run's data. `config/activeSeason` is a single
**global** Firestore document every viewer and admin screen watches
(`SeasonState`) — switching it instantly changes what literally everyone
sees, live, across the whole event, with no per-device override.

Creating a new season **immediately activates it** — there's no separate
"activate" step and no staging/preview season. This is why testing a
schema or format change safely during a live event can't use a new
season (it would switch every viewer over instantly) — the pattern used
so far instead is a throwaway category (e.g. `'test'`) within the *same*
already-active season, since the Home screen only ever renders cards for
`Category.all` (`boys`/`girls`), so a `'test'` category is reachable by
admin via direct route navigation but invisible to every viewer.

`legacySeasonId` (`lib/core/constants.dart`, currently `'2026'`) is the
season id data was written under before this multi-season feature
existed — the Seasons screen's empty state suggests creating a season
labeled with that id to "adopt" any such pre-existing data rather than
losing it.

## Admin ↔ viewer navigation

Admin screens (`/admin/*`) are plain top-level `GoRoute`s outside the
viewer `ShellRoute` — no shared bottom nav/drawer between the two sides.
The Admin Dashboard AppBar has a "View live app" icon
(`Icons.visibility_outlined`, `admin_dashboard_screen.dart`) that does a
plain `context.go('/')` — deliberately *not* the adjacent Logout icon's
`signOut()` — so an admin can check what viewers currently see without
ending their session. The Home screen's own admin icon
(`Icons.admin_panel_settings_outlined`, `home_screen.dart`) routes back to
`/admin` and, since the admin is still signed in, lands straight on the
dashboard with no login prompt. (Before this existed, the only way back
to Home from Admin was the Logout icon, which — as a side effect — forced
a re-login on the way back; that was the actual cause of "admin has to
sign in again every time," not a session-persistence bug.)

## Match engagement & live features

Independent of tournament stage/rules — these apply to any match:

- **Live commentary** (`lib/widgets/commentary_ticker.dart`,
  `FirestoreService.postCommentary`/`watchCommentary`) — free-text updates
  the admin posts against a match, stored in a `matches/{id}/commentary`
  subcollection, with `lastCommentaryText`/`lastCommentaryAt` denormalized
  onto the match doc so the match list can preview the latest entry
  without an extra listener per card.
- **Live score** (shipped 2026-10-07) — a per-team +/- control
  (`admin_match_edit_screen.dart`'s Live Score card, shown only while
  `status == live`) that writes straight to the *same* `scoreA`/`scoreB`
  the final-result entry uses (`FirestoreService.incrementLiveScore`, a
  Firestore transaction, clamped at 0) rather than a separate counter —
  finishing a match is just reviewing the live-built number and tapping
  the existing Save Result button, nothing to retype or reconcile. Every
  tap also appends to a `matches/{id}/pointLog` subcollection (same
  append-only shape as `commentary` — a wrong tap is corrected by a new
  entry, never an edit or delete), rendered as a point-by-point history on
  the match detail screen (`lib/widgets/point_log_ticker.dart`) and as a
  prominent accent-colored scoreboard on the match card/detail screen
  while live (the small per-row score only shows for
  `upcoming`/`completed`, to avoid showing the same number twice). The
  live scoreboard shows each team's name directly above its own number
  (`_LiveScoreboard` in both `match_card.dart` and
  `match_detail_screen.dart`) rather than relying on the plain name rows
  below — those rows are hidden entirely while live — so which score
  belongs to which team is never ambiguous from a single glance.
- **Reactions** (`lib/widgets/reaction_bar.dart`,
  `FirestoreService.incrementReaction`) — viewer emoji taps, no admin auth
  required, a `reactionCounts` map on the match doc updated via
  `FieldValue.increment`.
- **Predictions** (`lib/widgets/prediction_widget.dart`,
  `FirestoreService.castPrediction`) — viewer "who wins" pick before a
  match starts, a `predictionCounts` map, same no-auth/atomic-increment
  pattern as reactions; switching a pick decrements the old choice and
  increments the new one in one write.
- **CSV export** (`lib/core/utils/match_export.dart`'s `buildMatchesCsv`,
  triggered from the admin dashboard) — every match across every
  stage/category for a sport/season, one downloadable file.

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
  4-team "page playoff", not a generic bracket generator (the qualifier
  count feeding it is admin-configurable — 2, 3, or 4 — see below):
  - KO1: Seed 1 vs Seed 2 → winner goes **straight to the Final**
  - KO2: Seed 3 vs Seed 4 → winner advances to KO3
  - KO3: KO1's loser vs KO2's winner → winner is the Final's 2nd finalist
  - KOF (Final): KO1's winner vs KO3's winner
- **Final format — Single or Best-of-3** (admin's choice at bracket
  generation time, independent of qualifier count/sectioning): Single
  generates one `KOF` match as above; Best-of-3 generates `KOF1`/`KOF2`
  instead, sharing identical `teamASource`/`teamBSource` so the existing
  `resolveDependentSlots` resolves both from one completed match with no
  special-casing. If Games 1–2 split 1-1, the admin explicitly schedules a
  decider (`KOF3`, via `generateFinalGame3`) from the same Generate Bracket
  screen — mirrors the existing tie-breaker-scheduling action rather than
  auto-creating it, since it's only sometimes needed.
- **Podium** (`lib/core/utils/podium_resolver.dart`): 1st/2nd = KOF
  winner/loser (or, for a best-of-3 Final, whoever wins 2 of
  KOF1/KOF2/KOF3); the two semifinalists = KO2 and KO3's losers. Derived
  entirely from the knockout matches that exist, no separate podium data.
- **Ties are never guessed** — a knockout match can't legitimately end
  level in badminton, so the admin's score-entry screen blocks entering a
  tied result there, and both `resolveDependentSlots` and `computePodium`
  throw/return-undecided rather than silently treating "not team A" as
  "team B won."

#### Planned changes (beyond what's shipped, as of 2026-10-06)

**Shipped** (2026-09-30): the "sections feed one shared knockout" format
described above — exactly 2 sections, 2 qualifiers each, admin assigns
teams to sections, schedule/standings/bracket all became section-aware.
This was the PRD's "Example Format 1"; Format 2 (sections resolve fully
independently, no shared knockout) is **not** built.

**Shipped** (2026-10-05, qualifier count): the flat (non-sectioned) knockout
qualifier count is admin-configurable — 2, 3, or 4, not always 4 — via a
picker on the Generate Bracket screen, for situations like a team
withdrawing mid-tournament. Sectioned mode stays fixed at 2 sections x 2
qualifiers each.

**Shipped** (2026-10-06): the Final format — Single or Best-of-3 — is
admin-configurable at bracket generation time, for both Girls and Boys,
flat or sectioned. See "Final format" above.

**Still not built** — the goal remains a fully configurable tournament
engine, not hardcoded badminton rules: admins define a tournament's
sections, qualification rules, bracket shape, tie-breakers, and stages
through configuration, per sport — not through code changes per format.
Concretely, still missing:
- Any section count other than exactly 2 (needed to fit the still-fixed
  4-team bracket)
- Format 2 (sections resolving fully independently — no shared knockout)
- Alternate league scheduling (admin manually schedules matches / the
  system allocates them) as an alternative to round-robin
- A flexible stage/round sequence beyond the fixed KO1/KO2/KO3/KOF(1/2/3)
  codes
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
used for the chat on/off toggle (`config/chatSettings`), the Home-screen
announcement (`config/announcement`), and which season is currently active
(`config/activeSeason`, see "Seasons" above) — reuse this same shape for
any future single-value admin setting rather than inventing a new one.
A `pointLog` entry is append-only by contrast (`allow update, delete:
if false`) — see "Match engagement & live features" above — since it's a
log, not a single current value.

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
