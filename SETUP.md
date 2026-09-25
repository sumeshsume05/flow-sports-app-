# FLOW Sports App — Setup

This app is fully coded (data model, tournament logic, viewer + admin screens,
security rules), but it can't connect to a live backend until a Firebase
project exists. That step needs your Google/Firebase login, so it can't be
automated — do these once, in order.

## 1. Install the Firebase CLI + FlutterFire CLI (one-time, on this machine)

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

## 2. Log in to Firebase

```bash
firebase login
```
Opens a browser for your Google account. Use whichever Google account should
own this project (a shared team account is usually better than a personal one
for something you'll hand off later).

## 3. Create the Firebase project

Either via the [Firebase Console](https://console.firebase.google.com) ("Add
project"), or:
```bash
firebase projects:create flow-sports-2026
```
Keep it on the free **Spark plan** — nothing in this app needs Blaze/billing.

## 4. Enable Firestore and Authentication

In the Firebase Console for your new project:
- **Build > Firestore Database > Create database** — start in production mode
  (the rules file below replaces the defaults), pick a region close to your
  users.
- **Build > Authentication > Get started > Sign-in method > Email/Password**
  — enable it. This is only used for the 1-2 admin accounts; viewers never
  sign in.

## 5. Connect the Flutter app to your Firebase project

From this project's root directory:
```bash
flutterfire configure
```
Pick the project you just created, platform **Android** only. This
regenerates `lib/firebase_options.dart` with real credentials (it currently
contains placeholder values and the app cannot start without this step).

## 6. Deploy the security rules

```bash
firebase init firestore   # point it at the existing firestore.rules in this repo
firebase deploy --only firestore:rules
```

## 7. Run the app and seed initial data

```bash
flutter run
```
On a connected device/emulator. The Home screen loads with no data yet — that's
expected; teams/matches don't exist until seeded (next step).

## 8. Create your admin account(s)

1. Firebase Console → **Authentication → Users → Add user** — create an
   account for each of the 1-2 admins (email + password).
2. Copy each user's **UID** from that same screen.
3. Firebase Console → **Firestore Database → Start collection** → collection
   ID `admins` → document ID = the UID you copied → add a field
   `email` (string) = their email, `addedAt` (timestamp) = now.
4. Repeat for the second admin if there is one.

Only accounts with a doc in `admins/{uid}` can write data — everyone else
(including other logged-in accounts) is read-only, enforced by
`firestore.rules`.

## 9. Create a season, then seed initial team/match data

Every team and match belongs to a **season** — one per tournament run, since
this event is conducted multiple times a year and each run should keep its
own data instead of colliding with a previous run's.

1. In the app, sign in as an admin (`/admin/login`).
2. Tap the calendar icon on the **Admin Dashboard** (or go directly to
   **Admin > Seasons**) and create your first season — give it a label (e.g.
   "March 2026 Sports Meet") and a date. Creating a season also makes it the
   active one; everything below happens inside whichever season is active.
   To pick a season back up later (or switch between runs), open
   **Admin > Seasons** and tap **"Set as current"** on it — nothing is ever
   deleted when you switch.
3. Back on the **Admin Dashboard**, tap **"Seed Initial Data"** — this writes
   the 8 boys + 6 girls team pairs from the tournament sheet into the active
   season.
4. On the dashboard, tap **"Generate Schedule"** for Boys, then again for
   Girls — this creates the 28 + 15 round-robin league matches.
5. Once a category's league stage is fully played out, use
   **"Generate Bracket"** on the dashboard to create the top-4 knockout
   matches for that category (you'll be asked to confirm seed order if any
   teams are tied on points, with an option to schedule a real tie-breaker
   match instead of guessing).
6. Need to re-test the live flow before the real event? Each sport's
   dashboard section has a **"Reset [Sport] Data"** button in the danger
   zone — it clears that sport's matches/results for the active season
   (after a confirmation prompt) while keeping the teams, so you can
   regenerate the schedule and try again without re-typing every team name.
7. To download every match (league + knockout + any tie-breakers) for a
   sport, e.g. for record-keeping or sharing with organizers, tap
   **"Download CSV"** on that sport's dashboard section — it opens the share
   sheet so you can save it to Drive, email it, etc.

## 10. Distribute the APK internally

```bash
flutter build apk --release
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
  --app <YOUR_FIREBASE_ANDROID_APP_ID> \
  --groups "flow-employees"
```
The Android App ID is shown in Firebase Console → Project settings → Your
apps, after `flutterfire configure` registers the app. Create the
`flow-employees` tester group first under **Release & Monitor > App
Distribution > Testers & Groups**, and bulk-add employee emails there.

Two things worth telling employees ahead of time: they'll need to sign in
with a Google account matching their invite email to install via the App
Distribution link, and they'll need to allow "install unknown apps" the first
time. Send the install link a day or two before the event so people clear
this friction in advance.

---

**Not needed for V1:** push notifications. The `notifyTopic` field already
exists on every match document so this can be added later without a schema
change — see the plan file for what that would involve.
