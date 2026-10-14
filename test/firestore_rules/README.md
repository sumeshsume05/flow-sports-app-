# Firestore rules tests (cricket ball log)

Runs `firestore.rules` against the **local emulator** with a made-up project
(`demo-flow-test`) — it never touches the real `flow-sports-2026` project.

Needs Node, `firebase-tools` and Java 21+ (firebase-tools no longer runs the
emulator on older Java).

```
cd test/firestore_rules && npm install && cd ../..
RULES_FILE=$PWD/firestore.rules firebase emulators:exec --only firestore \
  --project demo-flow-test "cd test/firestore_rules && node balls.test.js"
```
