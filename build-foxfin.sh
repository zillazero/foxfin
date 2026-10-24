#!/usr/bin/env bash
# Foxfin release build. API keys come from foxfin-keys.json (git-ignored,
# template: foxfin-keys.example.json). Missing keys hide the integrations.
# Usage: ./build-foxfin.sh [voll|split|klein]   (default: voll = universal APK)
set -euo pipefail
cd "$(dirname "$0")"
ARGS=()
[ -f foxfin-keys.json ] && ARGS+=(--dart-define-from-file=foxfin-keys.json)
case "${1:-voll}" in
  split) flutter build apk --release --flavor mobile --split-per-abi --target-platform android-arm,android-arm64 "${ARGS[@]}" ;;
  klein) flutter build apk --release --flavor mobile --split-per-abi --target-platform android-arm,android-arm64 \
           --dart-define=FOX_KLEIN=true --tree-shake-icons "${ARGS[@]}" ;;
  *)     flutter build apk --release --flavor mobile "${ARGS[@]}" ;;
esac
