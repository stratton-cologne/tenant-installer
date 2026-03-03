# Release Convention

Diese Konvention beschreibt, wie vorbereitete Release-Artefakte fuer den Tenant-Installer strukturiert sein sollen.

## Ziel

Die Installer sollen Artefakte entweder lokal aus `tenant-installer/artifacts` oder remote aus einer stabilen Release-Quelle laden koennen. Die bevorzugte Remote-Konvention ist `GitHub Releases`.

## Manifest-Vertrag

Jedes Release-Artefakt benoetigt ein Manifest gemaess:

- [`release-manifest.schema.json`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/shared/manifests/release-manifest.schema.json)

Wesentliche Felder:

- `component`
- `version`
- `release_channel`
- `artifact.file_name`
- `artifact.sha256`

## GitHub-Release-Konvention

Empfohlene Struktur:

- Repository: `owner/repo`
- Tag: `v<version>` oder ein anderer konsistenter Praefix-Tag
- Asset-Datei: exakt wie `artifact.file_name` im Manifest

Beispiel:

- Manifest-Version: `1.0.0`
- Tag: `v1.0.0`
- Datei: `tenant-backend-1.0.0.zip`

Erwartete Download-URL:

```text
https://github.com/owner/repo/releases/download/v1.0.0/tenant-backend-1.0.0.zip
```

## Konkretes v1-Layout fuer Tenant-Komponenten

Empfohlene konkrete Repositories:

- `stratton-cologne/tenant-backend-releases`
- `stratton-cologne/tenant-frontend-releases`

Empfohlene Tags:

- Backend: `v<version>`
- Frontend: `v<version>`

Empfohlene Artefakte:

- Backend: `tenant-backend-<version>.zip`
- Frontend: `tenant-frontend-<version>.zip`

Beispiele:

```text
https://github.com/stratton-cologne/tenant-backend-releases/releases/download/v1.0.0/tenant-backend-1.0.0.zip
https://github.com/stratton-cologne/tenant-frontend-releases/releases/download/v1.0.0/tenant-frontend-1.0.0.zip
```

Fuer die Installer bedeutet das:

- Ubuntu:
  `ASSET_SOURCE=remote`
  `ASSET_BASE_URL=https://github.com/stratton-cologne/tenant-backend-releases/releases/download/v1.0.0`
  oder analog fuer Frontend, falls Komponenten getrennt bezogen werden
- Windows:
  `-AssetBaseUrl https://github.com/stratton-cologne/tenant-backend-releases/releases/download/v1.0.0`

Wenn Backend und Frontend in getrennten Repositories liegen, sollte mittelfristig pro Komponente eine eigene Asset-Basis konfigurierbar werden. Fuer den aktuellen Stand ist der Mechanismus bereits vorbereitet, aber noch auf eine gemeinsame Basis pro Lauf ausgelegt.

## URL-Hilfsskript

Das folgende Skript baut diese URL direkt aus dem Manifest:

```bash
./tenant-installer/tools/release/build-github-release-url.sh \
  tenant-installer/shared/manifests/example.tenant-backend.release.json \
  owner/repo \
  v
```

## Integration in die Installer

### Ubuntu

- `ASSET_SOURCE=remote`
- `ASSET_BASE_URL` kann auf ein generisches Asset-Verzeichnis zeigen
- Fuer GitHub kann `ASSET_BASE_URL` aus der erzeugten URL abgeleitet werden oder direkt auf `.../releases/download/<tag>` gesetzt werden

### Windows

- `-AssetBaseUrl` erwartet ebenfalls eine Basis-URL, die direkt auf das Verzeichnis mit den Release-Dateien zeigt

## Empfehlung

Fuer `v1` sollte pro Komponente ein eigenes Release-Repository oder ein klar strukturiertes gemeinsames Release-Repository verwendet werden, damit `tenant-backend`, `tenant-frontend` und spaeter Installer-Artefakte sauber versioniert und unabhaengig auslieferbar bleiben.
