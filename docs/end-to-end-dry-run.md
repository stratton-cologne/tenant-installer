# End-to-End Dry Run

Diese Anleitung beschreibt einen gefuehrten Dry-Run fuer den aktuellen `v1`-Stand, ohne produktive Dateien zu deployen.

## Ziel

Der Ablauf prueft:

- Preflight
- interaktive Eingabelogik
- Release-Aufloesung
- Artefakt-Staging im Dry-Run
- Template-Rendering im Dry-Run
- State- und Success-Marker-Vorschau

## Vorbereitung

1. Stelle sicher, dass lokale Beispiel-Artefakte vorhanden sind:
   - `tenant-installer/artifacts/modules/example-module-1.0.0.zip`
2. Fuer einen realistischeren Installer-Dry-Run sollten passende Backend- und Frontend-ZIPs mit Manifest-kompatiblen Dateinamen unter `tenant-installer/artifacts` liegen.
3. Fuehre den Dry-Run auf einem Testsystem aus.

## Ubuntu Installer Dry Run

```bash
./tenant-installer/ubuntu/scripts/install.sh --dry-run
```

Erwartet:

- Interaktive Abfragen fuer App-Pfad, Domain, Admin, DB und SMTP
- Preflight-Pruefungen
- Ausgabe der vorgesehenen Render- und Staging-Pfade
- keine schreibenden Aenderungen am Zielsystem

## Windows Installer Dry Run

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\windows\scripts\install.ps1 -DryRun
```

Erwartet:

- Interaktive Abfragen analog zu Ubuntu
- Windows-Preflight
- Vorschau fuer Artefakt-Download oder lokales Staging
- keine schreibenden Aenderungen am Zielsystem

## Modul-Manager Dry Run

Ubuntu:

```bash
./tenant-installer/module-manager/ubuntu/install-module.sh \
  /pfad/zur/install-state.enc.json \
  'admin-passwort' \
  ./tenant-installer/artifacts/modules/example-module-1.0.0.zip \
  --dry-run
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tenant-installer\module-manager\windows\install-module.ps1 `
  -StateFile C:\TenantPlatform\installer\state\install-state.enc.json `
  -Passphrase 'admin-passwort' `
  -ModuleZip .\tenant-installer\artifacts\modules\example-module-1.0.0.zip `
  -DryRun
```

## Was im Dry Run nicht passiert

- keine echten Downloads
- keine echten Deployments nach `current` oder `public`
- keine Service-Registrierung
- keine Datenbankmigrationen
- keine persistenten Success-Marker

## Nächster Schritt nach dem Dry Run

Wenn der Dry-Run plausibel aussieht:

1. Testartefakte bereitstellen
2. auf isoliertem Testsystem ohne `--dry-run` ausfuehren
3. danach `activate-runtime` separat testen
