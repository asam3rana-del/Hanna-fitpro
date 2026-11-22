; Hanna Fitness — Windows installer (Inno Setup 6).
; CI chalata hai:  ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutDir=<output> windows_assets\installer.iss
;
; - Admin ki zaroorat nahi: user ke apne folder (%LOCALAPPDATA%\Programs\Hanna Fitness) mein install hota hai.
; - Visual C++ runtime DLLs Release folder mein pehle se hain (build.yml), is liye alag install nahi chahiye.
; - Data (DB, settings) %APPDATA%\Hanna Solutions\Hanna Fitness mein hai — uninstall / update par NAHI mitta.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutDir
  #define OutDir "..\installer_out"
#endif

#define AppName "Hanna Fitness"
#define AppExe "hanna_fitness.exe"

[Setup]
; AppId kabhi na badlein — isi se Windows purani install pehchaan kar update karta hai.
AppId={{B7E41C92-3F5A-4D8B-A6C1-9E2F70D4C853}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Hanna Solutions
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutDir}
OutputBaseFilename=HannaFitness-Setup-{#AppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Chalti app band karwa kar update kare (DB file lock na rahe).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop par shortcut banayein"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "vc_redist.x64.exe,PEHLE_PARHEIN.txt"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{#AppName} Uninstall"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Hanna Fitness abhi kholein"; Flags: nowait postinstall skipifsilent
