#!/usr/bin/env bash
# Publishes a new FLOW Arena release: builds the release APK, uploads it to
# a GitHub Release at a STABLE URL (the "latest" tag's asset is replaced
# each time, never a new tag per release), and publishes a small version
# manifest to Firebase Hosting. The WhatsApp link only ever needs to be
# shared once — new installs get whatever's current, existing installs get
# prompted in-app.
#
# Why GitHub Releases and not Firebase Hosting for the APK itself: Firebase
# Hosting's free Spark plan blocks serving .apk/.exe/.dll/.ipa files by
# extension (a deliberate anti-abuse policy, not a bug) — see
# https://firebase.google.com/support/faq#hosting-exe-restrictions. GitHub
# Releases has no such restriction and this repo already lives there.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx scripts/publish_release.sh [--force] [--changelog "What's new"]
#
#   --force              Marks this release mandatory — existing installs
#                         are blocked from using the app until they update.
#                         Omit for a normal, dismissible update prompt.
#   --changelog TEXT      Optional short "what's new" text shown in the
#                         update prompt.
#
# Version name/code are read straight from pubspec.yaml's `version:` field
# — bump that before running this script, same as any normal Flutter release.
#
# Requires:
#   - GITHUB_TOKEN env var — a GitHub personal access token with `repo` scope
#     (needed to create the release/upload the asset; end users never need
#     this, only whoever runs this script). The repo must be public for
#     end users to download the asset without a token.
#   - An already-authenticated `firebase` CLI session (same one used for
#     `firebase deploy --only firestore:rules` elsewhere in this repo).
#   - android/key.properties set up (see android/app/build.gradle.kts) so
#     the build is signed with the release key, not the debug one.

set -euo pipefail
cd "$(dirname "$0")/.."

GITHUB_REPO="sumeshsume05/flow-sports-app-"
RELEASE_TAG="latest"
ASSET_NAME="flow-arena.apk"

FORCE=false
CHANGELOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --changelog) CHANGELOG="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "error: GITHUB_TOKEN env var not set — needed to publish the APK to GitHub Releases." >&2
  echo "Generate one at https://github.com/settings/tokens (repo scope) and re-run as:" >&2
  echo "  GITHUB_TOKEN=ghp_xxx $0 ..." >&2
  exit 1
fi

if [[ ! -f android/key.properties ]]; then
  echo "error: android/key.properties not found — release builds need the real signing key, not the debug one." >&2
  exit 1
fi

VERSION_LINE=$(grep -E '^version:' pubspec.yaml)
VERSION_FULL=$(echo "$VERSION_LINE" | sed -E 's/version:\s*//')
VERSION_NAME=$(echo "$VERSION_FULL" | cut -d'+' -f1)
VERSION_CODE=$(echo "$VERSION_FULL" | cut -d'+' -f2)

if [[ -z "$VERSION_NAME" || -z "$VERSION_CODE" || "$VERSION_NAME" == "$VERSION_CODE" ]]; then
  echo "error: couldn't parse version from pubspec.yaml (\"$VERSION_LINE\") — expected the form X.Y.Z+N." >&2
  exit 1
fi

FORCE_LABEL=""
[[ "$FORCE" == true ]] && FORCE_LABEL=", forced"
echo "Publishing FLOW Arena $VERSION_NAME (build $VERSION_CODE)$FORCE_LABEL..."

flutter build apk --release
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

GH_API="https://api.github.com/repos/$GITHUB_REPO"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"

echo "Looking up the '$RELEASE_TAG' release..."
RELEASE_JSON=$(curl -s -H "$AUTH_HEADER" "$GH_API/releases/tags/$RELEASE_TAG")
RELEASE_ID=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))")

if [[ -z "$RELEASE_ID" ]]; then
  echo "No '$RELEASE_TAG' release yet — creating it..."
  RELEASE_JSON=$(curl -s -H "$AUTH_HEADER" -X POST "$GH_API/releases" \
    -d "{\"tag_name\":\"$RELEASE_TAG\",\"name\":\"Latest build\",\"body\":\"Always overwritten by scripts/publish_release.sh — this is the stable download link, not a changelog.\",\"prerelease\":false}")
  RELEASE_ID=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))")
fi

if [[ -z "$RELEASE_ID" ]]; then
  echo "error: could not create/find the GitHub release. Response was:" >&2
  echo "$RELEASE_JSON" >&2
  exit 1
fi

EXISTING_ASSET_ID=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for a in d.get('assets', []):
    if a['name'] == '$ASSET_NAME':
        print(a['id'])
        break
")

if [[ -n "$EXISTING_ASSET_ID" ]]; then
  echo "Replacing existing $ASSET_NAME asset..."
  curl -s -H "$AUTH_HEADER" -X DELETE "$GH_API/releases/assets/$EXISTING_ASSET_ID" > /dev/null
fi

echo "Uploading $ASSET_NAME ($(du -h "$APK_PATH" | cut -f1))..."
UPLOAD_URL="https://uploads.github.com/repos/$GITHUB_REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME"
curl -s -H "$AUTH_HEADER" -H "Content-Type: application/vnd.android.package-archive" \
  -X POST "$UPLOAD_URL" --data-binary "@$APK_PATH" > /dev/null

APK_URL="https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$ASSET_NAME"

mkdir -p release
cat > release/version.json <<EOF
{
  "latestVersionCode": $VERSION_CODE,
  "latestVersionName": "$VERSION_NAME",
  "apkUrl": "$APK_URL",
  "forceUpdate": $FORCE,
  "changelog": "$CHANGELOG"
}
EOF

firebase deploy --only hosting --project flow-sports-2026

echo "Published. Live at:"
echo "  $APK_URL"
echo "  https://flow-sports-2026.web.app/version.json"
