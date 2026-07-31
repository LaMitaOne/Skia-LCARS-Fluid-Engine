program Project2;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  Unit2 in 'Unit2.pas' {Form2},
  SkiaLCARS_FluidEngine in 'SkiaLCARS_FluidEngine.pas';

{$R *.res}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
