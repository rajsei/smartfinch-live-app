#define MyAppName "Smartfinch"
#define MyAppPublisher "Smartfinch"
#define MyAppExeName "smartfinch.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef MySourceDir
  #define MySourceDir "build\\windows\\x64\\runner\\Release"
#endif

#ifndef MyOutputDir
  #define MyOutputDir "build\\windows\\x64\\runner"
#endif

#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "Smartfinch_v" + MyAppVersion + "_windows_x64_setup"
#endif

[Setup]
AppId={{9B4D67AB-8EAA-F69D-7D47-91EB47C43439}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/rajsei/smartfinch-live-app
AppSupportURL=https://github.com/rajsei/smartfinch-live-app/issues
AppUpdatesURL=https://github.com/rajsei/smartfinch-live-app/releases
DefaultDirName={autopf}\Smartfinch
DefaultGroupName=Smartfinch
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma
SolidCompression=yes
WizardStyle=modern
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Smartfinch"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall Smartfinch"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Smartfinch"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Smartfinch"; Flags: nowait postinstall skipifsilent
