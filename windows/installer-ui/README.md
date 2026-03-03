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
- Formular fuer Basisdaten, Datenbank, SMTP, optionale Felder und PHP-Runtime-Modus
- Validierung ueber `WizardState`
- Start von `windows/scripts/install.ps1` inklusive JSON-Konfigurationsdatei und Live-Log

## Architekturgrenze

Die UI soll keine Host-Installation direkt selbst ausfuehren.

- Die UI sammelt und validiert Daten.
- Die UI startet Skripte und zeigt deren Status an.
- Systemeingriffe wie PHP-, Nginx- oder MariaDB-Installation gehoeren in `windows/scripts`.
