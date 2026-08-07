#!/usr/bin/env bash
# discover.sh <legacy|enhanced> <win32|linux>
# prints: VERSION<TAB>URL
set -euo pipefail
source "$(dirname "$0")/common.sh"
need curl
need jq

product="${1:?}"
platform="${2:?}"

discover_legacy() {
  local platform="$1"
  local root listing folder version url data

  root="$(legacy_artifact_root "$platform")"
  listing="https://runtime.fivem.net/artifacts/fivem/${root}/master/"

  # Fast path: changelog latest when it already points at master.
  data="$(curl -fsSL "https://changelogs-live.fivem.net/api/changelog/versions/${platform}/server")"
  version="$(echo "$data" | jq -r '.latest // empty')"
  url="$(echo "$data" | jq -r '.latest_download // empty')"
  if [[ -n "$version" && -n "$url" ]] && is_master_url "$url"; then
    printf '%s\t%s\n' "$version" "$url"
    return 0
  fi

  # Fallback: active build on the master artifacts index.
  folder="$(curl -fsSL "$listing" | legacy_master_folder_from_stdin)" || {
    echo "discover failed: no master build on $listing" >&2
    return 1
  }
  version="${folder%%-*}"
  url="$(legacy_master_url "$platform" "$folder")"
  printf '%s\t%s\n' "$version" "$url"
}

discover_enhanced() {
  local platform="$1"
  local os tmp subtitle url version
  [[ "$platform" == win32 ]] && os=windows || os=linux

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "https://docs.fivem.net/docs/server-download/" -o "$tmp/page.html"
  # Enhanced CDN uses opaque UUIDs — scrape docs __NEXT_DATA__.
  awk 'BEGIN{RS="</script>"} /id="__NEXT_DATA__"/{sub(/^.*<script[^>]*>/,""); print; exit}' \
    "$tmp/page.html" >"$tmp/next.json"
  subtitle="$(jq -r --arg os "$os" '.props.pageProps.enhanced[$os][0].subtitle' "$tmp/next.json")"
  url="$(jq -r --arg os "$os" '.props.pageProps.enhanced[$os][0].downloadURL' "$tmp/next.json")"
  version="$(echo "$subtitle" | tr -cd '0-9')"

  [[ -n "$version" && -n "$url" && "$url" != null ]] || {
    echo "discover failed: enhanced/$platform" >&2
    return 1
  }
  printf '%s\t%s\n' "$version" "$url"
}

case "$product:$platform" in
  legacy:win32|legacy:linux) discover_legacy "$platform" ;;
  enhanced:win32|enhanced:linux) discover_enhanced "$platform" ;;
  *)
    echo "usage: $0 <legacy|enhanced> <win32|linux>" >&2
    exit 1
    ;;
esac
