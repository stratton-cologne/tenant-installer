# Full Test Run

Diese Anleitung beschreibt einen vollständigen Testlauf auf einem isolierten Testsystem fuer den aktuellen `v1`-Stand.

## Ziel

Der Ablauf deckt den gesamten Pfad ab:

- Testartefakte bereitstellen
- Installer im Dry-Run pruefen
- Installer produktiv auf Testsystem ausfuehren
- Runtime separat aktivieren
- Beispiel-Modul installieren, umschalten und deinstallieren
- Repair und Uninstall pruefen

## Voraussetzungen

- Isoliertes Ubuntu- oder Windows-Testsystem
- Administrator- oder Root-Rechte
- PHP 8.2, Composer, `jq` und weitere im Preflight geforderte Tools
- vorbereitete Backend- und Frontend-Artefakte passend zu den Manifesten
- Beispiel-Modul-ZIP:
  [`example-module-1.0.0.zip`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/artifacts/modules/example-module-1.0.0.zip)

## 1. Artefakte vorbereiten

### Lokaler Modus

- Backend- und Frontend-ZIPs unter `tenant-installer/artifacts`
- Modul-ZIP unter `tenant-installer/artifacts/modules`

### Remote-Modus

- Release-Assets gemäss:
  [`release-convention.md`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/docs/release-convention.md)
- optional Beispiel-Konfiguration:
  [`release-sources.example.json`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/shared/manifests/release-sources.example.json)

## 2. Dry Run durchfuehren

Siehe:

- [`end-to-end-dry-run.md`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/docs/end-to-end-dry-run.md)

Wenn der Dry-Run plausibel ist, den echten Testlauf starten.

## 3. Installer ausfuehren

### Ubuntu

```bash
./tenant-installer/ubuntu/scripts/install.sh
```

Nach erfolgreichem Lauf pruefen:

- `APP_ROOT/current`
- `APP_ROOT/public`
- `APP_ROOT/runtime`
- `APP_ROOT/installer/state/install-state.enc.json`
- `APP_ROOT/installer/state/install.success`
- `APP_ROOT/installer/logs/install.log`

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\windows\scripts\install.ps1
```

Nach erfolgreichem Lauf pruefen:

- `AppRoot\current`
- `AppRoot\public`
- `AppRoot\runtime`
- `AppRoot\installer\state\install-state.enc.json`
- `AppRoot\installer\state\install.success`
- `AppRoot\installer\logs\install.log`

## 4. Runtime aktivieren

### Ubuntu

```bash
./tenant-installer/ubuntu/scripts/activate-runtime.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  --apply
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\windows\scripts\activate-runtime.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -Apply
```

Pruefen:

- Runtime-Logdatei
- Runtime-Success-Marker
- erzeugte Zielkonfigurationen

## 5. Modul-Manager testen

### Install

Ubuntu:

```bash
./tenant-installer/module-manager/ubuntu/install-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  ./tenant-installer/artifacts/modules/example-module-1.0.0.zip
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\install-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleZip .\tenant-installer\artifacts\modules\example-module-1.0.0.zip
```

### Toggle

Ubuntu:

```bash
./tenant-installer/module-manager/ubuntu/toggle-module.sh \
  /var/www/tenant-platform \
  example-module \
  disable
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\toggle-module.ps1 `
  -AppRoot C:\TenantPlatform `
  -ModuleSlug example-module `
  -Action disable
```

### Update

Ubuntu:

```bash
./tenant-installer/module-manager/ubuntu/update-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  ./tenant-installer/artifacts/modules/example-module-1.0.0.zip
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\update-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleZip .\tenant-installer\artifacts\modules\example-module-1.0.0.zip
```

### Uninstall

Ubuntu:

```bash
./tenant-installer/module-manager/ubuntu/uninstall-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  example-module
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\uninstall-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleSlug example-module
```

## 6. Repair testen

Erzeuge testweise einen kontrollierten Defekt, z. B.:

- `.env` entfernen
- Frontend-Datei aus `public/` loeschen

Dann:

### Ubuntu

```bash
./tenant-installer/ubuntu/scripts/repair.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort'
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\windows\scripts\repair.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort'
```

## 7. Uninstall testen

### Ubuntu

```bash
./tenant-installer/ubuntu/scripts/uninstall.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort'
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\windows\scripts\uninstall.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort'
```

## Erwarteter Abschluss

Nach dem vollständigen Testlauf sollte geprüft werden:

- alle Kernpfade wurden einmal erfolgreich ausgefuehrt
- Logdateien liegen fuer Install, Runtime, Repair, Uninstall und Modul-Install vor
- Success-Marker wurden passend geschrieben
- Module koennen installiert, umgeschaltet und wieder entfernt werden
- Installer-State bleibt waehrend des Testlaufs konsistent
