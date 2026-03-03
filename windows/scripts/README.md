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

## Aktueller Startpunkt

- `preflight.ps1` als erster lauffaehiger Preflight-Skeleton
- `fetch-releases.ps1` als erster Baustein fuer den Bezug der neuesten GitHub-Releases und deren Assets
- `install.ps1` als Orchestrierungs-Skript fuer Preflight, Release-Bezug, Entpacken, Frontend-Deployment nach `public`, `.env`-Erzeugung, PHP-8.2-Pruefung/Installation, Composer-Install, Laravel-Bootstrap, PHP-FastCGI (Scheduled Task oder optional NSSM), Nginx-Basis-Setup und optionale MariaDB-Installation samt Provisionierung

## Warum Skripte hier sinnvoll sind

- Systemkommandos und Installationen sind unter PowerShell direkter und robuster umsetzbar als im UI-Code.
- Die Skripte koennen spaeter auch ohne Wizard getestet oder manuell ausgefuehrt werden.
- Der Wizard bleibt dadurch auf Benutzerfuehrung und Statusanzeige fokussiert.
