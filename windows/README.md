# Windows Installer

Dieser Bereich enthaelt den neuen Windows-Installationspfad.

## Scope

- Wizard fuer Erstinstallation
- Release-Bezug fuer Backend und Frontend
- PHP-8.2-Pruefung und optionale Bereitstellung
- Nginx-Einrichtung
- optionale lokale MariaDB-Installation

## Teilbereiche

- `bootstrap/`: optionale Build- und Setup-Vorbereitung
- `installer-ui/`: WPF-Wizard
- `scripts/`: PowerShell-Installationslogik

## Erste Implementierungsreihenfolge

1. Preflight
2. Wizard-Datenmodell
3. Release-Bezug
4. Installationsskript
5. optionaler Setup-Build nur bei Verteilungsbedarf
