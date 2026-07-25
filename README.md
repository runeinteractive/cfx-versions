# CFX Versions

Version index for CFX server runtimes (**Legacy FXServer** and **Enhanced Cfx Server**).

Metadata and download URLs only — **no binaries** are stored in this repository.

## Layout

```text
versions/
  index.json              # summary of all channels
  legacy/win32.json
  legacy/linux.json
  enhanced/win32.json
  enhanced/linux.json
```

Each channel file:

```json
{
  "product": "legacy",
  "platform": "win32",
  "latest": "32561",
  "stable": "25770",
  "builds": {
    "32561": {
      "url": "https://runtime.fivem.net/artifacts/.../server.zip",
      "seenAt": "2026-07-25T00:00:00Z"
    }
  }
}
```

## Usage

```bash
# Latest Enhanced Windows URL
jq -r '.builds[.latest].url' versions/enhanced/win32.json

# Stable Legacy Linux URL (after set-stable)
jq -r '.builds[.stable].url' versions/legacy/linux.json

# From raw.githubusercontent.com
curl -fsSL https://raw.githubusercontent.com/runeinteractive/cfx-versions/main/versions/enhanced/win32.json \
  | jq -r '.builds[.latest].url'
```

Then download from that URL (Cfx CDN) — not from this repo.

## CI

| Workflow | |
| --- | --- |
| `sync-versions` | Daily — discover latest builds, append to catalog |
| `set-stable` | Manual — set `stable` for a channel |

Legacy source: [changelog API](https://changelogs-live.fivem.net/api/changelog/versions/).  
Enhanced source: [Server Download](https://docs.fivem.net/docs/server-download/?platform=enhanced) (opaque CDN URLs).

## License

Unlicense — see [LICENSE](LICENSE).
