# Architektur

## Zielbild

Der Windows Tenant Installer besteht aus vier Hauptbausteinen:

1. WPF-Wizard fuer die Datenerfassung und Orchestrierung
2. PowerShell-Skripte fuer Systempruefung, Installation und Konfiguration
3. Release-Bezugskomponente fuer Backend- und Frontend-Releases
4. Bootstrap-/Packaging-Schicht fuer ein verteilbares Setup

## Architekturentscheidung: Skripte vs. direkte Logik im Installer

Die eigentliche Systemlogik soll nicht direkt in der WPF-Oberflaeche implementiert werden.

### Was direkt in den Installer (WPF) gehoert

- Wizard-Schritte und Benutzerfuehrung
- Eingabevalidierung auf UI-Ebene
- Zusammenfassung der erfassten Daten
- Start, Abbruch und Beobachtung von Installationslaeufen
- Darstellung von Fortschritt, Logs und Fehlern

### Was in PowerShell-Skripte gehoert

- Systempruefungen (Preflight)
- Installation und Konfiguration von PHP 8.2
- Installation und Konfiguration von Nginx
- optionale Installation von MariaDB
- Release-Bezug und Deployment
- Schreiben von Konfigurationsdateien und Durchfuehren von Shell-Befehlen

### Warum diese Trennung sinnvoll ist

- Die UI bleibt schlank und auf Benutzerfuehrung fokussiert.
- Systemeingriffe sind in Skripten einfacher testbar und schrittweise erweiterbar.
- Dieselbe Ausfuehrungslogik kann spaeter auch ohne GUI genutzt werden.
- Fehler in Host-Konfiguration und Deployment lassen sich in Skripten gezielter behandeln.

## Erste technische Entscheidung fuer den Neustart

Der neue Installer soll daher:

1. Installationsdaten im WPF-Wizard erfassen
2. diese Daten an PowerShell-Skripte uebergeben
3. die eigentliche Host-Konfiguration ausschliesslich ueber Skripte ausfuehren

## Kernablaeufe

### 1. Preflight

- Pruefen, ob Windows kompatibel ist
- Pruefen, ob PHP 8.2 vorhanden ist
- Pruefen, ob Nginx vorhanden ist
- Pruefen, ob GitHub-Zugriff fuer Release-Bezug moeglich ist
- Pruefen, ob Port- und Dateisystemvoraussetzungen erfuellt sind

### 2. Wizard

Der Wizard erfasst:

- Basisdaten
- Datenbankdaten inklusive lokal/remote-Entscheidung
- optionale SMTP-Konfiguration
- optionale Tenant-ID / Lizenzkeys

### 3. Installation

- neuestes Backend-Release beziehen
- neuestes Frontend-Release beziehen
- Backend bereitstellen
- Frontend in `public` des Backends kopieren
- `.env` bzw. Laufzeitkonfiguration erzeugen
- Nginx einrichten
- PHP 8.2 sicherstellen
- optional MariaDB lokal installieren

### 4. Packaging

- WPF-App als auslieferbares Windows-Artefakt bauen
- Setup-Wrapper fuer Installationsverteilung erstellen

## Komponentenstruktur

### `windows/installer-ui`

- Wizard-Oberflaeche
- Schrittmodell
- Validierung von Benutzereingaben
- Start von PowerShell-Installationslaeufen
- keine direkte Implementierung von Systeminstallationen im UI-Code

### `windows/scripts`

- Preflight
- Install
- Release-Bezug
- PHP- / Nginx- / MariaDB-Setup
- technische Ausfuehrung aller mutierenden Host-Operationen

### `windows/bootstrap`

- Publish der UI
- Setup-Build

## Technische Leitlinien

- Windows zuerst, keine Cross-Platform-Abstraktion im ersten Schritt
- Klare Trennung zwischen UI und Ausfuehrungslogik
- Idempotente Skriptbausteine, soweit moeglich
- Fehler sollen im Wizard klar sichtbar werden
