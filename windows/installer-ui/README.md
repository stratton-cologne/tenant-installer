# Windows Installer UI

Hier entsteht der neue WPF-Wizard.

## Wizard-Ziel

Der Wizard soll folgende Bereiche abfragen:

1. Basisdaten
2. Datenbank (lokal oder remote)
3. SMTP
4. Optionale Tenant-ID / Lizenzkeys
5. Zusammenfassung und Start der Installation

## Geplante Aufgaben

- Wizard-Layout erstellen
- Datenmodell definieren
- Validierung der Eingaben
- Anbindung an PowerShell-Skripte

## Aktueller Stand

- WPF-Projekt `TenantInstaller.Ui.csproj` vorhanden
- Formular fuer Basisdaten, SSL-Zertifikatspfade, Datenbank, SMTP, optionale Felder und PHP-Runtime-Modus
- Validierung ueber `WizardState`
- separater `Preflight ausfuehren`-Button fuer reine Systemchecks ohne Installlauf
- direkter TCP-Check fuer die Datenbankverbindung im Wizard (`DB-Verbindung testen`)
- Start von `windows/scripts/install.ps1` inklusive JSON-Konfigurationsdatei und Live-Log
- steuerbare Install-Optionen im Wizard: `Dry Run`, `Preflight ueberspringen`, `Prereleases zulassen`
- waehrend laufender Aktionen werden Start-Buttons gesperrt, um parallele Prozesse zu vermeiden
- GitHub-Token wird beim Start nur als Prozess-Umgebungsvariable (`GITHUB_TOKEN`) uebergeben, nicht als sichtbares CLI-Argument
- UI-Hinweis auf den verifizierten Installpfad inklusive Runtime-Setup und HTTP-Health-Check

## Architekturgrenze

Die UI soll keine Host-Installation direkt selbst ausfuehren.

- Die UI sammelt und validiert Daten.
- Die UI startet Skripte und zeigt deren Status an.
- Systemeingriffe wie PHP-, Nginx- oder MariaDB-Installation gehoeren in `windows/scripts`.
