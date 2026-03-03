# Tenant Installer

Dieses Repository enthaelt den nativen Tenant-Installer fuer Windows-Server und Ubuntu-Server sowie einen separaten Modul-Manager.

## Ziel

Der Installer stellt eine interaktive Bereitstellung des Tenant-Systems bereit und deckt in `v1` folgende Bereiche ab:

- Erstinstallation des Basissystems
- Pruefmodus ohne schreibende Aenderungen
- Update mit Backup und Rollback-Snapshot
- Repair defekter oder unvollstaendiger Installationen
- Uninstall mit benutzergefuehrter Entscheidung ueber Datenbestand
- Separater Modul-Manager fuer Module als lokale Paketdateien

## Geplante Struktur

```text
tenant-installer/
  docs/
    requirements.md
    architecture.md
    roadmap.md
  shared/
    manifests/
    schemas/
    templates/
    logging/
  windows/
    bootstrap/
    installer-ui/
    nginx/
    services/
    scripts/
  ubuntu/
    scripts/
    nginx/
    systemd/
    supervisor/
    letsencrypt/
  module-manager/
    core/
    windows/
    ubuntu/
  tools/
    build/
    release/
    validation/
```

## Leitprinzipien fuer v1

- Gemeinsames Repository mit getrennten Installationspfaden fuer Windows und Ubuntu
- Native Plattformlogik statt gemeinsamer Cross-Platform-Runtime
- Bereitstellung ueber vorbereitete ZIP-Artefakte
- Immer neueste stabile semantische Release-Version ohne `alpha`, `beta`, `rc`
- Backend und Frontend koennen unterschiedliche Release-Staende haben
- Release-Metadaten muessen Version und Kompatibilitaet beschreiben

## Kern-Dokumente

- [Anforderungen](docs/requirements.md)
- [Architektur](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Modul Smoke Test](docs/module-smoke-test.md)
- [Full Test Run](docs/full-test-run.md)
- [End-to-End Dry Run](docs/end-to-end-dry-run.md)
- [Release Convention](docs/release-convention.md)

## Aktueller Implementierungsstand

- Ubuntu: `preflight.sh`, `install.sh`, `repair.sh`, `uninstall.sh`, `activate-runtime.sh`
- Release-Manifeste und lokale Artefakt-Staging-Skripte vorhanden
- Windows: `preflight.ps1`, `install.ps1`, `activate-runtime.ps1`, `repair.ps1`, `uninstall.ps1` plus angebundener WPF-Wizard unter `windows/installer-ui`
- Windows-Bootstrap: `windows/bootstrap/publish-installer-ui.ps1` fuer Publish/Bundle der WPF-GUI, `windows/bootstrap/build-setup-wrapper.ps1` fuer den Setup-Wrapper und `TenantInstaller.Setup.iss.tpl` als Inno-Vorlage
- Modul-Manager: Ubuntu- und Windows-Skripte fuer lokalen Modul-ZIP-Installationsfluss vorhanden

## Test-Fixtures

- `module-manager/fixtures/example-module` liefert ein minimales Beispiel-Modul fuer lokale Paket- und Installations-Tests
- `tools/build/build-example-module.sh` erzeugt daraus ein testbares Modul-ZIP unter `artifacts/modules`

## Laufstatus

- Install-, Modul-Install-, Activate-Runtime-, Repair- und Uninstall-Flows schreiben jetzt erste Logdateien und einfache Success-Marker unter dem jeweiligen `installer`-Pfad

## Release-Quellen

- Standardmaessig nutzen die Installer lokale Artefakte unter `tenant-installer/artifacts`
- Ubuntu kann alternativ ueber `ASSET_SOURCE=remote` und `ASSET_BASE_URL=...` auf externe Release-Assets vorbereitet werden
- Windows kann alternativ ueber den Parameter `-AssetBaseUrl` externe Release-Assets laden
