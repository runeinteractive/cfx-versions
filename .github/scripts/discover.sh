#!/usr/bin/env bash
# discover.sh <legacy|enhanced> <win32|linux>
# prints: VERSION<TAB>URL
set -euo pipefail
source "$(dirname "$0")/common.sh"
need curl
need jq

product="${1:?}"
platform="${2:?}"

case "$product:$platform" in
  legacy:win32|legacy:linux)
    data="$(curl -fsSL "https://changelogs-live.fivem.net/api/changelog/versions/${platform}/server")"
    version="$(echo "$data" | jq -r '.latest')"
    url="$(echo "$data" | jq -r '.latest_download')"
    ;;
  enhanced:win32|enhanced:linux)
    [[ "$platform" == win32 ]] && os=windows || os=linux
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "https://docs.fivem.net/docs/server-download/" -o "$tmp/page.html"
    # Enhanced CDN uses opaque UUIDs — scrape docs payload.
    awk 'BEGIN{RS="</script>"} /id="__NEXT_DATA__"/{sub(/^.*<script[^>]*>/,""); print; exit}' \
      "$tmp/page.html" >"$tmp/next.json"
    subtitle="$(jq -r --arg os "$os" '.props.pageProps.enhanced[$os][0].subtitle' "$tmp/next.json")"
    url="$(jq -r --arg os "$os" '.props.pageProps.enhanced[$os][0].downloadURL' "$tmp/next.json")"
    version="$(echo "$subtitle" | tr -cd '0-9')"
    ;;
  *)
    echo "usage: $0 <legacy|enhanced> <win32|linux>" >&2
    exit 1
    ;;
esac

[[ -n "$version" && "$version" != null && -n "$url" && "$url" != null ]] || {
  echo "discover failed: $product/$platform" >&2
  exit 1
}

printf '%s\t%s\n' "$version" "$url"
