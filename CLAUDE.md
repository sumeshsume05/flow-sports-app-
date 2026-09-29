# FLOW Arena

Live companion app for FLOW's internal company badminton tournament (an
anniversary sports event). Full context: see the "FLOW Arena — PRD" doc
(ask the user for the link, or check their Claude Docs list — it's not
duplicated here since it changes independently of the code).

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

## Firestore rules

Deploy with `firebase deploy --only firestore:rules --project
flow-sports-2026` (add `,firestore:indexes` when indexes changed too).
Admin-only writes on match/team/season data; viewers can only write their
own reaction, prediction, or chat message — never arbitrary fields.

## Git workflow (strict — follow exactly)

One feature/fix per branch, off `main`:

1. Implement → `flutter analyze` + `flutter test` → build debug APK →
   install on the physical test device → **user tests on-device**
2. Only on explicit **"tested, working — commit and push the branch"**:
   commit, push the branch, merge into local `main`
3. Only on explicit **"push main now"**: push local `main` to `origin/main`

Never skip the on-device test step. Never push `origin/main` without that
exact phrase, even right after merging to local `main`.
