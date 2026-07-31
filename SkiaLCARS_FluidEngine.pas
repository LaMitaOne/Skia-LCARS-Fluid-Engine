{*******************************************************************************
  uSkiaLCARS_FluidEngine
********************************************************************************
  A high-performance, thread-safe LCARS UI rendering engine for Delphi FMX.
  Built natively on Skia4Delphi.

  Core Architecture:
  - Custom multi-threaded render loop with adaptive sleep cycles for CPU saving.
  - Fluid shape morphing system interpolating UI element vertices at runtime.
  - Automated offscreen surface caching for static elements to reduce draw calls.
  - Centralized physics pipeline managing smooth position, size, and color lerps.

  Key Features:
  - Completely decoupled from the standard FMX layout engine to prevent flicker.
  - Thread-safe object pooling for dynamic UI element creation and destruction.
  - Tactical combat display with radar sweep, targeting AI, and weapon physics.
  - Dynamic layout transitions with directional slide-out animations.
*******************************************************************************}
{     LCARS Engine v0.1                                                        }
{                                                                              }
{------------------------------------------------------------------------------}
{ by Lara Miriam Tamy Reschke                                                  }

unit SkiaLCARS_FluidEngine;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math,
  System.UITypes, System.SyncObjs, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Skia, System.Skia;

type
  // Definition of basic shape building blocks for the LCARS UI
  TLCARSShapeKind = (skBlock, skPillLeft, skPillRight, skTopBar);

  // Record to manage torpedo positions and velocity vectors
  TTorpedo = record
    Pos: TPointF;
    Vel: TPointF;
  end;

  // Manages the tactical radar display, ship schematics, and weapons
  TLCARSSchematic = class
  private
    FCurrentType: Integer;
    FTargetType: Integer;
    FMorphProgress: Single;
    FAlpha: Single;
    FTargetAlpha: Single;
    FPulsePhase: Single;
    FTorpedoes: TArray<TTorpedo>;
    FFireTorpedoes: Boolean;
    FFirePhasers: Boolean;
    FPhaserTime: Single;

    FEnemyPos: TPointF;
    FEnemyTargetPos: TPointF;
    FEnemyMoveTimer: Single;
    FEnemyHit: Boolean;

    function IsAnimating: Boolean;
    procedure Update(DeltaTime: Single; const W, H: Single);
    procedure Draw(const ACanvas: ISkCanvas; const W, H: Single);
    procedure DrawShipSide(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
    procedure DrawTacticalRadar(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
    procedure DrawWarpCore(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
    procedure FireTorpedoes(const StartX, StartY, TargetX, TargetY: Single);
    procedure FirePhasers;
    procedure SetType(NewType: Integer);
  public
    constructor Create;
    function CanFireTorpedoes: Boolean;
  end;

  // Represents a single UI element (button, panel, etc.)
  TLCARSFluidElement = class
  private
    FId: Integer;
    // Current and target values for fluid interpolation
    FCurrentPos: TPointF;
    FTargetPos: TPointF;
    FCurrentSize: TPointF;
    FTargetSize: TPointF;

    FCurrentKind: TLCARSShapeKind;
    FTargetKind: TLCARSShapeKind;
    FMorphProgress: Single;

    FCurrentColor: TAlphaColor;
    FTargetColor: TAlphaColor;

    FAlpha: Single;
    FTargetAlpha: Single;
    FIsRedAlert: Boolean;

    FText: string;
    FIsPooling: Boolean;
    FIsHovered: Boolean;
    FIsClickable: Boolean;

    FOnClick: TProc<TLCARSFluidElement>;

    // Caching mechanism for static elements to boost performance
    FCacheImage: ISkImage;
    FCacheKey: string;
    FCacheValid: Boolean;
    FRevision: Integer;

    procedure BuildCache(const AFont: ISkFont);
    function Lerp(A, B: Single; T: Single): Single; inline;
    function LerpPoint(const A, B: TPointF; T: Single): TPointF; inline;
    function LerpColor(const A, B: TAlphaColor; T: Single): TAlphaColor; inline;
    function GetDisplayColor: TAlphaColor;
    function IsAnimating: Boolean;
    function GetCurrentCacheKey: string;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;

    procedure TransitionTo(const ANewPos: TPointF; const ANewSize: TPointF;
                           ANewKind: TLCARSShapeKind; ANewColor: TAlphaColor;
                           const ANewText: string; AClickable: Boolean = False);

    procedure SlideOut(Direction: Integer; ScreenW, ScreenH: Single);
    procedure FadeOutAndPool;

    procedure Update(DeltaTime: Single);
    procedure Draw(const ACanvas: ISkCanvas; const AFont: ISkFont);
    function ContainsPoint(const P: TPointF): Boolean;
  end;

  // Main component: Manages thread, rendering pipeline, and layouts
  TSkiaLCARSFluid = class(TSkCustomControl)
  private
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection; // Thread-safety lock
    FElements: TObjectList<TLCARSFluidElement>;
    FElementPool: TObjectList<TLCARSFluidElement>; // Reusing objects to prevent memory fragmentation
    FSchematic: TLCARSSchematic;
    FFont: ISkFont;
    FTime: Single;
    FScanLineY: Single;
    FCurrentLayout: Integer;
    FNeedsRedraw: Boolean;
    FRedAlertActive: Boolean;

    function IsSystemAnimating: Boolean;
    procedure DoUpdate(DeltaSec: Double);
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;

    procedure DrawBackground(const ACanvas: ISkCanvas);

    // Layout definitions for different UI states
    procedure BuildLayout1;
    procedure BuildLayout2;
    procedure BuildLayout3;
    procedure SwitchLayout(NewLayout: Integer);
    function FindElementByID(ID: Integer): TLCARSFluidElement;
    procedure ToggleRedAlert;
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

{ TLCARSSchematic }

constructor TLCARSSchematic.Create;
begin
  // Initialization of the tactical display
  FCurrentType := 1;
  FTargetType := 1;
  FMorphProgress := 1.0;
  FAlpha := 1.0;
  FTargetAlpha := 1.0;
  SetLength(FTorpedoes, 0);
  FPhaserTime := 0;
  FEnemyPos := PointF(0, 0);
  FEnemyTargetPos := PointF(0, 0);
  FEnemyMoveTimer := 0;
  FEnemyHit := False;
end;

function TLCARSSchematic.IsAnimating: Boolean;
begin
  // The schematic is always animating (radar sweep, pulse, etc.)
  Result := True;
end;

procedure TLCARSSchematic.SetType(NewType: Integer);
begin
  // Switch the schematic type (side view, radar, warp core)
  if FTargetType <> NewType then
  begin
    FTargetType := NewType;
    FTargetAlpha := 1.0;
    FMorphProgress := 0.0;
  end;
  FFireTorpedoes := (NewType = 2);
  FFirePhasers := (NewType = 2);
end;

function TLCARSSchematic.CanFireTorpedoes: Boolean;
begin
  // Prevents torpedo spamming
  Result := FFireTorpedoes and (Length(FTorpedoes) = 0);
end;

procedure TLCARSSchematic.FireTorpedoes(const StartX, StartY, TargetX, TargetY: Single);
var
  I: Integer;
  DX, DY, Len: Single;
  Torp: TTorpedo;
begin
  if not CanFireTorpedoes then Exit;

  // Calculate flight direction ONCE upon firing
  DX := TargetX - StartX;
  DY := TargetY - StartY;
  Len := Sqrt(DX*DX + DY*DY);
  if Len = 0 then Len := 1;

  // Spawn 4 torpedoes slightly offset
  SetLength(FTorpedoes, 4);
  for I := 0 to 3 do
  begin
    Torp.Pos := PointF(StartX + (I * (DX/Len) * 5), StartY + (I * (DY/Len) * 5));
    Torp.Vel := PointF((DX/Len) * 300, (DY/Len) * 300);
    FTorpedoes[I] := Torp;
  end;
end;

procedure TLCARSSchematic.FirePhasers;
begin
  // Activates phaser effect and randomizes if the enemy is hit
  if not FFirePhasers then Exit;
  FPhaserTime := 0.5;
  FEnemyHit := Random(2) = 1;
end;

procedure TLCARSSchematic.Update(DeltaTime: Single; const W, H: Single);
var
  LerpFactor: Single;
  I, Len: Integer;
  Rad: Single;
begin
  // Time-based interpolation for smooth transitions
  LerpFactor := Min(1.0, DeltaTime * 3.0);
  FAlpha := FAlpha + (FTargetAlpha - FAlpha) * LerpFactor;
  FPulsePhase := FPulsePhase + (DeltaTime * 3.0);

  if FPhaserTime > 0 then
    FPhaserTime := FPhaserTime - DeltaTime;

  if FMorphProgress < 1.0 then
    FMorphProgress := Min(1.0, FMorphProgress + (DeltaTime * 1.5));

  if FMorphProgress >= 1.0 then
    FCurrentType := FTargetType;

  // Enemy AI: Moves randomly in a circle around the ship
  if FCurrentType = 2 then
  begin
    FEnemyMoveTimer := FEnemyMoveTimer - DeltaTime;
    if FEnemyMoveTimer <= 0 then
    begin
      FEnemyMoveTimer := 1.0 + Random(2);
      var Ang := Random * 2 * PI;
      var EnemyRad := 150 + Random(200);
      FEnemyTargetPos := PointF(W / 2 + Cos(Ang) * EnemyRad, H / 2 + Sin(Ang) * EnemyRad);
    end;
    FEnemyPos := FEnemyPos + (FEnemyTargetPos - FEnemyPos) * LerpFactor;
  end;

  // Move torpedoes straight forward and check radar bounds
  Rad := (H - 90) / 2;
  if Rad > 300 then Rad := 300;

  Len := Length(FTorpedoes);
  I := 0;
  while I < Len do
  begin
    FTorpedoes[I].Pos := FTorpedoes[I].Pos + PointF(FTorpedoes[I].Vel.X * DeltaTime, FTorpedoes[I].Vel.Y * DeltaTime);

    // Delete if outside the radar circle
    if Sqr(FTorpedoes[I].Pos.X - W/2) + Sqr(FTorpedoes[I].Pos.Y - H/2) > Sqr(Rad) then
    begin
      FTorpedoes[I] := FTorpedoes[Len - 1];
      Dec(Len);
      SetLength(FTorpedoes, Len);
    end
    else
      Inc(I);
  end;
end;

procedure TLCARSSchematic.Draw(const ACanvas: ISkCanvas; const W, H: Single);
begin
  if FAlpha < 0.01 then Exit;

  // Renders either the morphing state (transition) or the current target
  if FMorphProgress < 1.0 then
  begin
    if FCurrentType = 1 then DrawShipSide(ACanvas, W, H, FAlpha * (1.0 - FMorphProgress));
    if FCurrentType = 2 then DrawTacticalRadar(ACanvas, W, H, FAlpha * (1.0 - FMorphProgress));
    if FCurrentType = 3 then DrawWarpCore(ACanvas, W, H, FAlpha * (1.0 - FMorphProgress));

    if FTargetType = 1 then DrawShipSide(ACanvas, W, H, FAlpha * FMorphProgress);
    if FTargetType = 2 then DrawTacticalRadar(ACanvas, W, H, FAlpha * FMorphProgress);
    if FTargetType = 3 then DrawWarpCore(ACanvas, W, H, FAlpha * FMorphProgress);
  end
  else
  begin
    if FCurrentType = 1 then DrawShipSide(ACanvas, W, H, FAlpha);
    if FCurrentType = 2 then DrawTacticalRadar(ACanvas, W, H, FAlpha);
    if FCurrentType = 3 then DrawWarpCore(ACanvas, W, H, FAlpha);
  end;
end;

procedure TLCARSSchematic.DrawShipSide(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
var
  LPaint: ISkPaint;
  LFont: ISkFont;
  CX, CY: Single;
  LPB: ISkPathBuilder;
  Pulse: Single;

  // Helper to draw line labels
  procedure DrawFixedLabel(StartX, StartY, EndX, EndY: Single; const Txt: string; TxtAlignRight: Boolean = False);
  begin
    ACanvas.DrawLine(PointF(StartX, StartY), PointF(EndX, EndY), LPaint);
    ACanvas.DrawLine(PointF(EndX, EndY - 4), PointF(EndX, EndY + 4), LPaint);
    if TxtAlignRight then
      ACanvas.DrawSimpleText(Txt, EndX - 105, EndY - 8, LFont, LPaint)
    else
      ACanvas.DrawSimpleText(Txt, EndX + 5, EndY - 8, LFont, LPaint);
  end;

begin
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.AntiAlias := True;
  LPaint.StrokeWidth := 2;
  LPaint.StrokeCap := TSkStrokeCap.Round;

  LFont := TSkFont.Create(nil, 12, 1, 0);
  Pulse := (Sin(FPulsePhase) + 1) / 2;

  CX := W / 2;
  CY := H / 2;

  // --- LABELS ---
  LPaint.Color := TAlphaColorF.Create(0.2, 0.8, 1.0, Alpha * 0.8).ToAlphaColor;
  LPaint.StrokeWidth := 1;

  DrawFixedLabel(CX + 130, CY - 5, CX + 130, CY + 25, 'MAIN BRIDGE');
  DrawFixedLabel(CX - 120, CY + 80, CX - 120, CY + 110, 'ENG. HULL', True);
  DrawFixedLabel(CX - 230, CY - 45, CX - 230, CY - 75, 'WARP NACELLE', True);

  // --- SHIP HULL (Vector Paths) ---
  LPaint.Color := TAlphaColorF.Create(1.0, 0.7, 0.2, Alpha).ToAlphaColor;
  LPaint.StrokeWidth := 2;

  LPB := TSkPathBuilder.Create;
  LPB.MoveTo(CX - 150, CY - 30);
  LPB.CubicTo(CX - 150, CY - 60, CX + 120, CY - 60, CX + 170, CY - 30);
  LPB.CubicTo(CX + 180, CY - 20, CX + 180, CY - 10, CX + 170, CY - 5);
  LPB.CubicTo(CX + 120, CY - 5, CX - 150, CY - 5, CX - 150, CY - 30);
  LPB.Close;
  ACanvas.DrawPath(LPB.Snapshot, LPaint);

  LPB := TSkPathBuilder.Create;
  LPB.MoveTo(CX - 30, CY - 5);
  LPB.LineTo(CX - 50, CY + 30);
  LPB.LineTo(CX + 30, CY + 30);
  LPB.LineTo(CX + 20, CY - 5);
  LPB.Close;
  ACanvas.DrawPath(LPB.Snapshot, LPaint);

  ACanvas.DrawRoundRect(RectF(CX - 180, CY + 30, CX + 120, CY + 80), 20, 20, LPaint);

  LPB := TSkPathBuilder.Create;
  LPB.MoveTo(CX - 140, CY + 40);
  LPB.LineTo(CX - 220, CY - 30);
  LPB.LineTo(CX - 210, CY - 35);
  LPB.LineTo(CX - 130, CY + 35);
  LPB.Close;
  ACanvas.DrawPath(LPB.Snapshot, LPaint);

  ACanvas.DrawRoundRect(RectF(CX - 300, CY - 45, CX - 200, CY - 25), 5, 5, LPaint);

  // Pulsating warp drive
  LPaint.Style := TSkPaintStyle.Fill;
  LPaint.Color := TAlphaColorF.Create(1.0, 0.2, 0.2, Alpha * Pulse).ToAlphaColor;
  ACanvas.DrawCircle(PointF(CX - 210, CY - 35), 5, LPaint);
end;

procedure TLCARSSchematic.DrawTacticalRadar(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
var
  LPaint: ISkPaint;
  LFont: ISkFont;
  CX, CY, Rad: Single;
  Pulse, Sweep: Single;
  I: Integer;
  TorpedoRect: TRectF;
  ShipSize: Single;
  PathBuilder: ISkPathBuilder;
begin
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.AntiAlias := True;
  LPaint.StrokeWidth := 2;
  LPaint.StrokeCap := TSkStrokeCap.Round;

  LFont := TSkFont.Create(nil, 12, 1, 0);
  Pulse := (Sin(FPulsePhase) + 1) / 2;
  Sweep := Frac(FPulsePhase / (2*PI));

  CX := W / 2;
  CY := H / 2;

  Rad := (H - 90) / 2;
  if Rad > 300 then Rad := 300;
  ShipSize := 0.4;

  // --- RADAR BACKGROUND ---
  LPaint.Color := TAlphaColorF.Create(0.1, 0.4, 0.2, Alpha * 0.3).ToAlphaColor;
  LPaint.Style := TSkPaintStyle.Fill;
  ACanvas.DrawCircle(PointF(CX, CY), Rad, LPaint);

  LPaint.Style := TSkPaintStyle.Stroke;
  LPaint.Color := TAlphaColorF.Create(0.2, 0.8, 0.4, Alpha * 0.5).ToAlphaColor;
  LPaint.StrokeWidth := 1;
  ACanvas.DrawCircle(PointF(CX, CY), Rad * 0.3, LPaint);
  ACanvas.DrawCircle(PointF(CX, CY), Rad * 0.6, LPaint);
  ACanvas.DrawCircle(PointF(CX, CY), Rad * 0.9, LPaint);

  ACanvas.DrawLine(PointF(CX - Rad, CY), PointF(CX + Rad, CY), LPaint);
  ACanvas.DrawLine(PointF(CX, CY - Rad), PointF(CX, CY + Rad), LPaint);

  // --- RADAR SWEEP (Rotating Scanner) ---
  LPaint.Color := TAlphaColorF.Create(0.2, 1.0, 0.4, 0.3).ToAlphaColor;
  LPaint.Style := TSkPaintStyle.Fill;
  PathBuilder := TSkPathBuilder.Create;
  PathBuilder.MoveTo(CX, CY);
  PathBuilder.ArcTo(RectF(CX - Rad, CY - Rad, CX + Rad, CY + Rad), -90, 20, True);
  PathBuilder.LineTo(CX, CY);
  PathBuilder.Close;

  ACanvas.Save;
  ACanvas.Rotate(Sweep * 360, CX, CY);
  ACanvas.DrawPath(PathBuilder.Snapshot, LPaint);
  ACanvas.Restore;

  // --- OUR SHIP ---
  LPaint.Color := TAlphaColorF.Create(1.0, 0.7, 0.2, Alpha).ToAlphaColor;
  LPaint.StrokeWidth := 2;
  LPaint.Style := TSkPaintStyle.Stroke;

  ACanvas.DrawOval(RectF(CX - 40*ShipSize, CY - 60*ShipSize, CX + 40*ShipSize, CY + 20*ShipSize), LPaint);
  ACanvas.DrawRoundRect(RectF(CX - 30*ShipSize, CY + 20*ShipSize, CX + 30*ShipSize, CY + 90*ShipSize), 10, 10, LPaint);
  ACanvas.DrawRoundRect(RectF(CX - 50*ShipSize, CY + 30*ShipSize, CX - 40*ShipSize, CY + 110*ShipSize), 3, 3, LPaint);
  ACanvas.DrawRoundRect(RectF(CX + 40*ShipSize, CY + 30*ShipSize, CX + 50*ShipSize, CY + 110*ShipSize), 3, 3, LPaint);

  // --- ENEMY ---
  LPaint.Color := TAlphaColorF.Create(1.0, 0.2, 0.2, Alpha).ToAlphaColor;
  LPaint.Style := TSkPaintStyle.Fill;
  if FEnemyHit then
  begin
    // Explosion effect when hit
    ACanvas.DrawCircle(FEnemyPos, 20 * (1.0 - (FPhaserTime / 0.5)), LPaint);
  end
  else
  begin
    ACanvas.DrawCircle(FEnemyPos, 6, LPaint);
    LPaint.Style := TSkPaintStyle.Stroke;
    LPaint.StrokeWidth := 1;
    ACanvas.DrawLine(PointF(FEnemyPos.X - 15, FEnemyPos.Y), PointF(FEnemyPos.X + 15, FEnemyPos.Y), LPaint);
    ACanvas.DrawLine(PointF(FEnemyPos.X, FEnemyPos.Y - 15), PointF(FEnemyPos.X, FEnemyPos.Y + 15), LPaint);
  end;

  // --- WEAPONS (Phasers & Torpedoes) ---
  if (FPhaserTime > 0) then
  begin
    var PhaAlpha := (FPhaserTime / 0.5) * Alpha;
    LPaint.Color := TAlphaColorF.Create(1.0, 0.2, 0.0, PhaAlpha).ToAlphaColor;
    LPaint.StrokeWidth := 2;
    if FEnemyHit then
      ACanvas.DrawLine(PointF(CX, CY - 20), FEnemyPos, LPaint)
    else
      ACanvas.DrawLine(PointF(CX, CY - 20), PointF(FEnemyPos.X - 20, FEnemyPos.Y), LPaint);
  end;

  if Length(FTorpedoes) > 0 then
  begin
    LPaint.Color := TAlphaColorF.Create(1.0, 0.3, 0.0, Alpha).ToAlphaColor;
    LPaint.Style := TSkPaintStyle.Fill;
    for I := 0 to High(FTorpedoes) do
    begin
      TorpedoRect := RectF(FTorpedoes[I].Pos.X - 5, FTorpedoes[I].Pos.Y - 5, FTorpedoes[I].Pos.X + 5, FTorpedoes[I].Pos.Y + 5);
      ACanvas.DrawRect(TorpedoRect, LPaint);
    end;
  end;
end;

procedure TLCARSSchematic.DrawWarpCore(const ACanvas: ISkCanvas; const W, H: Single; Alpha: Single);
var
  LPaint: ISkPaint;
  CX, CY: Single;
  Pulse: Single;
begin
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.AntiAlias := True;
  LPaint.StrokeWidth := 2;

  Pulse := (Sin(FPulsePhase * 2) + 1) / 2;
  CX := W / 2;
  CY := H / 2;

  // Warp core reactor casing
  LPaint.Color := TAlphaColorF.Create(1.0, 0.2, 0.2, Alpha).ToAlphaColor;
  ACanvas.DrawRoundRect(RectF(CX - 40, CY - 180, CX + 40, CY + 180), 15, 15, LPaint);

  // Pulsating reactor interior
  LPaint.Style := TSkPaintStyle.Fill;
  LPaint.Color := TAlphaColorF.Create(0.2, 1.0, 0.8, Alpha * Pulse).ToAlphaColor;
  ACanvas.DrawRoundRect(RectF(CX - 20, CY - 160, CX + 20, CY + 160), 10, 10, LPaint);

  // Top and bottom plasma chambers
  LPaint.Style := TSkPaintStyle.Stroke;
  LPaint.Color := TAlphaColorF.Create(1.0, 0.8, 0.3, Alpha).ToAlphaColor;
  ACanvas.DrawCircle(PointF(CX, CY - 170), 10, LPaint);
  ACanvas.DrawCircle(PointF(CX, CY + 170), 10, LPaint);
end;


{ TLCARSFluidElement }

constructor TLCARSFluidElement.Create(AId: Integer);
begin
  // Default values for a new UI element
  FId := AId;
  FCurrentPos := PointF(0, 0);
  FTargetPos := PointF(0, 0);
  FCurrentSize := PointF(100, 40);
  FTargetSize := PointF(100, 40);
  FCurrentKind := skBlock;
  FTargetKind := skBlock;
  FMorphProgress := 1.0;
  FCurrentColor := $FFFF9900;
  FTargetColor := $FFFF9900;
  FAlpha := 0;
  FTargetAlpha := 0;
  FIsPooling := True;
  FIsHovered := False;
  FIsClickable := False;
  FCacheValid := False;
  FRevision := 0;
  FIsRedAlert := False;
end;

destructor TLCARSFluidElement.Destroy;
begin
  FCacheImage := nil;
  inherited;
end;

// Mathematical Linear Interpolation functions (Lerp)
function TLCARSFluidElement.Lerp(A, B, T: Single): Single;
begin
  Result := A + (B - A) * T;
end;

function TLCARSFluidElement.LerpPoint(const A, B: TPointF; T: Single): TPointF;
begin
  Result.X := Lerp(A.X, B.X, T);
  Result.Y := Lerp(A.Y, B.Y, T);
end;

function TLCARSFluidElement.LerpColor(const A, B: TAlphaColor; T: Single): TAlphaColor;
var
  CA, CB: TAlphaColorF;
begin
  CA := TAlphaColorF.Create(A);
  CB := TAlphaColorF.Create(B);
  Result := TAlphaColorF.Create(
    Lerp(CA.R, CB.R, T),
    Lerp(CA.G, CB.G, T),
    Lerp(CA.B, CB.B, T),
    Lerp(CA.A, CB.A, T)
  ).ToAlphaColor;
end;

function TLCARSFluidElement.GetDisplayColor: TAlphaColor;
var
  C1, C2, CMix: TAlphaColorF;
  Pulse: Single;
begin
  // Determines display color based on state (Red Alert, Hover)
  if FIsRedAlert then
  begin
    Pulse := (Sin(FMorphProgress * 10) + 1) / 2;
    C1 := TAlphaColorF.Create($FFFF5050);
    C2 := TAlphaColorF.Create($FF660000);
    CMix := C1 + (C2 - C1) * Pulse;
    Result := CMix.ToAlphaColor;
  end
  else if FIsHovered and FIsClickable then
  begin
    // Brighten on hover
    C1 := TAlphaColorF.Create(FCurrentColor);
    C2 := TAlphaColorF.Create(TAlphaColors.White);
    CMix := C1 + (C2 - C1) * 0.4;
    Result := CMix.ToAlphaColor;
  end
  else
    Result := FCurrentColor;
end;

function TLCARSFluidElement.IsAnimating: Boolean;
begin
  // Checks if the element is still animating
  if FIsRedAlert then Exit(True);
  Result := (FMorphProgress < 1.0) or (Abs(FAlpha - FTargetAlpha) > 0.01) or
            (Abs(FCurrentPos.X - FTargetPos.X) > 0.5) or (Abs(FCurrentPos.Y - FTargetPos.Y) > 0.5) or
            (Abs(FCurrentSize.X - FTargetSize.X) > 0.5) or (Abs(FCurrentSize.Y - FTargetSize.Y) > 0.5) or
            (FCurrentColor <> FTargetColor);
end;

function TLCARSFluidElement.GetCurrentCacheKey: string;
begin
  // Generates a key to check if the cache needs to be rebuilt
  Result := 'REV_' + IntToStr(FRevision) + '_RA_' + BoolToStr(FIsRedAlert, True);
end;

procedure TLCARSFluidElement.BuildCache(const AFont: ISkFont);
var
  LSurface: ISkSurface;
  LCanvas: ISkCanvas;
  LPaint: ISkPaint;
  LPB: ISkPathBuilder;
  LPath: ISkPath;
  R: Single;
  RectDraw: TRectF;
begin
  // Renders the shape onto an offscreen surface to save performance
  if (FCurrentSize.X < 1) or (FCurrentSize.Y < 1) then Exit;

  LSurface := TSkSurface.MakeRaster(Round(FCurrentSize.X), Round(FCurrentSize.Y));
  LCanvas := LSurface.Canvas;
  LCanvas.Clear(TAlphaColors.Null);

  LPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  LPaint.AntiAlias := True;
  LPaint.Color := GetDisplayColor;

  RectDraw := TRectF.Create(0, 0, FCurrentSize.X, FCurrentSize.Y);

  // Dynamic adjustment of corner radii based on shape
  R := 20;
  if RectDraw.Width < 40 then R := RectDraw.Width / 2 - 2;
  if RectDraw.Height < 40 then R := RectDraw.Height / 2 - 2;
  if FCurrentKind = skTopBar then R := RectDraw.Height / 2;

  LPB := TSkPathBuilder.Create;
  LPB.MoveTo(RectDraw.Left, RectDraw.Bottom);

  // Path generation for various LCARS shapes
  if FCurrentKind in [skBlock, skPillRight, skTopBar] then
  begin
    LPB.LineTo(RectDraw.Right - R, RectDraw.Bottom);
    LPB.QuadTo(RectDraw.Right, RectDraw.Bottom, RectDraw.Right, RectDraw.Bottom - R);
  end
  else
    LPB.LineTo(RectDraw.Right, RectDraw.Bottom);

  LPB.LineTo(RectDraw.Right, RectDraw.Top);

  if FCurrentKind in [skPillRight, skTopBar] then
  begin
    LPB.LineTo(RectDraw.Right, RectDraw.Top + R);
    LPB.QuadTo(RectDraw.Right, RectDraw.Top, RectDraw.Right - R, RectDraw.Top);
  end
  else
    LPB.LineTo(RectDraw.Left, RectDraw.Top);

  if FCurrentKind = skPillLeft then
  begin
    LPB.LineTo(RectDraw.Left + R, RectDraw.Top);
    LPB.QuadTo(RectDraw.Left, RectDraw.Top, RectDraw.Left, RectDraw.Top + R);
  end
  else
    LPB.LineTo(RectDraw.Left, RectDraw.Top);

  LPB.Close;
  LPath := LPB.Snapshot;

  LCanvas.DrawPath(LPath, LPaint);

  // Draw text if element is visible enough
  if (FText <> '') and (FAlpha > 0.5) then
  begin
    LPaint.Color := TAlphaColors.Black;
    LCanvas.DrawSimpleText(FText, 12, 24, AFont, LPaint);
  end;

  FCacheImage := LSurface.MakeImageSnapshot;
  FCacheKey := GetCurrentCacheKey;
  FCacheValid := True;
end;

procedure TLCARSFluidElement.TransitionTo(const ANewPos: TPointF; const ANewSize: TPointF;
  ANewKind: TLCARSShapeKind; ANewColor: TAlphaColor;
  const ANewText: string; AClickable: Boolean = False);
begin
  // Sets new target values for animation
  FTargetPos := ANewPos;
  FTargetSize := ANewSize;
  FTargetKind := ANewKind;
  FTargetColor := ANewColor;
  FText := ANewText;
  FIsClickable := AClickable;
  FTargetAlpha := 1.0;
  FIsPooling := False;

  // Reset morphing if the shape changes
  if FCurrentKind <> FTargetKind then
    FMorphProgress := 0.0
  else
    FMorphProgress := 1.0;

  FCacheValid := False;
end;

procedure TLCARSFluidElement.SlideOut(Direction: Integer; ScreenW, ScreenH: Single);
begin
  // Prepares the element to be slid out of the screen
  FTargetAlpha := 0.0;
  FIsPooling := True;
  FIsClickable := False;
  FIsRedAlert := False;

  case Direction of
    1: FTargetPos := PointF(-300, FCurrentPos.Y); // Left
    2: FTargetPos := PointF(ScreenW + 300, FCurrentPos.Y); // Right
    3: FTargetPos := PointF(FCurrentPos.X, -300); // Top
    4: FTargetPos := PointF(FCurrentPos.X, ScreenH + 300); // Bottom
  end;
  FCacheValid := False;
end;

procedure TLCARSFluidElement.FadeOutAndPool;
begin
  // Fade element out and return it to the pool
  FTargetAlpha := 0.0;
  FTargetPos := PointF(2000, 2000);
  FIsPooling := True;
  FIsClickable := False;
  FIsRedAlert := False;
  FCacheValid := False;
end;

procedure TLCARSFluidElement.Update(DeltaTime: Single);
var
  LerpFactor: Single;
begin
  // Interpolation of values towards target
  LerpFactor := Min(1.0, DeltaTime * 3.5);

  FCurrentPos := LerpPoint(FCurrentPos, FTargetPos, LerpFactor);
  FCurrentSize := LerpPoint(FCurrentSize, FTargetSize, LerpFactor);
  FAlpha := Lerp(FAlpha, FTargetAlpha, LerpFactor);
  FCurrentColor := LerpColor(FCurrentColor, FTargetColor, LerpFactor);

  // Red Alert has its own pulse, so constant cache update
  if FIsRedAlert then
  begin
    FMorphProgress := FMorphProgress + DeltaTime;
    FCacheValid := False;
  end
  else
  begin
    if FMorphProgress < 1.0 then
      FMorphProgress := Min(1.0, FMorphProgress + (DeltaTime * 2.0));

    // Invalidate cache if the element is still moving or changing
    if (Abs(FCurrentPos.X - FTargetPos.X) > 0.5) or (Abs(FCurrentPos.Y - FTargetPos.Y) > 0.5) or
       (Abs(FCurrentSize.X - FTargetSize.X) > 0.5) or (Abs(FCurrentSize.Y - FTargetSize.Y) > 0.5) or
       (Abs(FAlpha - FTargetAlpha) > 0.01) or (FCurrentColor <> FTargetColor) then
    begin
      FCacheValid := False;
    end
    else if FMorphProgress < 1.0 then
    begin
      FCacheValid := False;
    end
    else if not FCacheValid then
    begin
      // Rebuild cache finally when everything is settled
      Inc(FRevision);
      FCurrentKind := FTargetKind;
    end;
  end;
end;

procedure TLCARSFluidElement.Draw(const ACanvas: ISkCanvas; const AFont: ISkFont);
type
  TShapeVertices = array[0..39] of TPointF;
var
  LPaint: ISkPaint;
  LPB: ISkPathBuilder;
  RectCur: TRectF;
  R, MorphT, RMorph, ROld, RNew: Single;
  VertsOld, VertsNew, VertsMorphed: TShapeVertices;
  i: Integer;

  // Helper: Generates vertices for morphing animation
  function GetShapeVertices(Kind: TLCARSShapeKind; const Rect: TRectF; const CustomR: Single): TShapeVertices;
  var
    i: Integer;
    CX, CY: Single;
    UseR: Single;
  begin
    UseR := CustomR;

    if Kind = skPillLeft then UseR := Min(Rect.Height / 2, CustomR);
    if Kind = skPillRight then UseR := Min(Rect.Height / 2, CustomR);
    if Kind = skTopBar then UseR := Min(Rect.Height / 2, CustomR);

    // Generates 40 points along the shape's circumference
    for i := 0 to 9 do
      Result[i] := PointF(Rect.Left + (Rect.Width * (i/10)), Rect.Bottom);

    if Kind in [skBlock, skPillRight, skTopBar] then
    begin
      CX := Rect.Right - UseR;
      CY := Rect.Bottom - UseR;
      for i := 0 to 9 do
        Result[10 + i] := PointF(CX + Cos(0 + (i/10) * (PI/2)) * UseR, CY + Sin(0 + (i/10) * (PI/2)) * UseR);
    end
    else
    begin
      for i := 0 to 9 do
        Result[10 + i] := PointF(Rect.Right, Rect.Bottom - (Rect.Height * (i/10)));
    end;

    for i := 0 to 9 do
      Result[20 + i] := PointF(Rect.Right, Rect.Bottom - UseR - ((Rect.Height - UseR) * (i/10)));

    if Kind in [skPillRight, skTopBar] then
    begin
      CX := Rect.Right - UseR;
      CY := Rect.Top + UseR;
      for i := 0 to 9 do
        Result[30 + i] := PointF(CX + Cos(PI/2 + (i/10) * (PI/2)) * UseR, CY + Sin(PI/2 + (i/10) * (PI/2)) * UseR);
    end
    else
    begin
      for i := 0 to 9 do
        Result[30 + i] := PointF(Rect.Right - UseR - ((Rect.Width - UseR) * (i/10)), Rect.Top);
    end;

    if Kind = skPillLeft then
    begin
      CX := Rect.Left + UseR;
      CY := Rect.Top + UseR;
      for i := 0 to 9 do
        Result[i] := PointF(CX - Cos(PI - (i/10) * (PI/2)) * UseR, CY - Sin(PI - (i/10) * (PI/2)) * UseR + (Rect.Bottom - Rect.Top - 2*UseR));
    end;
  end;

begin
  if FAlpha < 0.01 then Exit;

  // Use cache when possible to minimize draw calls
  if not FIsRedAlert then
  begin
    if not FCacheValid or (FCacheKey <> GetCurrentCacheKey) then
      BuildCache(AFont);
  end;

  LPaint := TSkPaint.Create;
  LPaint.AntiAlias := True;

  if FCacheValid and Assigned(FCacheImage) and not FIsRedAlert then
  begin
    ACanvas.DrawImage(FCacheImage, FCurrentPos.X, FCurrentPos.Y, LPaint);
    Exit;
  end;

  LPaint.Style := TSkPaintStyle.Fill;
  LPaint.Color := GetDisplayColor;

  RectCur := TRectF.Create(FCurrentPos.X, FCurrentPos.Y, FCurrentPos.X + FCurrentSize.X, FCurrentPos.Y + FCurrentSize.Y);

  // If the shape is changing (morphing), calculate interpolation between old and new vertices
  if (FMorphProgress < 1.0) and not FIsRedAlert then
  begin
    MorphT := FMorphProgress;

    ROld := 20;
    if RectCur.Width < 40 then ROld := RectCur.Width / 2 - 2;
    if RectCur.Height < 40 then ROld := RectCur.Height / 2 - 2;
    if FCurrentKind = skTopBar then ROld := RectCur.Height / 2;

    RNew := 20;
    if RectCur.Width < 40 then RNew := RectCur.Width / 2 - 2;
    if RectCur.Height < 40 then RNew := RectCur.Height / 2 - 2;
    if FTargetKind = skTopBar then RNew := RectCur.Height / 2;

    RMorph := ROld + (RNew - ROld) * MorphT;

    VertsOld := GetShapeVertices(FCurrentKind, RectCur, RMorph);
    VertsNew := GetShapeVertices(FTargetKind, RectCur, RMorph);

    for i := 0 to 39 do
    begin
      VertsMorphed[i].X := VertsOld[i].X + (VertsNew[i].X - VertsOld[i].X) * MorphT;
      VertsMorphed[i].Y := VertsOld[i].Y + (VertsNew[i].Y - VertsOld[i].Y) * MorphT;
    end;

    LPB := TSkPathBuilder.Create;
    LPB.MoveTo(VertsMorphed[0]);
    for i := 1 to 39 do
      LPB.LineTo(VertsMorphed[i]);
    LPB.Close;

    ACanvas.DrawPath(LPB.Snapshot, LPaint);
  end
  else
  begin
    // Draw static shape
    R := 20;
    if RectCur.Width < 40 then R := RectCur.Width / 2 - 2;
    if RectCur.Height < 40 then R := RectCur.Height / 2 - 2;
    if FCurrentKind = skTopBar then R := RectCur.Height / 2;

    LPB := TSkPathBuilder.Create;
    LPB.MoveTo(RectCur.Left, RectCur.Bottom);

    if FCurrentKind in [skBlock, skPillRight, skTopBar] then
    begin
      LPB.LineTo(RectCur.Right - R, RectCur.Bottom);
      LPB.QuadTo(RectCur.Right, RectCur.Bottom, RectCur.Right, RectCur.Bottom - R);
    end
    else
      LPB.LineTo(RectCur.Right, RectCur.Bottom);

    LPB.LineTo(RectCur.Right, RectCur.Top);

    if FCurrentKind in [skPillRight, skTopBar] then
    begin
      LPB.LineTo(RectCur.Right, RectCur.Top + R);
      LPB.QuadTo(RectCur.Right, RectCur.Top, RectCur.Right - R, RectCur.Top);
    end
    else
      LPB.LineTo(RectCur.Left, RectCur.Top);

    if FCurrentKind = skPillLeft then
    begin
      LPB.LineTo(RectCur.Left + R, RectCur.Top);
      LPB.QuadTo(RectCur.Left, RectCur.Top, RectCur.Left, RectCur.Top + R);
    end
    else
      LPB.LineTo(RectCur.Left, RectCur.Top);

    LPB.Close;

    ACanvas.DrawPath(LPB.Snapshot, LPaint);
  end;

  // Draw text (only if sufficiently visible)
  if (FText <> '') and (FAlpha > 0.5) then
  begin
    LPaint.Color := TAlphaColors.Black;
    ACanvas.DrawSimpleText(FText, RectCur.Left + 12, RectCur.Top + 24, AFont, LPaint);
  end;
end;

function TLCARSFluidElement.ContainsPoint(const P: TPointF): Boolean;
begin
  // Simple bounding box hitcheck for mouse events
  Result := TRectF.Create(FCurrentPos.X, FCurrentPos.Y,
    FCurrentPos.X + FCurrentSize.X, FCurrentPos.Y + FCurrentSize.Y).Contains(P);
end;


{ TSkiaLCARSFluid }

constructor TSkiaLCARSFluid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := TAlignLayout.Client;
  HitTest := True;

  // Thread-safety initialization
  FLock := TCriticalSection.Create;
  FElements := TObjectList<TLCARSFluidElement>.Create;
  FElementPool := TObjectList<TLCARSFluidElement>.Create;
  FSchematic := TLCARSSchematic.Create;

  FFont := TSkFont.Create(nil, 14, 1, 0);

  FActive := True;
  FScanLineY := 0;
  FCurrentLayout := 1;
  FNeedsRedraw := True;
  FRedAlertActive := False;

  BuildLayout1;
  StartThread;
end;

destructor TSkiaLCARSFluid.Destroy;
begin
  // Cleanup background thread and lists
  StopThread;
  FElements.Free;
  FElementPool.Free;
  FSchematic.Free;
  FLock.Free;
  inherited;
end;

function TSkiaLCARSFluid.FindElementByID(ID: Integer): TLCARSFluidElement;
var E: TLCARSFluidElement;
begin
  Result := nil;
  for E in FElements do if E.FId = ID then Exit(E);
end;

function TSkiaLCARSFluid.IsSystemAnimating: Boolean;
var
  Elem: TLCARSFluidElement;
begin
  // Checks if any animation is in progress to spare CPU
  if FSchematic.IsAnimating then Exit(True);
  for Elem in FElements do
    if Elem.IsAnimating then Exit(True);
  Result := False;
end;

procedure TSkiaLCARSFluid.ToggleRedAlert;
var
  Elem: TLCARSFluidElement;
begin
  // Toggles Red Alert mode and changes corresponding button colors/text
  FRedAlertActive := not FRedAlertActive;

  if FRedAlertActive then
  begin
    Elem := FindElementByID(1);
    if Assigned(Elem) then
    begin
      Elem.FIsRedAlert := True;
      Elem.TransitionTo(Elem.FTargetPos, Elem.FTargetSize, skPillRight, $FFFF3030, 'RED ALERT!');
      FNeedsRedraw := True;
    end;
    Elem := FindElementByID(2);
    if Assigned(Elem) then
    begin
      Elem.FIsRedAlert := True;
      Elem.TransitionTo(Elem.FTargetPos, Elem.FTargetSize, skPillRight, $FFFF3030, 'RED ALERT!');
      FNeedsRedraw := True;
    end;
  end
  else
  begin
    Elem := FindElementByID(1);
    if Assigned(Elem) then
    begin
      Elem.FIsRedAlert := False;
      Elem.TransitionTo(Elem.FTargetPos, Elem.FTargetSize, skPillRight, $FFCC66CC, 'USS ENTERPRISE - NCC-1701-C');
      FNeedsRedraw := True;
    end;
    Elem := FindElementByID(2);
    if Assigned(Elem) then
    begin
      Elem.FIsRedAlert := False;
      Elem.TransitionTo(Elem.FTargetPos, Elem.FTargetSize, skPillRight, $FFCC66CC, 'STARFLEET COMMAND');
      FNeedsRedraw := True;
    end;
  end;
end;

procedure TSkiaLCARSFluid.SwitchLayout(NewLayout: Integer);
begin
  // Switches between the 3 UI states
  FCurrentLayout := NewLayout;
  case FCurrentLayout of
    1: begin BuildLayout1; FSchematic.SetType(1); end;
    2: begin BuildLayout2; FSchematic.SetType(2); end;
    3: begin BuildLayout3; FSchematic.SetType(3); end;
  end;
  FNeedsRedraw := True;
end;

procedure TSkiaLCARSFluid.BuildLayout1;
var
  Elem: TLCARSFluidElement;
  Margin, W, H: Single;
begin
  // Main menu layout
  FLock.Acquire;
  try
    // Slide old elements out
    for Elem in FElements do
      if not Elem.FIsPooling then Elem.SlideOut(3, Width, Height);

    Margin := 20; W := Width; H := Height;

    // Header & Footer
    Elem := FindElementByID(1);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(1); Elem.FCurrentPos := PointF(-50, -50); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, Margin), PointF(W - Margin*2, 35), skPillRight, $FFCC66CC, 'USS ENTERPRISE - NCC-1701-C');

    Elem := FindElementByID(2);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(2); Elem.FCurrentPos := PointF(-50, H+50); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, H - Margin - 35), PointF(W - Margin*2, 35), skPillRight, $FFCC66CC, 'STARFLEET COMMAND');

    // Left Buttons
    Elem := FindElementByID(3);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(3); Elem.FCurrentPos := PointF(-200, 100); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 100), PointF(150, 120), skBlock, $FFFF9900, 'MAIN ROSTER', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin SwitchLayout(2); end;

    Elem := FindElementByID(4);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(4); Elem.FCurrentPos := PointF(-200, 230); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 230), PointF(150, 60), skBlock, $FF3399FF, 'TACTICAL', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin SwitchLayout(2); end;

    Elem := FindElementByID(5);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(5); Elem.FCurrentPos := PointF(-200, 300); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 300), PointF(150, 60), skBlock, $FF3399FF, 'ENGINEERING', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin SwitchLayout(3); end;

    Elem := FindElementByID(6);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(6); Elem.FCurrentPos := PointF(-200, 370); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 370), PointF(150, 150), skPillLeft, $FFFF3030, 'RED ALERT', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin ToggleRedAlert; end;

    // Right Panels
    Elem := FindElementByID(7);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(7); Elem.FCurrentPos := PointF(W+200, 100); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(W - Margin - 195, 100), PointF(150, 100), skBlock, $FFFF9900, 'WARP CORE');

    Elem := FindElementByID(8);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(8); Elem.FCurrentPos := PointF(W+200, 210); Elem.FAlpha := 0; FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(W - Margin - 195, 210), PointF(150, 150), skPillLeft, $FFCC66CC, 'SHIELDS');

  finally
    FLock.Release;
  end;
end;

procedure TSkiaLCARSFluid.BuildLayout2;
var
  Elem: TLCARSFluidElement;
  Margin, W, H: Single;
begin
  // Tactical layout (Battle Bridge)
  FLock.Acquire;
  try
    for Elem in FElements do
      if not Elem.FIsPooling then Elem.SlideOut(3, Width, Height);

    Margin := 20; W := Width; H := Height;

    Elem := FindElementByID(1);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(1); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, Margin), PointF(W - Margin*2, 35), skPillRight, $FFFF3030, 'RED ALERT - TACTICAL MODE');

    Elem := FindElementByID(2);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(2); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, H - Margin - 35), PointF(W - Margin*2, 35), skPillRight, $FFFF3030, 'SHIELDS AT 40%');

    Elem := FindElementByID(3);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(3); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 100), PointF(150, 120), skBlock, $FF3399FF, 'PHASERS', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement)
    begin
      SwitchLayout(2);
      FSchematic.FirePhasers;
    end;

    Elem := FindElementByID(4);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(4); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 230), PointF(150, 60), skBlock, $FF3399FF, 'PHOTON TORP', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement)
    begin
      SwitchLayout(2);
      if FSchematic.CanFireTorpedoes then
        // Fire torpedoes exactly from the center (CX, CY-20) to the enemy
        FSchematic.FireTorpedoes(W / 2, (H / 2) - 20, FSchematic.FEnemyPos.X, FSchematic.FEnemyPos.Y);
    end;

    Elem := FindElementByID(5);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(5); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 300), PointF(150, 60), skBlock, $FF3399FF, 'RETURN', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin SwitchLayout(1); end;

    Elem := FindElementByID(7);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(7); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(W - Margin - 195, 100), PointF(150, 350), skPillRight, $FFFF3030, 'TARGET LOCK');

  finally
    FLock.Release;
  end;
end;

procedure TSkiaLCARSFluid.BuildLayout3;
var
  Elem: TLCARSFluidElement;
  Margin, W, H: Single;
begin
  // Engineering layout
  FLock.Acquire;
  try
    for Elem in FElements do
      if not Elem.FIsPooling then Elem.SlideOut(1, Width, Height);

    Margin := 20; W := Width; H := Height;

    Elem := FindElementByID(1);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(1); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, Margin), PointF(W - Margin*2, 35), skPillRight, $FF00BFFF, 'ENGINEERING OVERRIDE');

    Elem := FindElementByID(2);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(2); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin, H - Margin - 35), PointF(W - Margin*2, 35), skPillRight, $FF00BFFF, 'COOLANT LEVELS NOMINAL');

    Elem := FindElementByID(3);
    if Elem = nil then begin Elem := TLCARSFluidElement.Create(3); FElements.Add(Elem); end;
    Elem.TransitionTo(PointF(Margin + 45, 100), PointF(150, 420), skPillLeft, $FF00BFFF, 'SYSTEMS', True);
    Elem.FOnClick := procedure(_: TLCARSFluidElement) begin SwitchLayout(1); end;

  finally
    FLock.Release;
  end;
end;

procedure TSkiaLCARSFluid.Resize;
begin
  // Rebuild layout on window resize
  inherited;
  SwitchLayout(FCurrentLayout);
end;

procedure TSkiaLCARSFluid.DoUpdate(DeltaSec: Double);
var
  Elem: TLCARSFluidElement;
  i: Integer;
begin
  // Update loop: Called from the background thread
  if not FNeedsRedraw and not IsSystemAnimating then Exit;

  FNeedsRedraw := False;

  FTime := FTime + DeltaSec;
  // Scanline effect for retro look
  FScanLineY := FScanLineY + (DeltaSec * 200);
  if FScanLineY > Height then FScanLineY := -50;

  FLock.Acquire;
  try
    FSchematic.Update(DeltaSec, Width, Height);
    for i := FElements.Count - 1 downto 0 do
    begin
      Elem := FElements[i];
      Elem.Update(DeltaSec);

      // Move faded out objects back to the pool
      if (Elem.FAlpha < 0.01) and (Elem.FIsPooling) then
      begin
        FElements.Extract(Elem);
        FElementPool.Add(Elem);
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TSkiaLCARSFluid.DrawBackground(const ACanvas: ISkCanvas);
var
  LPaint: ISkPaint;
  i: Integer;
begin
  // Black background and grid
  LPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  LPaint.Color := $FF050505;
  ACanvas.DrawPaint(LPaint);

  LPaint.Color := $0A00FFFF;
  LPaint.Style := TSkPaintStyle.Stroke;
  LPaint.StrokeWidth := 1;

  for i := 0 to Round(Width) do
    if i mod 40 = 0 then ACanvas.DrawLine(PointF(i, 0), PointF(i, Height), LPaint);

  for i := 0 to Round(Height) do
    if i mod 40 = 0 then ACanvas.DrawLine(PointF(0, i), PointF(Width, i), LPaint);

  // Moving scanline
  LPaint.Style := TSkPaintStyle.Fill;
  LPaint.Color := $15FFCC66;
  ACanvas.DrawRect(RectF(0, FScanLineY, Width, FScanLineY + 15), LPaint);
end;

procedure TSkiaLCARSFluid.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
var
  Elem: TLCARSFluidElement;
begin
  // Main render pipeline
  DrawBackground(ACanvas);
  FSchematic.Draw(ACanvas, Width, Height);

  FLock.Acquire;
  try
    for Elem in FElements do
      Elem.Draw(ACanvas, FFont);
  finally
    FLock.Release;
  end;
end;

procedure TSkiaLCARSFluid.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Elem: TLCARSFluidElement;
  P: TPointF;
begin
  // Hover detection
  inherited;
  P := PointF(X, Y);

  FLock.Acquire;
  try
    for Elem in FElements do
      Elem.FIsHovered := Elem.FIsClickable and Elem.ContainsPoint(P);
  finally
    FLock.Release;
  end;
  FNeedsRedraw := True;
end;

procedure TSkiaLCARSFluid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Elem: TLCARSFluidElement;
  P: TPointF;
begin
  // Click detection for UI buttons
  inherited;
  if Button <> TMouseButton.mbLeft then Exit;

  P := PointF(X, Y);

  FLock.Acquire;
  try
    for Elem in FElements do
    begin
      if Elem.FIsClickable and Elem.ContainsPoint(P) then
      begin
        if Assigned(Elem.FOnClick) then
          Elem.FOnClick(Elem);
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
  FNeedsRedraw := True;
end;

procedure TSkiaLCARSFluid.StartThread;
begin
  // Starts the background thread for the render loop
  FThread := TThread.CreateAnonymousThread(
    procedure
    var LastTime, NowTime, DeltaMS: Cardinal;
    begin
      LastTime := TThread.GetTickCount;
      while not TThread.CheckTerminated do
      begin
        NowTime := TThread.GetTickCount;
        DeltaMS := NowTime - LastTime;
        if DeltaMS = 0 then DeltaMS := 1;
        LastTime := NowTime;

        if FActive then
        begin
          DoUpdate(DeltaMS / 1000);
          SafeInvalidate;
        end;

        // Dynamic sleep rate: Less updates when system is idle
        if not FNeedsRedraw and not IsSystemAnimating then
          Sleep(100)
        else
          Sleep(16); // ~60 FPS on activity
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TSkiaLCARSFluid.SafeInvalidate;
begin
  // Thread-safe triggering of a redraw in the main thread
  if csDestroying in ComponentState then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
      begin
        Redraw;
        Repaint;
      end
    end);
end;

procedure TSkiaLCARSFluid.StopThread;
begin
  // Cleanly terminate the thread upon component destruction
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50);
  end;
end;

end.
