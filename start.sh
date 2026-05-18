#!/usr/bin/env bash
set -e
[ -d node_modules ] || npm install --no-audit --no-fund
node server/seed.js > /dev/null
node server/server.js
