; Inno Setup template for packaging the published WPF installer bundle.
; Replace the placeholders before building:
; __APP_VERSION__
; __PUBLISH_DIR__
; __OUTPUT_DIR__

[Setup]
AppId={{2D553403-2D46-4D39-9BB5-4D96B94D9B88}
AppName=Tenant Installer
AppVersion=__APP_VERSION__
AppPublisher=Stratton Cologne
DefaultDirName={autopf}\Tenant Installer
DefaultGroupName=Tenant Installer
OutputDir=__OUTPUT_DIR__
OutputBaseFilename=tenant-installer-setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Files]
Source: "__PUBLISH_DIR__\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Tenant Installer"; Filename: "{app}\TenantInstaller.Ui.exe"
Name: "{autodesktop}\Tenant Installer"; Filename: "{app}\TenantInstaller.Ui.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknuepfung erstellen"; GroupDescription: "Zusaetzliche Aufgaben:"

[Run]
Filename: "{app}\TenantInstaller.Ui.exe"; Description: "Tenant Installer starten"; Flags: nowait postinstall skipifsilent
