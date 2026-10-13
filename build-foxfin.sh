#!/usr/bin/env bash
# Foxfin release build. API keys come from foxfin-keys.json (git-ignored,
# template: foxfin-keys.example.json). Missing keys hide the integrations.
set -euo pipefail
cd "$(dirname "$0")"
ARGS=()
[ -f foxfin-keys.json ] && ARGS+=(--dart-define-from-file=foxfin-keys.json)
flutter build apk --release --flavor mobile "${ARGS[@]}"
