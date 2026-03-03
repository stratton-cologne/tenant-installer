# Architektur

## Systemaufteilung

Das Repository wird in vier Hauptbereiche getrennt:

- Gemeinsame Definitionen und Vorlagen
- Windows-Installer
- Ubuntu-Installer
- Modul-Manager

Die Plattformpfade nutzen gemeinsame Manifeste, Templates und Validierungslogik, bleiben aber in der Ausfuehrung nativ.

## Komponentenmodell

### Shared

`shared/` enthaelt die wiederverwendbaren Bestandteile:

- Release-Metafile-Schema
- Konfigurationsschemas
- Vorlagen fuer `Nginx`, App-Config und Service-Definitionen
- Logging-Formate
- Validierungsregeln fuer Eingaben

### Windows

`windows/` enthaelt:

- Bootstrap-Logik fuer Voraussetzungen
- Assistentenlogik fuer den interaktiven Ablauf
- Auslieferung und Konfiguration von `Nginx`
- Service-Wrapper fuer Queue und Scheduler
- Skripte fuer Install, Update, Repair, Uninstall und Check

### Ubuntu

`ubuntu/` enthaelt:

- Interaktive Shell-Skripte fuer Install, Update, Repair, Uninstall und Check
- `Nginx`-Konfiguration
- `systemd`- und `Supervisor`-Definitionen
- `Let's Encrypt`-Einrichtung
- Hilfsskripte fuer Paketpruefung, Proxy und Ports

### Modul-Manager

`module-manager/` enthaelt:

- Gemeinsame Paketlogik fuer lokale Moduldateien
- Plattformnahe Shells oder Launcher fuer Windows und Ubuntu
- Entpack-, Aktivierungs- und Deaktivierungslogik
- Nachlauf fuer Migrationen, Cache-Neuaufbau und technische Synchronisation

## Installationsfluss

### 1. Preflight

Vor jeder schreibenden Aktion:

- Betriebssystem und Version pruefen
- Administratorrechte pruefen
- Netzwerk und Proxy pruefen
- Domain und DNS pruefen
- Ports `80` und `443` pruefen
- Vorhandensein von `PHP 8.2`, benoetigten Extensions, `Composer`, DB-Client pruefen

Im Pruefmodus endet der Lauf nach der Ausgabe des Statusberichts.

### 2. Eingabefluss

Der Installer erfasst:

- App-Pfad
- Domain
- Admin-Zugang
- Datenbankdaten
- Optionale SMTP-Daten
- Optionale Tenant- und Lizenzdaten
- SSL-Wunsch
- Entscheidung ueber lokale DB-Installation

Geheime Werte werden maskiert eingegeben und nie in Klartext-Logs geschrieben.

### 3. Release-Aufloesung

Fuer Backend und Frontend getrennt:

- Neueste stabile Release ermitteln
- Release-Metadaten lesen
- Kompatibilitaetshinweise auswerten
- Zielversion dem Benutzer anzeigen
- Ausfuehrung bestaetigen lassen

### 4. Deployment

#### Backend

- Release-ZIP entpacken
- `.env` schreiben
- Falls notwendig Verzeichnisse vorbereiten
- `composer install` ausfuehren
- Laravel-Initialisierung und Migrationen ausfuehren

#### Frontend

- Bestehende Artefakte sichern
- Neues `dist` deployen
- Alte Artefakte ersetzen

#### Runtime

- `Nginx` konfigurieren
- SSL optional konfigurieren
- Queue-Worker und Scheduler einrichten
- Health-Check ausfuehren

### 5. Persistenz

Der Installer speichert einen verschluesselten Zustandsdatensatz unter `installer/state`, um spaetere `Update`, `Repair` und `Uninstall`-Ablaufe reproduzierbar zu machen.

## Update-Strategie

Updates laufen immer als In-Place-Update mit:

- Snapshot des aktuellen Zustands
- Backup relevanter Dateien
- Sicherung vorhandener Frontend-Artefakte
- Durchfuehrung des Updates
- Rollback-Moeglichkeit bei Fehlern

Frontend und Backend koennen getrennte Versionen besitzen. Deshalb muss der Update-Ablauf beide Komponenten isoliert pruefen und deren Metadaten separat behandeln.

## Repair-Strategie

`Repair` behebt vor allem:

- Fehlende oder fehlerhafte Services
- Defekte `Nginx`-Konfiguration
- Fehlende Dateien aus dem letzten Installationsstand
- Inkonsistente Installer-Zustandsdaten

`Repair` darf bei Bedarf Artefakte erneut herunterladen.

## Uninstall-Strategie

`Uninstall` liest die verschluesselte Installer-Zustandsdatei und entfernt:

- Deployte Anwendungsdateien
- Webserver-Konfiguration
- Dienste und Scheduler
- Optional lokale technische Abhaengigkeiten, sofern vom Installer angelegt

Vor dem Entfernen von Datenbankinhalten oder persistenten Dateien wird der Benutzer explizit gefragt.

## Modul-Paketfluss

Der Modul-Manager verarbeitet lokale ZIP-Dateien mit definiertem Layout:

- `module.json`
- `backend/`
- `frontend/`

Ablauf:

- Paket auswaehlen
- Paketstruktur validieren
- Dateien entpacken
- Registrierung aktualisieren
- Notwendige Nacharbeiten ausfuehren
- Aktivierungszustand setzen

In `v1` gibt es keine harte Blockade auf Basis einer Kompatibilitaetspruefung. Der Modul-Manager sollte dennoch sichtbare Warnungen fuer moegliche Konflikte ausgeben.

## Logging-Modell

Jeder Ablauf erzeugt einen getrennten Logstrom:

- Install
- Update
- Module
- Repair

Logeintraege muessen:

- Zeitstempel enthalten
- Plattform und Aktion enthalten
- sensible Werte maskieren
- fuer Rotation oder Archivierung geeignet sein
