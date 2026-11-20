; Vixeo installer for Windows (Inno Setup 6), built by the CI (.github/workflows/build.yml):
;   iscc /DAppVersion=1.2.0 /DBuildNumber=123 /DSourceDir=... /DOutputDir=... vixeo.iss
; Installed for the current user only (no administrator rights): the in-app update runs it
; again with /SILENT, and Vixeo starts again at the end (docs/windows-release.md).

#define AppName "Vixeo"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildNumber
  #define BuildNumber "0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\release"
#endif

[Setup]
; Never change the AppId: Windows recognises the installed app by it (updates, uninstall).
AppId={{8C1E0F2A-5B7D-4E2B-9A61-3F2D7C4B9E10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Vixeo
AppPublisherURL=https://www.vixeo.app
AppSupportURL=https://www.vixeo.app
VersionInfoVersion={#AppVersion}.{#BuildNumber}
DefaultDirName={localappdata}\Programs\Vixeo
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=vixeo-setup-{#BuildNumber}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\vixeo.exe
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; An update closes the running Vixeo (the app also quits by itself before it starts the installer).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Files of the previous version that the new one no longer has.
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\vixeo.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\vixeo.exe"; Tasks: desktopicon

[Run]
; Also after a silent update (no skipifsilent): Vixeo starts again by itself.
Filename: "{app}\vixeo.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall
