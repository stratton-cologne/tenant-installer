# Modul-Manager

Der Modul-Manager verarbeitet lokale Modulpakete mit folgendem Mindestlayout:

- `module.json`
- `backend/`
- `frontend/`

Er unterstuetzt in `v1`:

- Installieren
- Aktualisieren
- Deinstallieren
- Aktivieren
- Deaktivieren

Aktueller Stand:

- `core/module-package.schema.json` beschreibt das erwartete `module.json`
- `ubuntu/install-module.sh` installiert ein lokales Modul-ZIP anhand des vorhandenen Installer-State
- `ubuntu/toggle-module.sh` schaltet Module ueber den lokalen Modulstatus auf enabled/disabled
- `ubuntu/update-module.sh` und `ubuntu/uninstall-module.sh` decken Update und Deinstallation des lokalen Modulstatus ab
- `windows/*.ps1` spiegeln denselben lokalen Modulfluss fuer Install, Toggle, Update und Uninstall
- `fixtures/example-module` liefert eine minimale Test-Fixture fuer lokale Paket-Tests
- `tools/build/build-example-module.sh` verpackt die Test-Fixture direkt als lokales Modul-ZIP
- `toggle`- und `update`-Skripte schreiben jetzt ebenfalls eigene Logdateien
