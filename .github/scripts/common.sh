#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }

channel_file() {
  echo "versions/$1/$2.json"
}

# Legacy FXServer: only …/master/… (never feature/*).
is_master_url() {
  [[ "${1:-}" == *"/master/"* ]]
}

legacy_artifact_root() {
  case "$1" in
    win32) echo "build_server_windows" ;;
    linux) echo "build_proot_linux" ;;
    *) echo "unknown platform: $1" >&2; return 1 ;;
  esac
}

legacy_artifact_file() {
  case "$1" in
    win32) echo "server.zip" ;;
    linux) echo "fx.tar.xz" ;;
    *) echo "unknown platform: $1" >&2; return 1 ;;
  esac
}

legacy_master_url() {
  local platform="$1" folder="$2"
  printf 'https://runtime.fivem.net/artifacts/fivem/%s/master/%s/%s\n' \
    "$(legacy_artifact_root "$platform")" \
    "$folder" \
    "$(legacy_artifact_file "$platform")"
}

# Active build folder from Cfx master listing HTML on stdin.
# Example: 34629-cb3c120b0a46c07ff1513cb0cbf8c4b4b38fb05b
legacy_master_folder_from_stdin() {
  local folder
  folder="$(sed -n 's/.*is-active[^>]*href="\.\/\([0-9][0-9]*-[a-f0-9]*\)\/.*/\1/p' | head -1)"
  if [[ -z "$folder" ]]; then
    folder="$(grep -oE 'href="\./[0-9]+-[a-f0-9]+/' | grep -oE '[0-9]+-[a-f0-9]+' | sort -t- -k1,1n | tail -1)"
  fi
  [[ -n "$folder" ]] || return 1
  printf '%s\n' "$folder"
}

# Rewrite versions/index.json from channel files. Arg: ISO-8601 UTC timestamp.
write_index() {
  local updatedAt="$1"
  local tmp
  tmp="$(mktemp)"
  jq -n \
    --arg updatedAt "$updatedAt" \
    --argjson lw "$(jq '{latest,stable}' versions/legacy/win32.json)" \
    --argjson ll "$(jq '{latest,stable}' versions/legacy/linux.json)" \
    --argjson ew "$(jq '{latest,stable}' versions/enhanced/win32.json)" \
    --argjson el "$(jq '{latest,stable}' versions/enhanced/linux.json)" \
    '{
      updatedAt: $updatedAt,
      channels: {
        "legacy/win32": ($lw + {path: "versions/legacy/win32.json"}),
        "legacy/linux": ($ll + {path: "versions/legacy/linux.json"}),
        "enhanced/win32": ($ew + {path: "versions/enhanced/win32.json"}),
        "enhanced/linux": ($el + {path: "versions/enhanced/linux.json"})
      }
    }' >"$tmp"
  mv "$tmp" versions/index.json
}
