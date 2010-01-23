unit Console;

interface

uses Windows;

type
  TConsoleRedirector = class(TObject)
  private
    SI: TStartupInfo;
    PI: TProcessInformation;
    StdOutPipeRead, StdOutPipeWrite: THandle;
    FAppName: string;
    FCmdLine: string;
    FLine: string;
    FActive: Boolean;
    FExitCode: DWORD;
  protected
    procedure StartProcess;
    procedure StopProcess;
  public
    constructor Create(const aAppName, aCmdLine: string);
    procedure BeforeDestruction; override;
    procedure Execute;
    function EOF: boolean;
    function GetNextLine: string;
    property ExitCode: DWORD read FExitCode;
  end;

implementation

uses SysUtils;

constructor TConsoleRedirector.Create(const aAppName, aCmdLine: string);
begin
  inherited Create;
  FAppName := aAppName;
  FCmdLine := ' ' + aCmdLine;  // Make sure there is a space in front else CreateProcess will fail
  FActive := False;
  FLine := '';
end;

procedure TConsoleRedirector.BeforeDestruction;
begin
  inherited;
  StopProcess;
end;

function TConsoleRedirector.EOF: boolean;
begin
  Result := not FActive and (FLine = '');
end;

procedure TConsoleRedirector.Execute;
var SA: TSecurityAttributes;
    WasOK: boolean;
begin
  if FActive then
    raise Exception.Create('Service already start');
  StartProcess;
  with SA do begin
    nLength := SizeOf(SA);
    bInheritHandle := True;
    lpSecurityDescriptor := nil;
  end;
  // create pipe for standard output redirection
  CreatePipe(StdOutPipeRead,  // read handle
             StdOutPipeWrite, // write handle
             @SA,             // security attributes
             0                // number of bytes reserved for pipe - 0 default
            );

  // Make child process use StdOutPipeWrite as standard out,
  // and make sure it does not show on screen.
  with SI do begin
    ZeroMemory(@SI, SizeOf(SI));
    cb := SizeOf(SI);
    dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
    wShowWindow := SW_HIDE;
    hStdInput := GetStdHandle(STD_INPUT_HANDLE); // don't redirect std input
    hStdOutput := StdOutPipeWrite;
    hStdError := StdOutPipeWrite;
  end;

  // launch the command line compiler
  WasOK := CreateProcess(PChar(FAppName), PChar(FCmdLine), nil, nil, True, NORMAL_PRIORITY_CLASS, nil, nil, SI, PI);

  // Now that the handle has been inherited, close write to be safe.
  // We don't want to read or write to it accidentally.
  CloseHandle(StdOutPipeWrite);
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
        WasOK := ReadFile(StdOutPipeRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil);
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
      Result := Copy(FLine, 1, iPos);
      Delete(FLine, 1, iPos + 1);
    end;
  end;
end;

procedure TConsoleRedirector.StartProcess;
begin
  FActive := True;
end;

procedure TConsoleRedirector.StopProcess;
begin
  if FActive then begin
    GetExitCodeProcess(PI.hProcess, FExitCode);
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
    CloseHandle(StdOutPipeRead);
    FActive := False;
  end;
end;

end.
