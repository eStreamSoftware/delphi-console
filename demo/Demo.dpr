program Demo;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  Console in '..\Console.pas';

begin
  SetConsoleOutputCP(CP_UTF8);

  var cmd := 'netsh wlan show profiles';
  var o := TConsoleRedirector.Create(cmd);
  try
    o.Execute;
    while not o.EOF do Writeln(o.GetNextLine);
  finally
    o.Free;
  end;

  Writeln('Press enter key to close...');
  Readln;
end.
