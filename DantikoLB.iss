; DantikoLB Installer - Inno Setup Script
; Save as: DantikoLB.iss
; Compile in Inno Setup (Unicode)

#define MyAppName "Dantiko's SWTOR Loadout Builder"
#define MyAppExeName "DantikoLB.exe"
#define MyAppPublisher "Dantiko"
#define MyAppVersion "1.0.2"

; Path to your Flutter Windows release output
#define BuildDir "build\windows\x64\runner\Release"

[Setup]
AppId={{19F67635-1F2B-4F77-9604-3F24BFDF9950}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=DantikoLB_Setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes

; If you have an .ico file, set these (recommended)
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

WizardImageFile=installer_assets\wizard_large.png
WizardSmallImageFile=installer_assets\wizard_small.png

; Optional polish
WizardImageBackColor=none
WizardStyle=modern

; Create a normal per-machine installer
PrivilegesRequired=admin

; Helps avoid "app already running" install issues
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Copy EVERYTHING from the Flutter Release folder, including subfolders (data, etc.)
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; (Optional) If you keep assets outside Release (usually not needed), add more Source lines.

[Icons]
; Start Menu shortcut
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
; Optional desktop shortcut
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
; Launch after install (optional)
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function GetUninstallString(): string;
var
  S: string;
begin
  S := '';
  if not RegQueryStringValue(HKLM,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1',
    'UninstallString', S) then
  begin
    RegQueryStringValue(HKLM,
      'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1',
      'UninstallString', S);
  end;
  Result := S;
end;

function TryCloseRunningApp(): Boolean;
var
  ResultCode: Integer;
  PsCmd: string;
begin
  Result := True;

  { Try graceful close first, then force if still running }
  PsCmd :=
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ' +
    '"$p = Get-Process ''DantikoLB'' -ErrorAction SilentlyContinue; ' +
    'if ($p) { ' +
    '  $p | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch {} }; ' +
    '  Start-Sleep -Seconds 3; ' +
    '  $p = Get-Process ''DantikoLB'' -ErrorAction SilentlyContinue; ' +
    '  if ($p) { $p | Stop-Process -Force } ' +
    '}"';

  if not Exec('powershell.exe', PsCmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    { Fallback if PowerShell launch fails: use taskkill directly }
    Exec(ExpandConstant('{cmd}'),
      '/C taskkill /IM "{#MyAppExeName}" /T /F >nul 2>&1',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function InitializeSetup(): Boolean;
var
  UninstallStr: string;
  ResultCode: Integer;
begin
  Result := True;

  UninstallStr := GetUninstallString();
  if UninstallStr <> '' then
  begin
    if MsgBox(
      'Dantiko''s SWTOR Loadout Builder is already installed.' + #13#10 +
      'Setup will update it to version {#MyAppVersion}.' + #13#10#13#10 +
      'If the app is running, setup will close it first.' + #13#10#13#10 +
      'Click OK to continue.',
      mbInformation, MB_OKCANCEL) <> IDOK then
    begin
      Result := False;
      Exit;
    end;

    TryCloseRunningApp();

    UninstallStr := RemoveQuotes(UninstallStr);

    Exec(UninstallStr, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;