# Windows Scripts

Hier entsteht die PowerShell-Installationslogik.

## Geplante Skripte

- `preflight.ps1`
- `install.ps1`
- `fetch-releases.ps1`
- optional spaeter weitere Wartungsskripte

## Verantwortlichkeiten

- Systempruefungen
- Release-Bezug
- PHP- / Nginx- / MariaDB-Vorbereitung
- Deployment des Backends
- Kopieren des Frontends in `public`
- Erzeugen der Laufzeitkonfiguration

## Warum Skripte hier sinnvoll sind

- Systemkommandos und Installationen sind unter PowerShell direkter und robuster umsetzbar als im UI-Code.
- Die Skripte koennen spaeter auch ohne Wizard getestet oder manuell ausgefuehrt werden.
- Der Wizard bleibt dadurch auf Benutzerfuehrung und Statusanzeige fokussiert.
