# Modul Smoke Test

Diese Anleitung beschreibt einen einfachen lokalen Smoke-Test fuer den Modul-Manager mit der vorhandenen Beispiel-Fixture.

## Voraussetzung

- Ein vorhandener Installer-State einer bestehenden Testinstallation
- Zugriff auf das erzeugte Beispiel-Modul-ZIP

Aktuelles Beispiel-ZIP:

- [`example-module-1.0.0.zip`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/artifacts/modules/example-module-1.0.0.zip)

## ZIP neu erzeugen

```bash
./tenant-installer/tools/build/build-example-module.sh
```

## Ubuntu Smoke Test

Installieren:

```bash
./tenant-installer/module-manager/ubuntu/install-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  ./tenant-installer/artifacts/modules/example-module-1.0.0.zip
```

Aktivieren oder deaktivieren:

```bash
./tenant-installer/module-manager/ubuntu/toggle-module.sh \
  /var/www/tenant-platform \
  example-module \
  disable
```

Deinstallieren:

```bash
./tenant-installer/module-manager/ubuntu/uninstall-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  example-module
```

## Windows Smoke Test

Installieren:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\install-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleZip .\tenant-installer\artifacts\modules\example-module-1.0.0.zip
```

Aktivieren oder deaktivieren:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\toggle-module.ps1 `
  -AppRoot C:\TenantPlatform `
  -ModuleSlug example-module `
  -Action disable
```

Deinstallieren:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\uninstall-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleSlug example-module
```

## Erwartete Ergebnisse

- Backend-Dateien liegen unter `current/modules/example-module`
- Frontend-Dateien liegen unter `public/modules/example-module`
- Modulstatus liegt unter `installer/modules/installed/example-module/module-state.json`
- Logdatei und Success-Marker werden unter `installer/modules/...` geschrieben
