# CFX Versions

Version index for CFX server runtimes (**Legacy** + **Enhanced**).
Metadata and download URLs only — no binaries in this repository.

## Layout

```text
versions/
  policy.json              # retention floors (minBuild)
  index.json               # derived channel pins
  legacy/{win32,linux}.json
  enhanced/{win32,linux}.json
```

Each channel file (`schemaVersion: 1`): `latest`, `stable`, `builds.{id}.{url,seenAt}`.

Legacy builds are **master-only** (`…/build_*/master/…`). Feature branches are ignored.

Builds below `versions/policy.json` retention floors are pruned on sync (pins `latest`/`stable` are always kept).

## Usage

```bash
jq -r '.builds[.latest].url' versions/legacy/win32.json
jq -r '.builds[.stable].url' versions/legacy/win32.json
```

Then download from that Cfx CDN URL.

## CI

| Workflow | |
| --- | --- |
| `sync-versions` | Daily — discover, prune retention, validate |
| `set-stable` | Manual — pin `stable` to a known build |
| `validate` | PR/push — catalog invariants |

## License

Public domain — [Unlicense](LICENSE).
