unit Console;

interface

uses
  Winapi.Windows;

type
  // Reference: http://snippets.dzone.com/posts/show/5729
  TConsoleRedirector = class(TObject)
  private
    SI: TStartupInfo;
    PI: TProcessInformation;
    FStdInRead: THandle;
    FStdInWrite: THandle;
    FStdOutRead: THandle;
    FStdOutWrite: THandle;
    FAppName: string;
    FCmdLine: string;
    FCurrentDirectory: string;
    FLine: string;
    FActive: Boolean;
    FExitCode: DWORD;
    procedure ClosePipeHandle(var H: THandle);
  protected
    procedure StartProcess;
    procedure StopProcess;
  public
    constructor Create(const aAppName, aCmdLine: string; aCurrentDirectory:
        string); overload;
    constructor Create(const aCmdLine: string; aCurrentDirectory: string = '');
        overload;
    procedure BeforeDestruction; override;
    procedure Execute;
    function EOF: boolean;
    function GetNextLine: string;
    property ExitCode: DWORD read FExitCode;
  end;

implementation

uses
  System.SysUtils;

constructor TConsoleRedirector.Create(const aAppName, aCmdLine: string;
    aCurrentDirectory: string);
begin
  inherited Create;
  FAppName := aAppName;
  FCmdLine := aCmdLine;
  FCurrentDirectory := aCurrentDirectory;
  FActive := False;
  FLine := '';
end;

procedure TConsoleRedirector.BeforeDestruction;
begin
  inherited;
  StopProcess;
end;

procedure TConsoleRedirector.ClosePipeHandle(var H: THandle);
begin
  if H <> 0 then begin
    CloseHandle(H);
    H := 0;
  end;
end;

constructor TConsoleRedirector.Create(const aCmdLine: string;
    aCurrentDirectory: string = '');
begin
  Create('', aCmdLine, aCurrentDirectory);
end;

function TConsoleRedirector.EOF: boolean;
begin
  Result := not FActive and (FLine = '');
end;

procedure TConsoleRedirector.Execute;
var WasOK: boolean;
    pAppName, pCurDir: PChar;
    SD: SECURITY_DESCRIPTOR;
    SA: SECURITY_ATTRIBUTES;
begin
  if FActive then
    raise Exception.Create('Service already start');
  StartProcess;

  ZeroMemory(@SD, SizeOf(SECURITY_DESCRIPTOR));
  ZeroMemory(@SA, SizeOf(SECURITY_ATTRIBUTES));

  if Win32Platform = VER_PLATFORM_WIN32_NT then begin
    InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
    SetSecurityDescriptorDacl(@SD, True, nil, False);
    SA.lpSecurityDescriptor := @SD;
  end else
    SA.lpSecurityDescriptor := nil;
  SA.nLength := SizeOf(SECURITY_ATTRIBUTES);
  SA.bInheritHandle := True;

  // create pipe for standard output redirection
  if not CreatePipe(FStdOutRead, FStdOutWrite, @SA, 0) or
     not CreatePipe(FStdInRead, FStdInWrite, @SA, 0)
  then
    raise Exception.Create('Error while creating pipes');

  SetHandleInformation(FStdOutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(FStdInWrite, HANDLE_FLAG_INHERIT, 0);

  // Make child process use StdOutPipeWrite as standard out,
  // and make sure it does not show on screen.
  with SI do begin
    ZeroMemory(@SI, SizeOf(SI));
    cb := SizeOf(SI);
    dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
    wShowWindow := SW_HIDE;
    hStdInput := FStdInRead;
    hStdOutput := FStdOutWrite;
    hStdError := FStdOutWrite;
  end;

  // launch the command line compiler
  pAppName := nil;
  if FAppName <> '' then
    pAppName := PChar(FAppName);
  UniqueString(FCmdLine);
  if FCurrentDirectory.Trim.IsEmpty then
    pCurDir := nil
  else
    pCurDir := PChar(FCurrentDirectory);
  WasOK := CreateProcess(pAppName, PChar(FCmdLine), nil, nil, True, NORMAL_PRIORITY_CLASS, nil, pCurDir, SI, PI);

  WaitForInputIdle(PI.hProcess, INFINITE);

  // Now that the handle has been inherited, close write to be safe.
  // We don't want to read or write to it accidentally.
  ClosePipeHandle(FStdOutWrite);

  // if process could be created then handle its output
  if not WasOK then
    raise Exception.Create(SysErrorMessage(GetLastError))
  else
    GetExitCodeProcess(PI.hProcess, FExitCode);
end;

function TConsoleRedirector.GetNextLine: string;
var Buffer: array[0..4095] of AnsiChar;
    BytesRead: Cardinal;
    iPos: integer;
    WasOK: boolean;
begin
  Result := '';
  if not EOF then begin
    iPos := Pos(#$0D#$0A, FLine);

    if iPos = 0 then begin
      repeat
        // read block of characters (might contain carriage returns and line feeds)
        WasOK := ReadFile(FStdOutRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil);
        // has anything been read?
        if WasOK and (BytesRead > 0) then begin
          // finish buffer to PChar
          Buffer[BytesRead] := #0;
          // combine the buffer with the rest of the last run
          FLine := FLine + string(Buffer);
        end else begin
          WaitForSingleObject(PI.hProcess, INFINITE);
          StopProcess;
        end;
        iPos := Pos(#$0D#$0A, FLine);
      until (iPos > 0) or not FActive;
    end;
    if iPos > 0 then begin
      Result := Copy(FLine, 1, iPos - 1);   // Do not return CRLF
      Delete(FLine, 1, iPos + 1);           // Remove up to next CRLF
    end else begin
      // GetLastError should be ERROR_BROKEN_PIPE due to console program didn't flush the output buffer properly
      // Will return whatever left in FLine
      Result := FLine;
      FLine := '';
    end;
  end;
end;

procedure TConsoleRedirector.StartProcess;
begin
  FActive := True;
  FStdInRead := 0;
  FStdInWrite := 0;
  FStdOutRead := 0;
  FStdOutWrite := 0;
end;

procedure TConsoleRedirector.StopProcess;
begin
  if FActive then begin
    GetExitCodeProcess(PI.hProcess, FExitCode);
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);

    ClosePipeHandle(FStdInRead);
    ClosePipeHandle(FStdInWrite);
    ClosePipeHandle(FStdOutRead);
    ClosePipeHandle(FStdOutWrite);

    FActive := False;
  end;
end;

end.
