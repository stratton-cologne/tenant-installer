# Roadmap v1

## Arbeitspakete

### 1. Repository-Grundgeruest

- Zielordnerstruktur anlegen
- Gemeinsame Konventionen fuer Skripte, Konfigurationsdateien und Logs festlegen
- Schema fuer Release-Metafiles definieren
- Format fuer verschluesselte Installer-Zustandsdatei festlegen

### 2. Shared-Bausteine

- Vorlagen fuer `Nginx` erzeugen
- Vorlagen fuer Service-Definitionen erzeugen
- Eingabevalidierung beschreiben
- Logging-Format und Maskierungsregeln festlegen
- Release-Selektor fuer stabile semantische Versionen definieren

### 3. Ubuntu-Installer

- Preflight-Check fuer Ubuntu entwickeln
- Pruefmodus implementieren
- Interaktiven Installationsablauf implementieren
- Optionale Einrichtung von `MariaDB` implementieren
- `Nginx`-Provisionierung und `Let's Encrypt` integrieren
- `systemd`- und `Supervisor`-Definitionen fuer Queue und Scheduler integrieren
- Update-, Repair- und Uninstall-Ablauf implementieren

Aktueller Stand:

- Preflight vorhanden
- Install-Skelett mit Eingaben, Template-Rendering, lokalem Artefakt-Staging, Entpacken, Basis-Deploy und Laravel-Bootstrap vorhanden
- Repair und Uninstall als erste State-basierte Skripte vorhanden
- Runtime-Aktivierung als separater Schritt vorhanden

### 4. Windows-Installer

- Bootstrap fuer Voraussetzungen entwickeln
- Assistentenfluss fuer `EXE` definieren
- Pruefmodus implementieren
- Mitgeliefertes `Nginx` integrieren
- Service-Wrapper fuer Queue und Scheduler implementieren
- Optionale `MariaDB`-Einrichtung integrieren
- Update-, Repair- und Uninstall-Ablauf implementieren

### 5. Modul-Manager

- Paketvalidierung fuer `module.json`, `backend/`, `frontend/` implementieren
- Installieren und Aktualisieren implementieren
- Aktivieren und Deaktivieren implementieren
- Deinstallieren implementieren
- Nacharbeiten fuer Migrationen und technische Synchronisation integrieren
- Warnlogik fuer moegliche Kompatibilitaetskonflikte integrieren

### 6. Release- und Paketierungsprozess

- Build-Pipeline fuer Installer-Artefakte definieren
- Release-ZIP-Konvention fuer Backend und Frontend dokumentieren
- Signierungsprozess fuer Windows-`EXE` festlegen
- Verteilung ueber vorbereitete ZIP-Assets standardisieren

## Abhaengigkeiten

- Ohne Release-Metafile-Schema sind Install-, Update- und Modulprozesse nicht stabil umsetzbar.
- Ohne gemeinsames Logging- und State-Format steigt der Aufwand fuer `Repair` und `Uninstall`.
- Der Windows-Service-Wrapper ist ein kritischer Pfad und sollte frueh als Prototyp geklaert werden.

## Empfohlene Umsetzungsreihenfolge

1. Repository-Grundgeruest und Shared-Schemas
2. Ubuntu-Installer als erste lauffaehige Referenz
3. Release-Metafile- und State-Format finalisieren
4. Windows-Installer mit Service-Wrapper
5. Modul-Manager
6. Packaging, Signierung und Release-Pipeline

## Offene Punkte fuer die Umsetzung

- Welches konkrete UI-Framework fuer den Windows-Assistenten genutzt wird
- Wie der Windows-Service-Wrapper technisch gebaut wird
- Wie Release-Assets aus Git bezogen und authentifiziert werden
- Ob `Apache` unter Windows spaeter als Alternative aufgenommen wird
