unit fwpatcher;

// In-memory firmware "hours + CRC" patcher for AsProgrammer.
//
// After a successful IC read the caller passes the buffer that was just loaded
// into the hex editor. This unit shows a small dialog with the therapy and
// machine hour counters decoded from the image, lets the user change them, and
// patches the buffer in place:
//   * therapy hours  : uint32 LE seconds @ 0x0C..0x0F
//   * machine hours  : uint32 LE seconds @ 0x10..0x1B (written three times)
//   * CRC16-CCITT (FALSE) over 0x00..0x4F @ 0x50..0x51
// No file is read or written here; the caller reloads the editor and the user
// flashes it with the existing "Write IC" button.

{$mode objfpc}{$H+}

interface

function FWPatchFirmwareInMemory(Mem: PByte; Len: Int64): boolean;

implementation

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Graphics, Dialogs;

const
  FW_MIN_SIZE    = $52;  // shortest image with the expected header
  FW_OFF_THERAPY = $0C;  // uint32 LE - therapy seconds
  FW_OFF_MACHINE = $10;  // uint32 LE - machine seconds (written 3x)
  FW_OFF_CRC     = $50;  // uint16 LE - CRC16-CCITT(FALSE) over 0x00..0x4F
  FW_CRC_COVER   = $50;  // number of bytes covered by the checksum
  FW_MAX_HOURS   = 4294967295.0 / 3600.0;

function ReadLE16(p: PByte): Word;
begin
  Result := Word(p[0]) or (Word(p[1]) shl 8);
end;

procedure WriteLE16(p: PByte; v: Word);
begin
  p[0] := v and $FF;
  p[1] := (v shr 8) and $FF;
end;

function ReadLE32(p: PByte): LongWord;
begin
  Result := LongWord(p[0])
         or (LongWord(p[1]) shl 8)
         or (LongWord(p[2]) shl 16)
         or (LongWord(p[3]) shl 24);
end;

procedure WriteLE32(p: PByte; v: LongWord);
begin
  p[0] := v and $FF;
  p[1] := (v shr 8) and $FF;
  p[2] := (v shr 16) and $FF;
  p[3] := (v shr 24) and $FF;
end;

function CRC16CCITTFalse(Buf: PByte; Len: Integer): Word;
var
  i, j: Integer;
  crc: LongWord;
begin
  crc := $FFFF;
  for i := 0 to Len - 1 do
  begin
    crc := crc xor (LongWord(Buf[i]) shl 8);
    for j := 0 to 7 do
    begin
      if (crc and $8000) <> 0 then
        crc := ((crc shl 1) xor $1021) and $FFFF
      else
        crc := (crc shl 1) and $FFFF;
    end;
  end;
  Result := crc and $FFFF;
end;

function FormatHours(h: double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(h, ffFixed, 4, 0, fs);
end;

function ParseHours(const s: string; out h: double): boolean;
var
  t: string;
  fs: TFormatSettings;
begin
  t := StringReplace(Trim(s), ',', '.', [rfReplaceAll]);
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(t, h, fs);
end;

function FWPatchFirmwareInMemory(Mem: PByte; Len: Int64): boolean;
var
  Form: TForm;
  Title, Info: TLabel;
  LblTherapy, LblMachine: TLabel;
  EditTherapy, EditMachine: TEdit;
  LblTherapyOrig, LblMachineOrig: TLabel;
  BtnApply, BtnCancel: TButton;
  therapySec, machineSec: LongWord;
  therapyHrs, machineHrs: double;
  newTherapyHrs, newMachineHrs: double;
  newTherapySec, newMachineSec: LongWord;
  crc: Word;
begin
  Result := False;
  if (Mem = nil) or (Len < FW_MIN_SIZE) then
    Exit;

  therapySec := ReadLE32(Mem + FW_OFF_THERAPY);
  machineSec := ReadLE32(Mem + FW_OFF_MACHINE);
  therapyHrs := therapySec / 3600.0;
  machineHrs := machineSec / 3600.0;

  Form := TForm.CreateNew(nil);
  try
    Form.Caption := 'Firmware Hours & CRC Patcher';
    Form.BorderStyle := bsDialog;
    Form.Position := poMainFormCenter;
    Form.FormStyle := fsStayOnTop;
    Form.ClientWidth := 560;
    Form.ClientHeight := 248;

    Title := TLabel.Create(Form);
    Title.Parent := Form;
    Title.Caption := 'Patch operating hours (applied to memory, not written yet)';
    Title.Font.Style := [fsBold];
    Title.SetBounds(16, 12, 528, 22);

    Info := TLabel.Create(Form);
    Info.Parent := Form;
    Info.Caption := 'CRC16-CCITT(FALSE) recalculated automatically - press Write IC.';
    Info.SetBounds(16, 38, 528, 18);

    LblTherapy := TLabel.Create(Form);
    LblTherapy.Parent := Form;
    LblTherapy.Caption := 'Therapy:';
    LblTherapy.SetBounds(16, 70, 120, 24);

    EditTherapy := TEdit.Create(Form);
    EditTherapy.Parent := Form;
    EditTherapy.Text := FormatHours(therapyHrs);
    EditTherapy.SetBounds(140, 68, 150, 26);

    LblTherapyOrig := TLabel.Create(Form);
    LblTherapyOrig.Parent := Form;
    LblTherapyOrig.Caption := 'Original: ' + FormatHours(therapyHrs) +
      ' hrs (' + IntToStr(Int64(therapySec)) + ' s)';
    LblTherapyOrig.Font.Color := clGray;
    LblTherapyOrig.SetBounds(16, 100, 528, 20);

    LblMachine := TLabel.Create(Form);
    LblMachine.Parent := Form;
    LblMachine.Caption := 'Machine:';
    LblMachine.SetBounds(16, 130, 120, 24);

    EditMachine := TEdit.Create(Form);
    EditMachine.Parent := Form;
    EditMachine.Text := FormatHours(machineHrs);
    EditMachine.SetBounds(140, 128, 150, 26);

    LblMachineOrig := TLabel.Create(Form);
    LblMachineOrig.Parent := Form;
    LblMachineOrig.Caption := 'Original: ' + FormatHours(machineHrs) +
      ' hrs (' + IntToStr(Int64(machineSec)) + ' s)';
    LblMachineOrig.Font.Color := clGray;
    LblMachineOrig.SetBounds(16, 160, 528, 20);

    BtnApply := TButton.Create(Form);
    BtnApply.Parent := Form;
    BtnApply.Caption := 'Apply';
    BtnApply.Default := True;
    BtnApply.ModalResult := mrOk;
    BtnApply.SetBounds(356, 200, 92, 32);

    BtnCancel := TButton.Create(Form);
    BtnCancel.Parent := Form;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.SetBounds(452, 200, 92, 32);

    while True do
    begin
      if Form.ShowModal <> mrOk then
        Exit;

      if (not ParseHours(EditTherapy.Text, newTherapyHrs)) or
         (not ParseHours(EditMachine.Text, newMachineHrs)) then
      begin
        MessageDlg('Firmware Patcher', 'Hours must be valid numbers.', mtError, [mbOK], 0);
        Continue;
      end;

      if (newTherapyHrs < 0) or (newTherapyHrs > FW_MAX_HOURS) or
         (newMachineHrs < 0) or (newMachineHrs > FW_MAX_HOURS) then
      begin
        MessageDlg('Firmware Patcher',
          'Hours must be between 0 and ' + FormatHours(FW_MAX_HOURS) + '.',
          mtError, [mbOK], 0);
        Continue;
      end;

      Break;
    end;

    newTherapySec := Round(newTherapyHrs * 3600);
    newMachineSec := Round(newMachineHrs * 3600);

    WriteLE32(Mem + FW_OFF_THERAPY, newTherapySec);
    WriteLE32(Mem + FW_OFF_MACHINE, newMachineSec);
    WriteLE32(Mem + FW_OFF_MACHINE + 4, newMachineSec);
    WriteLE32(Mem + FW_OFF_MACHINE + 8, newMachineSec);

    crc := CRC16CCITTFalse(Mem, FW_CRC_COVER);
    WriteLE16(Mem + FW_OFF_CRC, crc);

    Result := True;
  finally
    Form.Free;
  end;
end;

end.
