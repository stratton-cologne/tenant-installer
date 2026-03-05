# Tenant Installer

Neustart des Windows Tenant Installers auf Basis der aktuellen Anforderungen in [requirements.md](c:\Users\simon\Documents\tenant-installer\requirements.md).

## Ziel

Der Installer soll unter Windows:

- die neuesten Releases von `tenant-backend` und `tenant-frontend` automatisiert beziehen
- einen Wizard fuer Installationsdaten bereitstellen
- PHP 8.2 und Nginx pruefen und bei Bedarf vorbereiten
- optional MariaDB lokal installieren
- das Frontend in den `public`-Ordner des Backends deployen

## Geplantes Grundgeruest

```text
tenant-installer/
  requirements.md
  README.md
  docs/
    architecture.md
    roadmap.md
  windows/
    README.md
    bootstrap/
      README.md
    installer-ui/
      README.md
    scripts/
      README.md
```

## Naechste Umsetzungsstufen

1. Remote-Datenbank-Testlauf gegen reale Zielumgebung validieren
2. Fehlerdialoge und Statusmeldungen im Wizard weiter schaerfen
3. Optionale Packaging-Strecke (Wrapper/Signierung) nur bei Bedarf ergaenzen
