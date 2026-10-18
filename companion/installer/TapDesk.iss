; TapDesk desktop companion — Windows installer
;
; The point of this file is that a teacher should never have to install Python.
; The companion is a frozen executable (see TapDesk.spec) and this wraps it in
; something that behaves like any other Windows program.
;
; Two things here are more than boilerplate.
;
; The firewall rule. The companion listens on a TCP port on the local network,
; and Windows Firewall blocks that silently by default - the user gets a
; companion that shows a QR code which never works, with no error anywhere. So
; the rule is added at install time and removed at uninstall. Doing it here,
; rather than asking the user to, means it is correct on a machine where they
; have never opened the firewall settings.
;
; Run as admin. Not because the companion needs it, but because adding a
; firewall rule does.

#define AppName "TapDesk"
#define AppVersion "1.0.0"
#define AppPublisher "TapDesk"
#define AppExeName "TapDesk.exe"

[Setup]
AppId={{6E3C2A11-9B4D-4F27-9C5E-7B1D4A8E3F60}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\TapDesk
DefaultGroupName=TapDesk
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=TapDesk-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user by default so installing does not need admin rights; the firewall
; rule still does, so admin is requested below.
; Installs per-user by default so it works without admin, and elevates only
; when the user chooses to - which is what adds the firewall rule.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}
; No LicenseFile for now - there is no LICENSE in the repository to point at,
; and Inno Setup fails the build on a missing one. Better an absent licence
; page than a build that will not compile.

[Files]
; The freeze is one file, not a folder of DLLs (see TapDesk.spec), so this is
; a single entry and the installed program is one executable. It unpacks to a
; temp folder on first run, which is a second or two of delay on launch.
Source: "..\dist\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\TapDesk"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall TapDesk"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TapDesk"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Start TapDesk now"; Flags: nowait postinstall skipifsilent

[FirewallRules]
; Added and removed with the install, so a user who uninstalls is not left
; with a permanent hole in their firewall for a program that no longer exists.
Name: "tapdesk"; Description: "TapDesk companion - local network control"; DirName: "{app}"; Protocol: TCP; Port: 8765; Isolate: no

[Code]
var
  RunningAsAdmin: Boolean;
  Nl: String;

function Say(const Lines: array of string): String;
var
  I: Integer;
begin
  { Built by joining rather than with #13#10 scattered through the source: a
    line beginning with # is read by the preprocessor as a directive, which
    fails the build with "Unknown preprocessor directive" and no line number
    pointing anywhere useful. }
  Result := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    if I > 0 then Result := Result + Nl;
    Result := Result + Lines[I];
  end;
end;

function InitializeSetup(): Boolean;
var
  Answer: Integer;
begin
  Result := True;
  Nl := #13#10;
  RunningAsAdmin := IsAdminInstallMode;

  { The firewall rule needs admin rights. Refusing to install without them
    would be heavy-handed: the user may simply have declined the UAC prompt,
    and a warning they can act on afterwards is better than a program that
    refuses to exist. So the app installs either way, and says plainly what
    is missing if it did not get the rule. }
  if RunningAsAdmin or WizardSilent then
  begin
    Result := True;
    exit;
  end;

  Answer := MsgBox(
    Say([
      'TapDesk installs without administrator rights, but then it cannot add',
      'the firewall rule your phone needs to reach this computer.',
      '',
      'Install now and add the rule later, or cancel and run this installer',
      'as administrator?'
    ]), mbConfirmation, MB_YESNO);

  Result := Answer = IDYES;
end;
