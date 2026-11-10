#!/usr/bin/env bash
# Builds and serves the game on http://localhost:${PORT:-8000}/
set -euo pipefail
cd "$(dirname "$0")/.."
tools/build.sh >/dev/null
exec python3 -m http.server "${PORT:-8000}" -d build/web
