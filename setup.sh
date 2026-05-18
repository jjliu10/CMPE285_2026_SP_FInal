#!/usr/bin/env bash
set -e
npm install --no-audit --no-fund

# Only rebuild the native binding if it can't actually load on the current
# OS/arch (i.e. you switched between Windows and WSL on the same checkout).
# Note: requiring better-sqlite3 alone doesn't dlopen the .node binary —
# we have to instantiate a Database to surface a platform mismatch.
if ! node -e "new (require('better-sqlite3'))(':memory:').close()" >/dev/null 2>&1; then
  PLATFORM=$(node -p "process.platform + '-' + process.arch")
  echo "Rebuilding better-sqlite3 for ${PLATFORM}..."
  npm rebuild better-sqlite3 --no-audit --no-fund >/dev/null
fi

node server/seed.js
echo "Setup complete. Run ./start.sh to launch."
