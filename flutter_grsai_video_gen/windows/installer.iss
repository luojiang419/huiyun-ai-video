#define MyAppName "绘云AI 影视版"
#ifndef MyAppVersion
  #define MyAppVersion "V10.0"
#endif
#define MyAppPublisher "Leo.j"
#define MyAppExeName "flutter_grsai_image_gen.exe"
#define MyAppId "HuiYunAI.Video"
#define MyAppLegacyIdPrefix "HuiYunAI.Video"
#ifndef MyAppOutputBaseFilename
  #define MyAppOutputBaseFilename "影视版-安装包-" + MyAppVersion
#endif
#ifndef MyAppOutputDir
  #define MyAppOutputDir "..\..\dist\影视版\影视版-" + MyAppVersion
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyAppOutputDir}
OutputBaseFilename={#MyAppOutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UsePreviousAppDir=no
SetupLogging=yes
CloseApplications=no
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "data\Settings\config.json,data\Settings\system_prompt.txt"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\data\Settings\config.json"; DestDir: "{app}\data\Settings"; Flags: ignoreversion onlyifdoesntexist uninsneveruninstall
Source: "..\build\windows\x64\runner\Release\data\Settings\system_prompt.txt"; DestDir: "{app}\data\Settings"; Flags: ignoreversion onlyifdoesntexist uninsneveruninstall
Source: "..\build\windows\x64\runner\Release\data\Defaults\config.json"; DestDir: "{app}\data\Defaults"; Flags: ignoreversion uninsneveruninstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  UninstallRegPath = 'Software\Microsoft\Windows\CurrentVersion\Uninstall';

function StartsText(const Prefix, Value: String): Boolean;
begin
  Result := CompareText(Copy(Value, 1, Length(Prefix)), Prefix) = 0;
end;

function EndsText(const Suffix, Value: String): Boolean;
begin
  if Length(Value) < Length(Suffix) then
  begin
    Result := False;
    Exit;
  end;

  Result :=
    CompareText(
      Copy(Value, Length(Value) - Length(Suffix) + 1, Length(Suffix)),
      Suffix
    ) = 0;
end;

function NormalizeDir(const Value: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Trim(Value));
end;

function TryReadInstallDir(
  RootKey: Integer;
  const SubKeyName: String;
  var InstallDir: String
): Boolean;
var
  Value: String;
begin
  Result := False;
  InstallDir := '';

  if RegQueryStringValue(
    RootKey,
    UninstallRegPath + '\' + SubKeyName,
    'Inno Setup: App Path',
    Value
  ) then
  begin
    InstallDir := NormalizeDir(Value);
  end
  else if RegQueryStringValue(
    RootKey,
    UninstallRegPath + '\' + SubKeyName,
    'InstallLocation',
    Value
  ) then
  begin
    InstallDir := NormalizeDir(Value);
  end;

  if InstallDir = '' then
    Exit;

  Result :=
    DirExists(InstallDir) or
    FileExists(AddBackslash(InstallDir) + '{#MyAppExeName}');
end;

function ExtractLegacyVersionScore(const KeyName: String): Integer;
var
  Prefix: String;
  VersionText: String;
  I: Integer;
  PartValue: Integer;
  PartIndex: Integer;
  HasDigits: Boolean;
begin
  Prefix := '{#MyAppLegacyIdPrefix}.';
  VersionText := KeyName;
  if StartsText(Prefix, VersionText) then
    Delete(VersionText, 1, Length(Prefix));
  if EndsText('_is1', VersionText) then
    Delete(VersionText, Length(VersionText) - 3, 4);

  Result := 0;
  PartValue := 0;
  PartIndex := 0;
  HasDigits := False;

  for I := 1 to Length(VersionText) do
  begin
    if (VersionText[I] >= '0') and (VersionText[I] <= '9') then
    begin
      PartValue := (PartValue * 10) + (Ord(VersionText[I]) - Ord('0'));
      HasDigits := True;
    end
    else if HasDigits then
    begin
      if PartIndex = 0 then
        Result := Result + (PartValue * 10000)
      else if PartIndex = 1 then
        Result := Result + (PartValue * 100)
      else if PartIndex = 2 then
        Result := Result + PartValue;

      Inc(PartIndex);
      PartValue := 0;
      HasDigits := False;
      if PartIndex >= 3 then
        Break;
    end;
  end;

  if HasDigits then
  begin
    if PartIndex = 0 then
      Result := Result + (PartValue * 10000)
    else if PartIndex = 1 then
      Result := Result + (PartValue * 100)
    else if PartIndex = 2 then
      Result := Result + PartValue;
  end;
end;

function FindLegacyInstallDirInRoot(
  RootKey: Integer;
  var BestDir: String;
  var BestScore: Integer
): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
  CandidateDir: String;
  CandidateScore: Integer;
begin
  Result := False;

  if not RegGetSubkeyNames(RootKey, UninstallRegPath, Names) then
    Exit;

  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    if not StartsText('{#MyAppLegacyIdPrefix}.', Names[I]) then
      Continue;
    if not EndsText('_is1', Names[I]) then
      Continue;
    if not TryReadInstallDir(RootKey, Names[I], CandidateDir) then
      Continue;

    CandidateScore := ExtractLegacyVersionScore(Names[I]);
    if CandidateScore > BestScore then
    begin
      BestScore := CandidateScore;
      BestDir := CandidateDir;
      Result := True;
    end;
  end;
end;

function FindInstalledDir(var InstallDir: String): Boolean;
var
  BestDir: String;
  BestScore: Integer;
begin
  if TryReadInstallDir(HKCU, '{#MyAppId}_is1', InstallDir) then
  begin
    Result := True;
    Exit;
  end;

  if TryReadInstallDir(HKLM, '{#MyAppId}_is1', InstallDir) then
  begin
    Result := True;
    Exit;
  end;

  BestDir := '';
  BestScore := -1;
  FindLegacyInstallDirInRoot(HKCU, BestDir, BestScore);
  FindLegacyInstallDirInRoot(HKLM, BestDir, BestScore);

  InstallDir := BestDir;
  Result := InstallDir <> '';
end;

function GetDefaultInstallDir(Param: String): String;
begin
  if FindInstalledDir(Result) then
    Log('检测到历史安装目录，沿用升级路径: ' + Result)
  else if DirExists('D:\') then
  begin
    Result := 'D:\Program Files\VideoGen';
    Log('未检测到历史安装目录，首次安装默认使用 D 盘 Program Files: ' + Result);
  end
  else
  begin
    Result := ExpandConstant('{autopf}\VideoGen');
    Log('未检测到 D 盘，回退到系统 Program Files 目录: ' + Result);
  end;
end;

function IsMainAppRunning(): Boolean;
var
  ResultCode: Integer;
begin
  Exec(
    ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq {#MyAppExeName}" /NH | find /I "{#MyAppExeName}" >NUL 2>NUL',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
  Result := ResultCode = 0;
end;

function StopMainAppProcesses(const Phase: String): Boolean;
var
  Attempt: Integer;
  ResultCode: Integer;
begin
  Result := True;

  if not IsMainAppRunning() then
    Exit;

  Log('{#MyAppExeName} process detected during ' + Phase + '; forcing shutdown before installation continues.');

  for Attempt := 1 to 3 do
  begin
    Exec(
      ExpandConstant('{sys}\taskkill.exe'),
      '/F /T /IM {#MyAppExeName}',
      '',
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );
    Sleep(500);

    if not IsMainAppRunning() then
      Exit;
  end;

  MsgBox(
    '检测到旧版绘云AI仍在运行，安装程序无法自动结束进程。请手动退出绘云AI后重新运行安装包。',
    mbError,
    MB_OK
  );
  Result := False;
end;

function InitializeSetup(): Boolean;
begin
  Result := StopMainAppProcesses('setup initialization');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not StopMainAppProcesses('file installation') then
    Result := '旧版绘云AI进程仍在运行，安装已取消。';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = wpReady then
    Result := StopMainAppProcesses('ready page');
end;

function InitializeUninstall(): Boolean;
begin
  Result := StopMainAppProcesses('uninstall initialization');
end;
