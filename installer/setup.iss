#define MyAppName "MTBBS"
; 版本号优先读环境变量（scripts/version.ps1 导出），未设置时回退 1.0.0
#define MyAppVersion GetEnv('MTBBS_VERSION_NAME')
#if MyAppVersion == ''
  #undef MyAppVersion
  #define MyAppVersion '1.0.0'
#endif
#define MyAppPublisher "qcxs"
#define MyAppURL "https://bbs.binmt.cc"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\qcxs\mtbbs
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\mtbbs.exe
OutputDir=..\build
OutputBaseFilename=MTBBS_v{#MyAppVersion}_Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs; Excludes: "mtbbs.exe.WebView2"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\mtbbs.exe"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\mtbbs.exe"

[Run]
Filename: "{app}\mtbbs.exe"; Description: "运行 {#MyAppName}"; Flags: postinstall nowait skipifsilent

[Code]
var
  DeleteUserData: Boolean;

function InitializeUninstall: Boolean;
begin
  Result := True;
  DeleteUserData := MsgBox(
    '是否同时删除个人数据？'#13#10#13#10
      '勾选"是"将删除以下目录及其全部内容：'#13#10
      '  %APPDATA%\qcxs\mtbbs\（数据库、Cookie、设置）'#13#10#13#10
      '建议仅在不再使用此应用时删除。保留数据可下次安装后恢复登录状态和配置。',
    mbConfirmation,
    MB_YESNO
  ) = idYes;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then begin
    if DeleteUserData then begin
      DelTree(ExpandConstant('{userappdata}') + '\qcxs\mtbbs', True, True, True);
    end;
  end;
end;
