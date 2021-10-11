unit MainForm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls;

const MatrixSize = 10; // Размер матрицы образа
      MemoryK = 0.6;   // коэффициент забывания

type
  TForm1 = class(TForm)
    Box1: TGroupBox;
    Shape1: TShape;
    ClearBtn: TButton;
    MemorizeBtn: TButton;
    RecognizeBtn: TButton;
    Panel1: TPanel;
    Label1: TLabel;
    Label2: TLabel;
    PaintBox1: TPaintBox;
    procedure FormCreate(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBox1MouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure PaintBox1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ClearBtnClick(Sender: TObject);
    procedure MemorizeBtnClick(Sender: TObject);
    procedure RecognizeBtnClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;


  T8Bit = class(TBitmap)   // класс восьмибитной картинки с градациями серого
  private
    Scan: array[0..1023{этим числом ограничена максимальная высота}] of PByte;
    BitHeight, BitWidth:Integer;
    function GetPix(AX, AY: Single): Single;
    procedure SetPix(AX, AY: Single; const Value: Single);
  public
    constructor Create; override;
    procedure Init(AWidth, AHeight: Integer);
    procedure Clear(Color: Byte);
    property Pixels[AX, AY:Single]:Single read GetPix write SetPix;
  end;


  TNeuro = object     // матрица для хранения образа
    A: array[0..MatrixSize-1, 0..MatrixSize-1] of Single;
    Empty: Boolean;
    procedure Clear;
    procedure Normalize;
    procedure MemoryFrom(var Neuro: TNeuro);
    function CompareWith(var Neuro: TNeuro): real; // single
    procedure GetFromBitmap(Bitm: T8Bit);
  end;

  TNeuroBank = object  // набор матриц
    Neuro: array['0'..'9'] of TNeuro;
    procedure ClearAll;
    procedure SaveToFile(FileName: string);
    procedure LoadFromFile(FileName: string);
  end;

var
  Form1: TForm1;
  VScreen: T8Bit;
  Bank: TNeuroBank;
  MouseDowned: Boolean;  // кнопка мыши нажата?

implementation

 uses SelectNum;

{$R *.DFM}

{ T8Bit }

procedure T8Bit.Clear(Color: Byte);
var i:Integer;
begin
  for i:=0 to BitHeight-1 do
    FillChar(PByte(Scan[i])^, Width, Color);
end;

constructor T8Bit.Create;
begin
  inherited Create;
end;

function T8Bit.GetPix(AX, AY: Single): Single;
const OneDiv256=0.00390625;
var dX, dY, idX, idY: Single;
    X,Y, P1, P2:Integer;
begin
  X:=Trunc(AX+16384)-16384;
  Y:=Trunc(AY+16384)-16384;
  dX:=AX-X;
  idX:=1.0-dX;
  dY:=AY-Y;
  idY:=1.0-dY;

  if (X<0) or (X > BitWidth-2) or
     (Y<0) or (Y > BitHeight-2)
   then
     begin
       Result:=1.0;
       EXIT;
     end;

  P1:=Integer(Scan[Y])+X;
  P2:=Integer(Scan[Y+1])+X;
  Result := ((PByte(P1)^*idX + PByte(P1+1)^*dX)*idY + dY*(PByte(P2)^*idX + PByte(P2+1)^*dX))*OneDiv256;
end;

procedure T8Bit.Init(AWidth, AHeight: Integer);
var i:Integer;
    Pal:PLogPalette;
    NewPal:HPalette;
begin
  PixelFormat := pf8bit;
  Width := AWidth;
  Height := AHeight;
  BitHeight:=AHeight;
  BitWidth:=AWidth;
  GetMem(Pal, 256*4 + 40);
  Pal.palVersion := $300;
  Pal.palNumEntries := 256;

  for i := 0 to 255 do
  begin
    Pal.palPalEntry[i].peRed :=   Byte(i);
    Pal.palPalEntry[i].peGreen := Byte(i);
    Pal.palPalEntry[i].peBlue :=  Byte(i);
    Pal.palPalEntry[i].peFlags:=0;
  end;
  NewPal := CreatePalette( Pal^ );
  Palette := NewPal;
  GDIFlush;
  FreeMem(Pal);


  for i:=0 to BitHeight-1 do
    begin
      Scan[i]:=ScanLine[i];
      FillChar(PByte(Scan[i])^, AWidth, 255);
    end;

end;

procedure T8Bit.SetPix(AX, AY: Single; const Value: Single);
var  X,Y :Integer;
begin
  X:=Trunc(AX+16384)-16384;
  Y:=Trunc(AY+16384)-16384;

  if X<0 then X:=0 else
    if X > BitWidth-1 then X:=BitWidth-1;

  if Y<0 then Y:=0 else
    if Y > BitHeight-1 then Y:=BitHeight-1;

  PByte(Integer(Scan[Y])+X)^:=Round(Value*255);
end;

{ TNeuro }

procedure TNeuro.Clear;
var f,g: Integer;
begin
  Empty := True;
  for f := 0 to High(A) do
    for g := 0 to High(A[f]) do
      A[f, g]:=0.0;
end;

function TNeuro.CompareWith(var Neuro: TNeuro): real;
var
 f,g: Integer;
begin
  Result := 0.0;
  for f := 0 to High(A) do
    for g := 0 to High(A[f]) do
      Result := Result + Sqr(Neuro.A[f,g] - A[f,g]);

  Result := Result / Sqr(MatrixSize);
end;

procedure TNeuro.GetFromBitmap(Bitm: T8Bit);
var SymbolRect: TRect;
    f,g, i,j, Delta: Integer;
    Dx, Dy: Single;

  // функция возвращает число цветов, которые на данной линии по яркости меньше, чем половина
  function GetBitmapLineSum(X1,Y1, X2,Y2: Integer): Integer;
  var i: Integer;
  begin
    Result := 0;
    if X1 = X2 then  // вертикальная линия
      begin
        for i := Y1 to Y2 do
          if Bitm.Pixels[X1, i] < 0.5 then Inc(Result);
      end
    else             // горизонтальная линия
      for i := X1 to X2 do
        if Bitm.Pixels[i, Y1] < 0.5 then Inc(Result);
  end;

begin
  Clear;
  // находим символ на картинке
  SymbolRect := Bounds(0,0, Bitm.Width, Bitm.Height);

  with SymbolRect do
  begin
    // определяем верхнюю границу
    while (Top < Bottom) and
          (GetBitmapLineSum(Left, Top, Right, Top) = 0) do Inc(Top, 2);
    // определяем нижнюю границу
    while (Top < Bottom) and
          (GetBitmapLineSum(Left, Bottom, Right, Bottom) = 0) do Dec(Bottom, 2);
    // определяем левую границу
    while (Left < Right) and
          (GetBitmapLineSum(Left, Top, Left, Bottom) = 0) do Inc(Left, 2);
    // определяем правую границу
    while (Left < Right) and
          (GetBitmapLineSum(Right, Top, Right, Bottom) = 0) do Dec(Right, 2);

    if (Right - Left < 2) or (Bottom - Top < 2) then EXIT;

    Delta := ((Bottom-Top)-(Right - Left)) div 2;
    if Abs(Delta) > Bitm.Width div 4 then
      if Delta > 0 then
          begin Inc(Right, Delta); Dec(Left, Delta); end
        else begin Inc(Bottom, -Delta); Dec(Top, -Delta); end;

    Dx := 0.25*(Right - Left) / MatrixSize;
    Dy := 0.25*(Bottom - Top) / MatrixSize;

  end;

  // производим заполнение матрицы A из картинки

  for f := 0 to High(A) do
    for g := 0 to High(A[f]) do
      for i := 0 to 3 do
      for j := 0 to 3 do
        A[f,g] := A[f,g] + (1.0-Bitm.Pixels[ (f*4 + i)*DX + SymbolRect.Left,
                                (g*4 + j)*DY + SymbolRect.Top]) / 16;

  Empty := False;
end;

procedure TNeuro.MemoryFrom(var Neuro: TNeuro);  // запоминание
var f,g: Integer;
    Sum: Single;
begin
  Sum := 0.0;
  for f := 0 to High(A) do
    for g := 0 to High(A[f]) do
    begin
      A[f,g] := A[f,g] * MemoryK + Neuro.A[f,g] * (1-MemoryK);
      if A[f,g] > Sum then Sum := A[f,g];
    end;

  if Sum > 1e-5 then
  begin
    Empty := False;
    Sum := 1 / Sum;
    for f := 0 to High(A) do
      for g := 0 to High(A[f]) do
        A[f,g] := A[f,g] * Sum;
  end
    else Empty := True;

end;

procedure TNeuro.Normalize;        // нормализация
var f,g: Integer;
    Sum: Single;
begin
  Sum := 0.0;
  for f := 0 to High(A) do
    for g := 0 to High(A[f]) do
    begin
      if A[f,g] > Sum then Sum := A[f,g];
    end;

  if Sum > 1e-5 then
  begin
    Empty := False;
    Sum := 1 / Sum;
    for f := 0 to High(A) do
      for g := 0 to High(A[f]) do
        A[f,g] := A[f,g] * Sum;
  end
    else Empty := True;
end;

{ TNeuroBank }

procedure TNeuroBank.ClearAll;
var Ch: Char;
begin
  for Ch := Low(Neuro) to High(Neuro) do
    Neuro[Ch].Clear;
end;

procedure TNeuroBank.LoadFromFile(FileName: String);
var Fil: file of TNeuro;
    Ch: Char;
begin
  AssignFile(Fil, FileName);
  Reset(Fil);

  for Ch := Low(Neuro) to High(Neuro) do
    Read(Fil, Neuro[Ch]);

  CloseFile(Fil);
end;


procedure TNeuroBank.SaveToFile(FileName: String);
var Fil: file of TNeuro;
    Ch: Char;
begin
  AssignFile(Fil, FileName);
  Rewrite(Fil);

  for Ch := Low(Neuro) to High(Neuro) do
    Write(Fil, Neuro[Ch]);

  CloseFile(Fil);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  if FileExists('Bank.bnk')
  then Bank.LoadFromFile('Bank.bnk')
  else Bank.ClearAll;
  // создание полотна, на котором будет рисоваться символ
  VScreen := T8Bit.Create;
  VScreen.Init(PaintBox1.Width + 20, PaintBox1.Height + 20);
  VScreen.Canvas.Pen.Color := clBlack;
  VScreen.Canvas.Pen.Width := 15;
end;

procedure TForm1.PaintBox1Paint(Sender: TObject);
begin
  PaintBox1.Canvas.Draw(-10, -10, VScreen);
end;

procedure TForm1.PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then EXIT;
  MouseDowned := True;
  VScreen.Canvas.MoveTo(X+10, Y+10);
  PaintBox1Paint(nil);
end;

procedure TForm1.PaintBox1MouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
  if MouseDowned then
    begin
      VScreen.Canvas.LineTo(X+10, Y+10);
      PaintBox1Paint(nil);
    end;
end;

procedure TForm1.PaintBox1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  MouseDowned := False;
end;

procedure TForm1.ClearBtnClick(Sender: TObject);
begin
  VScreen.Clear(255);
  PaintBox1Paint(nil);
end;

procedure TForm1.MemorizeBtnClick(Sender: TObject);
var
 Temp: TNeuro;
begin
  Form2.ShowModal;
  case Form2.Tag of
    -1: begin end;
    else
      begin
        Temp.GetFromBitmap(VScreen); // запоминаем образ...
        Temp.Normalize;
        if not Temp.Empty then
          begin
             Bank.Neuro[Chr(48+Form2.Tag)].MemoryFrom(Temp);
             Bank.SaveToFile('Bank.bnk');
          end;
      end;
  end;{case}
end;

procedure TForm1.RecognizeBtnClick(Sender: TObject);
var
 MinVal, Value: real;
 MinString: String;
 Ch: Char;
 Temp: TNeuro;
begin
  MinVal := 1e10;
  MinString := 'Образ не распознан.';
  Temp.GetFromBitmap(VScreen);
  Temp.Normalize;
  PaintBox1Paint(nil); // пытаемся распознать образ...
  if not Temp.Empty then
    for Ch := Low(Bank.Neuro) to High(Bank.Neuro) do
    if not Bank.Neuro[Ch].Empty then
      begin
        Value := Bank.Neuro[Ch].CompareWith(Temp);
        if Value < MinVal then
          begin
            MinVal := Value;
            MinString := 'Это '+Ch;
          end;
      end;
  ShowMessage(MinString);
end;

end.


