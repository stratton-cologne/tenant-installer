# Release

Hilfsskripte fuer die Aufloesung und Verarbeitung von Release-Artefakten.

## Neueste stabile lokale Manifestdatei bestimmen

```bash
./tenant-installer/tools/release/select-latest-stable.sh \
  tenant-installer/shared/manifests \
  tenant-backend
```

Das Skript ist absichtlich lokal gehalten und dient als erste technische Basis. Der spaetere Git- oder Asset-Download kann darauf aufsetzen.

## Release-Asset per Basis-URL laden

```bash
./tenant-installer/tools/release/fetch-release-asset.sh \
  tenant-installer/shared/manifests/example.tenant-backend.release.json \
  https://releases.example.invalid/tenant \
  /tmp/tenant-cache
```

Das Skript laedt `artifact.file_name` relativ zur angegebenen Basis-URL und prueft anschliessend den `sha256` aus dem Manifest.

## GitHub-Release-URL aus Manifest ableiten

```bash
./tenant-installer/tools/release/build-github-release-url.sh \
  tenant-installer/shared/manifests/example.tenant-backend.release.json \
  owner/repo \
  v
```

Das Skript baut eine GitHub-Release-URL im Format:

```text
https://github.com/owner/repo/releases/download/v<version>/<artifact.file_name>
```
