# Windows Installer

Dieser Bereich enthaelt den nativen Windows-Installer fuer `v1`.

Zielbild:

- Signiertes `EXE` mit Assistent
- Mitgeliefertes `nginx`
- Eigener Service-Wrapper fuer Queue-Worker und Scheduler
- Preflight-, Install-, Update-, Repair- und Uninstall-Ablauf

Aktueller Stand:

- `scripts/preflight.ps1` prueft Administratorrechte, Windows-Version, PHP 8.2, benoetigte Tools, Ports und zentrale PHP-Extensions
- `scripts/install.ps1` deckt jetzt Eingaben, Manifest-Auswahl, lokales Artefakt-Staging, Entpacken, Basis-Deploy nach `current`, Runtime-Dateien und verschluesselten Installer-State ab
- `scripts/activate-runtime.ps1`, `scripts/repair.ps1` und `scripts/uninstall.ps1` nutzen den Windows-State fuer Betrieb und Wartung
- `windows/nginx` und `windows/services` enthalten jetzt konkrete Basisartefakte fuer mitgeliefertes `nginx` und den Windows-Service-Wrapper
- `installer-ui` enthaelt jetzt einen echten WPF-Wizard, der `preflight.ps1` und `install.ps1` bereits mit Live-Ausgabe, phasenbasiertem Fortschritt und Ergebnisbereich ansteuern kann
- `bootstrap/publish-installer-ui.ps1` bereitet das Packaging als verteilbares Windows-EXE vor, optional inkl. Signierung
- `bootstrap/build-setup-wrapper.ps1` rendert und kompiliert optional den Inno-Setup-Wrapper fuer ein echtes Setup-EXE
