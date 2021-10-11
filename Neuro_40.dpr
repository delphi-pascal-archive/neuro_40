program Neuro_40;

uses
  Forms,
  MainForm in 'MainForm.pas' {Form1},
  SelectNum in 'SelectNum.pas' {Form2};

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
