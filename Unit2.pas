unit Unit2;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, SkiaLCARS_FluidEngine;

type
  TForm2 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FLCARS: TSkiaLCARSFluid;
  public
    { Public-Deklarationen }
  end;

var
  Form2: TForm2;

implementation

{$R *.fmx}

procedure TForm2.FormCreate(Sender: TObject);
begin
  FLCARS := TSkiaLCARSFluid.Create(Self);
  FLCARS.Parent := Self;
  FLCARS.Align := TAlignLayout.Client;
end;

procedure TForm2.FormDestroy(Sender: TObject);
begin
  if Assigned(FLCARS) then
    FLCARS.Free;
end;

end.
