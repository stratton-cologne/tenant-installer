# Roadmap

## Phase 1: Grundgeruest

- Repository fuer den Windows-Neustart strukturieren
- Anforderungen in technische Architektur ueberfuehren
- Verantwortlichkeiten fuer Wizard, Skripte und Bootstrap trennen

## Phase 2: Wizard-Design

- Wizard-Schritte definieren
- Datenmodell fuer Eingaben anlegen
- Validierungsregeln festlegen

## Phase 3: Installations-Engine

- Preflight-Skript erstellen
- Release-Bezug fuer Backend und Frontend implementieren
- Deploy-Logik fuer Backend plus Frontend-in-`public` erstellen
- PHP 8.2 sicherstellen
- Nginx sicherstellen
- lokale MariaDB-Option vorbereiten

## Phase 4: Packaging

- WPF-App publizieren
- Setup-Wrapper erstellen
- spaeter optional Signierung ergaenzen

## Phase 5: Test und Härtung

- Testfaelle fuer lokale und remote Datenbank
- Fehlerbehandlung und Logging
- Review des Installationsflusses
