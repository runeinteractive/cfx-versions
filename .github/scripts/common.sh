#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }

channel_file() {
  echo "versions/$1/$2.json"
}

git_bot() {
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
}
