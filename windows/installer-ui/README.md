# Windows Installer UI

Dieses Verzeichnis enthaelt das erste GUI-Skelett fuer den Windows-Installer.

## Technologie

- `.NET`
- `WPF`
- Ziel: spaeter Packaging als signiertes `EXE`

## Ziel fuer v1

Die GUI sammelt Installationsdaten, zeigt den Ablauf als Wizard und delegiert die technische Ausfuehrung an die bestehenden PowerShell-Skripte in `windows/scripts`.

## Aktueller Stand

- Projektdatei fuer eine Windows-WPF-Anwendung
- Wizard-Grundlayout mit mehreren Schritten
- Modell fuer Installationsdaten
- Kommandoaufbau fuer `preflight.ps1` und `install.ps1`
- echte Startbuttons fuer Preflight und Install
- Live-Ausgabe fuer `stdout` und `stderr`
- phasenbasierter Fortschrittsbalken auf Basis der `install.ps1`-Statusmeldungen
- finaler Ergebnisbereich fuer Success- und Error-Zustaende
- temporaere JSON-Konfiguration fuer `install.ps1 -ConfigPath ...`

Die GUI ist jetzt an die bestehende PowerShell-Engine angebunden. Fuer den Produktivstand fehlen vor allem Signierung, Packaging als `EXE` und ein finaler Error-/Success-Flow.
