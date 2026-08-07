# CFX Versions

Version index for CFX server runtimes (**Legacy** + **Enhanced**).
Metadata and download URLs only — no binaries in this repository.

## Layout

```text
versions/
  index.json
  legacy/{win32,linux}.json
  enhanced/{win32,linux}.json
```

Each channel file: `latest`, `stable`, `builds.{id}.{url,seenAt}`.

Legacy builds are **master-only** (`…/build_*/master/…`). Feature branches are ignored.

## Usage

```bash
jq -r '.builds[.latest].url' versions/legacy/win32.json
```

Then download from that Cfx CDN URL.

## CI

| Workflow | |
| --- | --- |
| `sync-versions` | Daily — discover latest builds |
| `set-stable` | Manual — pin `stable` to a known build |

## License

Public domain — [Unlicense](LICENSE).
