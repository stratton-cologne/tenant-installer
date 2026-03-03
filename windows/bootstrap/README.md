# Windows Bootstrap

Dieses Verzeichnis enthaelt die Build- und Packaging-Bausteine fuer den Windows-Installer.

## Inhalt

- `publish-installer-ui.ps1`
  Erstellt aus dem WPF-Projekt ein verteilbares Windows-EXE-Bundle via `dotnet publish`.
- `build-setup-wrapper.ps1`
  Rendert aus der Inno-Setup-Vorlage eine echte `.iss`-Datei und kann sie optional direkt kompilieren.
- `TenantInstaller.Setup.iss.tpl`
  Vorlage fuer einen spaeteren Inno-Setup-Wrapper um das veroeffentlichte EXE-Bundle.

## Ziel fuer v1

1. `TenantInstaller.Ui.exe` als Single-File-Build erzeugen
2. optional per `signtool` signieren
3. spaeter daraus ein endgueltiges Setup-EXE mit Inno Setup oder vergleichbarem Tool bauen

## Beispiel

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\bootstrap\publish-installer-ui.ps1 -SelfContained -SingleFile
```

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\bootstrap\build-setup-wrapper.ps1 -AppVersion 0.1.0
```

Mit Inno Setup Compiler:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\bootstrap\build-setup-wrapper.ps1 -AppVersion 0.1.0 -Compile -InnoCompilerPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

## Hinweis

Das Publish-Skript fuehrt nur den Build- und Bundle-Schritt aus. Ein echtes signiertes Release benoetigt weiterhin:

- installierte .NET-SDK- und Windows-Targeting-Komponenten
- Zugriff auf NuGet beim Restore
- optional ein Codesigning-Zertifikat plus `signtool`
