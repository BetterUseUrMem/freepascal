{
    This file is part of the Free Pascal Test Suite
    Copyright (c) 1999-2000 by Pierre Muller

    Unit to redirect output and error to files

    Adapted from code donated to public domain by Schwartz Gabriel 20/03/1993

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
Unit FpRedir;
Interface

{$R-}
{$ifndef Linux}
{$ifndef Unix}
  {$S-}
{$endif}
{$endif}

{$ifdef TP}
{$define implemented}
{$endif TP}
{$ifdef Go32v2}
{$define implemented}
{$endif}
{$ifdef OS2}
{$define shell_implemented}
{$endif}
{$ifdef Windows}
{$define implemented}
{$endif}
{$ifdef linux}
{$define implemented}
{$endif}
{$ifdef BSD}
{$define implemented}
{$endif}
{$ifdef netwlibc}
{$define implemented}
{$endif}
{$ifdef netware_clib}
{$define implemented}
{$endif}

{ be sure msdos is not set for FPC compiler }
{$ifdef FPC}
{$UnDef MsDos}
{$endif FPC}

Var
  IOStatus                   : Integer;
  RedirErrorOut,RedirErrorIn,
  RedirErrorError            : Integer;
  ExecuteResult              : Word;

{------------------------------------------------------------------------------}
procedure InitRedir;
function ExecuteRedir (Const ProgName, ComLine, RedirStdIn, RedirStdOut, RedirStdErr : String) : boolean;
procedure DosExecute(ProgName, ComLine : String);

function  ChangeRedirOut(Const Redir : String; AppendToFile : Boolean) : Boolean;
procedure RestoreRedirOut;
procedure DisableRedirOut;
procedure EnableRedirOut;
function  ChangeRedirIn(Const Redir : String) : Boolean;
procedure RestoreRedirIn;
procedure DisableRedirIn;
procedure EnableRedirIn;
function  ChangeRedirError(Const Redir : String; AppendToFile : Boolean) : Boolean;
procedure RestoreRedirError;
procedure DisableRedirError;
procedure EnableRedirError;
procedure RedirDisableAll;
procedure RedirEnableAll;

{ unused in UNIX }
const
  UseComSpec : boolean = true;

Implementation

Uses
{$ifdef go32v2}
  go32,
{$endif go32v2}
{$ifdef netwlibc}
  Libc,
{$endif netwlibc}
{$ifdef netware_clib}
  nwserv,
{$endif netware_clib}
{$ifdef Windows}
  windows,
{$endif Windows}
{$ifdef unix}
  {$ifdef ver1_0}
    linux,
  {$else}
    baseunix,
    unix,
  {$endif}
{$endif unix}
  dos;

Const
{$ifdef UNIX}
  DirSep='/';
  listsep = [';',':'];
  exeext = '';
{$else UNIX}
  DirSep='\';
  listsep = [';'];
  exeext = '.exe';
{$endif UNIX}


var
  FIN,FOUT,FERR     : ^File;
  RedirChangedOut,
  RedirChangedIn    : Boolean;
  RedirChangedError : Boolean;
  InRedirDisabled,OutRedirDisabled,ErrorRedirDisabled : Boolean;


{*****************************************************************************
                                     Helpers
*****************************************************************************}

function FixPath(const s:string):string;
var
  i : longint;
begin
  { Fix separator }
  for i:=1 to length(s) do
   if s[i] in ['/','\'] then
    fixpath[i]:=DirSep
   else
    fixpath[i]:=s[i];
  fixpath[0]:=s[0];
end;


    function maybequoted(const s:string):string;
      var
        s1 : string;
        i  : integer;
        quoted : boolean;
      begin
        quoted:=false;
        s1:='"';
        for i:=1 to length(s) do
         begin
           case s[i] of
             '"' :
               begin
                 quoted:=true;
                 s1:=s1+'\"';
               end;
             ' ',
             #128..#255 :
               begin
                 quoted:=true;
                 s1:=s1+s[i];
               end;
             else
               s1:=s1+s[i];
           end;
         end;
        if quoted then
          maybequoted:=s1+'"'
        else
          maybequoted:=s;
      end;


{*****************************************************************************
                                     Dos
*****************************************************************************}

{$ifdef implemented}

{$ifdef TP}

{$ifndef Windows}
const
  UnusedHandle    = -1;
  StdInputHandle  = 0;
  StdOutputHandle = 1;
  StdErrorHandle  = 2;
{$endif Windows}

Type
  PtrRec = packed record
             Ofs, Seg : Word;
           end;

  PHandles = ^THandles;
  THandles = Array [Byte] of Byte;

  PWord = ^Word;

Var
  MinBlockSize : Word;
  MyBlockSize  : Word;
  Handles      : PHandles;
  PrefSeg      : Word;
  OldHandleOut,OldHandleIn,OldHandleError    : Byte;
{$endif TP}

var
  TempHOut, TempHIn,TempHError : longint;

{
For linux the following functions exist
Function  fpdup(oldfile:longint;var newfile:longint):Boolean;
Function  fpdup2(oldfile,newfile:longint):Boolean;
Function  fpClose(fd:longint):boolean;
}
{$ifdef go32v2}

function dup(fh : longint;var nh : longint) : boolean;
var
  Regs : Registers;
begin
    Regs.ah:=$45;
    Regs.bx:=fh;
    MsDos (Regs);
    dup:=true;
    If (Regs.Flags and fCarry)=0 then
      nh:=Regs.Ax
    else
      dup:=false;
end;

function dup2(fh,nh : longint) : boolean;
var
  Regs : Registers;
begin
    dup2:=true;
    If fh=nh then
      exit;
    Regs.ah:=$46;
    Regs.bx:=fh;
    Regs.cx:=nh;
    MsDos (Regs);
    If (Regs.Flags and fCarry)<>0 then
      dup2:=false;
end;

{$ifndef ver1_0}
function fpdup(fh:longint):longint;
begin
  if not dup(fh,fpdup) then
   fpdup:=-1;
end;

function fpdup2(fh,nh:longint):longint;
begin
  if dup2(fh,nh) then
   fpdup2:=0
  else
   fpdup2:=-1;
end;
{$endif ver1_0}


Function {$ifdef ver1_0}fdclose{$else}fpclose{$endif} (Handle : Longint) : boolean;
var Regs: registers;
begin
  Regs.Eax := $3e00;
  Regs.Ebx := Handle;
  MsDos(Regs);
  {$ifdef ver1_0}fdclose{$else}fpclose{$endif}:=(Regs.Flags and fCarry)=0;
end;

{$endif def go32v2}

{$ifdef Windows}
Function {$ifdef ver1_0}fdclose{$else}fpclose{$endif} (Handle : Longint) : boolean;
begin
  { Do we need this ?? }
  {$ifdef ver1_0}fdclose{$else}fpclose{$endif}:=true;
end;
{$endif}

{$ifdef os2}
Function {$ifdef ver1_0}fdclose{$else}fpclose{$endif} (Handle : Longint) : boolean;
begin
  { Do we need this ?? }
  {$ifdef ver1_0}fdclose{$else}fpclose{$endif}:=true;
end;
{$endif}

{$ifdef TP}
Function {$ifdef ver1_0}fdclose{$else}fpclose{$endif} (Handle : Longint) : boolean;
begin
  { if executed as under GO32 this hangs the DOS-prompt }
  {$ifdef ver1_0}fdclose{$else}fpclose{$endif}:=true;
end;

{$endif}

{$I-}
function FileExist(const FileName : PathStr) : Boolean;
var
  f : file;
  Attr : word;
begin
  Assign(f, FileName);
  GetFAttr(f, Attr);
  FileExist := DosError = 0;
end;

function CompleteDir(const Path: string): string;
begin
  { keep c: untouched PM }
  if (Path<>'') and (Path[Length(Path)]<>DirSep) and
     (Path[Length(Path)]<>':') then
   CompleteDir:=Path+DirSep
  else
   CompleteDir:=Path;
end;


function LocateExeFile(var FileName:string): boolean;
var
  dir,s,d,n,e : string;
  i : longint;
begin
  LocateExeFile:=False;
  if FileExist(FileName) then
    begin
      LocateExeFile:=true;
      Exit;
    end;

  Fsplit(Filename,d,n,e);

  if (e='') and FileExist(FileName+exeext) then
    begin
      FileName:=FileName+exeext;
      LocateExeFile:=true;
      Exit;
    end;

  S:=GetEnv('PATH');
  While Length(S)>0 do
    begin
      i:=1;
      While (i<=Length(S)) and not (S[i] in ListSep) do
        Inc(i);
      Dir:=CompleteDir(Copy(S,1,i-1));
      if i<Length(S) then
        Delete(S,1,i)
      else
        S:='';
      if FileExist(Dir+FileName) then
        Begin
           FileName:=Dir+FileName;
           LocateExeFile:=true;
           Exit;
        End;
   end;
end;


{............................................................................}

function ChangeRedirOut(Const Redir : String; AppendToFile : Boolean) : Boolean;
  begin
    ChangeRedirOut:=False;
    If Redir = '' then Exit;
    Assign (FOUT^, Redir);
    If AppendToFile and FileExist(Redir) then
      Begin
      Reset(FOUT^,1);
      Seek(FOUT^,FileSize(FOUT^));
      End else Rewrite (FOUT^);

    RedirErrorOut:=IOResult;
    IOStatus:=RedirErrorOut;
    If IOStatus <> 0 then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    OldHandleOut:=Handles^[StdOutputHandle];
    Handles^[StdOutputHandle]:=Handles^[FileRec (FOUT^).Handle];
    ChangeRedirOut:=True;
    OutRedirDisabled:=False;
{$else}
{$ifdef Windows}
    if SetStdHandle(Std_Output_Handle,FileRec(FOUT^).Handle) then
{$else not Windows}
    {$ifdef ver1_0}
    dup(StdOutputHandle,TempHOut);
    dup2(FileRec(FOUT^).Handle,StdOutputHandle);
    {$else}
    TempHOut:=fpdup(StdOutputHandle);
    fpdup2(FileRec(FOUT^).Handle,StdOutputHandle);
    {$endif}
    if (TempHOut<>UnusedHandle) and
       (StdOutputHandle<>UnusedHandle) then
{$endif not Windows}
      begin
         ChangeRedirOut:=True;
         OutRedirDisabled:=False;
      end;
{$endif def FPC}
     RedirChangedOut:=True;
  end;

function ChangeRedirIn(Const Redir : String) : Boolean;
  begin
    ChangeRedirIn:=False;
    If Redir = '' then Exit;
    Assign (FIN^, Redir);
    Reset(FIN^,1);

    RedirErrorIn:=IOResult;
    IOStatus:=RedirErrorIn;
    If IOStatus <> 0 then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    OldHandleIn:=Handles^[StdInputHandle];
    Handles^[StdInputHandle]:=Handles^[FileRec (FIN^).Handle];
    ChangeRedirIn:=True;
    InRedirDisabled:=False;
{$else}
{$ifdef Windows}
    if SetStdHandle(Std_Input_Handle,FileRec(FIN^).Handle) then
{$else not Windows}
    {$ifdef ver1_0}
    dup(StdInputHandle,TempHIn);
    dup2(FileRec(FIn^).Handle,StdInputHandle);
    {$else}
    TempHIn:=fpdup(StdInputHandle);
    fpdup2(FileRec(FIn^).Handle,StdInputHandle);
    {$endif}
    if (TempHIn<>UnusedHandle) and
       (StdInputHandle<>UnusedHandle) then
{$endif not Windows}
      begin
         ChangeRedirIn:=True;
         InRedirDisabled:=False;
      end;
{$endif def FPC}
     RedirChangedIn:=True;
  end;

function ChangeRedirError(Const Redir : String; AppendToFile : Boolean) : Boolean;
  begin
    ChangeRedirError:=False;
    If Redir = '' then Exit;
    Assign (FERR^, Redir);
    If AppendToFile and FileExist(Redir) then
      Begin
      Reset(FERR^,1);
      Seek(FERR^,FileSize(FERR^));
      End else Rewrite (FERR^);

    RedirErrorError:=IOResult;
    IOStatus:=RedirErrorError;
    If IOStatus <> 0 then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    OldHandleError:=Handles^[StdErrorHandle];
    Handles^[StdErrorHandle]:=Handles^[FileRec (FERR^).Handle];
    ChangeRedirError:=True;
    ErrorRedirDisabled:=False;
{$else}
{$ifdef Windows}
    if SetStdHandle(Std_Error_Handle,FileRec(FERR^).Handle) then
{$else not Windows}
    {$ifdef ver1_0}
    dup(StdErrorHandle,TempHError);
    dup2(FileRec(FERR^).Handle,StdErrorHandle);
    {$else}
    TempHError:=fpdup(StdErrorHandle);
    fpdup2(FileRec(FERR^).Handle,StdErrorHandle);
    {$endif}
    if (TempHError<>UnusedHandle) and
       (StdErrorHandle<>UnusedHandle) then
{$endif not Windows}
      begin
         ChangeRedirError:=True;
         ErrorRedirDisabled:=False;
      end;
{$endif}
     RedirChangedError:=True;
  end;


{$IfDef MsDos}
{Set HeapEnd Pointer to Current Used Heapsize}
Procedure SmallHeap;assembler;
asm
                mov     bx,word ptr HeapPtr
                shr     bx,4
                inc     bx
                add     bx,word ptr HeapPtr+2
                mov     ax,PrefixSeg
                sub     bx,ax
                mov     es,ax
                mov     ah,4ah
                int     21h
end;



{Set HeapEnd Pointer to Full Heapsize}
Procedure FullHeap;assembler;
asm
                mov     bx,word ptr HeapEnd
                shr     bx,4
                inc     bx
                add     bx,word ptr HeapEnd+2
                mov     ax,PrefixSeg
                sub     bx,ax
                mov     es,ax
                mov     ah,4ah
                int     21h
end;

{$EndIf MsDos}


  procedure RestoreRedirOut;

  begin
    If not RedirChangedOut then Exit;
{$ifndef FPC}
    Handles^[StdOutputHandle]:=OldHandleOut;
    OldHandleOut:=StdOutputHandle;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Output_Handle,StdOutputHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHOut,StdOutputHandle);
{$endif not Windows}
{$endif FPC}
    Close (FOUT^);
    {$ifdef ver1_0}fdclose{$else}fpclose{$endif}(TempHOut);
    RedirChangedOut:=false;
  end;

  {............................................................................}


  procedure RestoreRedirIn;
  begin
    If not RedirChangedIn then Exit;
{$ifndef FPC}
    Handles^[StdInputHandle]:=OldHandleIn;
    OldHandleIn:=StdInputHandle;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Input_Handle,StdInputHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHIn,StdInputHandle);
{$endif not Windows}
{$endif}
    Close (FIn^);
    {$ifdef ver1_0}fdclose{$else}fpclose{$endif}(TempHIn);
    RedirChangedIn:=false;
  end;

  {............................................................................}

  procedure DisableRedirIn;

  begin
    If not RedirChangedIn then Exit;
    If InRedirDisabled then Exit;
{$ifndef FPC}
    Handles^[StdInputHandle]:=OldHandleIn;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Input_Handle,StdInputHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHIn,StdInputHandle);
{$endif not Windows}
{$endif}
    InRedirDisabled:=True;
  end;

  {............................................................................}

  procedure EnableRedirIn;

  begin
    If not RedirChangedIn then Exit;
    If not InRedirDisabled then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    Handles^[StdInputHandle]:=Handles^[FileRec (FIn^).Handle];
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Input_Handle,FileRec(FIn^).Handle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(FileRec(FIn^).Handle,StdInputHandle);
{$endif not Windows}
{$endif}
    InRedirDisabled:=False;
  end;

  {............................................................................}

  procedure DisableRedirOut;

  begin
    If not RedirChangedOut then Exit;
    If OutRedirDisabled then Exit;
{$ifndef FPC}
    Handles^[StdOutputHandle]:=OldHandleOut;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Output_Handle,StdOutputHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHOut,StdOutputHandle);
{$endif not Windows}
{$endif}
    OutRedirDisabled:=True;
  end;

  {............................................................................}

  procedure EnableRedirOut;

  begin
    If not RedirChangedOut then Exit;
    If not OutRedirDisabled then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    Handles^[StdOutputHandle]:=Handles^[FileRec (FOut^).Handle];
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Output_Handle,FileRec(FOut^).Handle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(FileRec(FOut^).Handle,StdOutputHandle);
{$endif not Windows}
{$endif}
    OutRedirDisabled:=False;
  end;

  {............................................................................}

  procedure RestoreRedirError;

  begin
    If not RedirChangedError then Exit;
{$ifndef FPC}
    Handles^[StdErrorHandle]:=OldHandleError;
    OldHandleError:=StdErrorHandle;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Error_Handle,StdErrorHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHError,StdErrorHandle);
{$endif not Windows}
{$endif}
    Close (FERR^);
    {$ifdef ver1_0}fdclose{$else}fpclose{$endif}(TempHError);
    RedirChangedError:=false;
  end;

  {............................................................................}

  procedure DisableRedirError;

  begin
    If not RedirChangedError then Exit;
    If ErrorRedirDisabled then Exit;
{$ifndef FPC}
    Handles^[StdErrorHandle]:=OldHandleError;
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Error_Handle,StdErrorHandle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(TempHError,StdErrorHandle);
{$endif not Windows}
{$endif}
    ErrorRedirDisabled:=True;
  end;

  {............................................................................}

  procedure EnableRedirError;

  begin
    If not RedirChangedError then Exit;
    If not ErrorRedirDisabled then Exit;
{$ifndef FPC}
    Handles:=Ptr (prefseg, PWord (Ptr (prefseg, $34))^);
    Handles^[StdErrorHandle]:=Handles^[FileRec (FErr^).Handle];
{$else}
{$ifdef Windows}
    SetStdHandle(Std_Error_Handle,FileRec(FErr^).Handle);
{$else not Windows}
    {$ifdef ver1_0}dup2{$else}fpdup2{$endif}(FileRec(FERR^).Handle,StdErrorHandle);
{$endif not Windows}
{$endif}
    ErrorRedirDisabled:=False;
  end;

{............................................................................}

function ExecuteRedir (Const ProgName, ComLine, RedirStdIn, RedirStdOut, RedirStdErr : String) : boolean;
{$ifdef Windows}
var
  mode : word;
{$endif Windows}
Begin
  RedirErrorOut:=0; RedirErrorIn:=0; RedirErrorError:=0;
  ExecuteResult:=0;
  IOStatus:=0;
  if RedirStdIn<>'' then
    ChangeRedirIn(RedirStdIn);
  if RedirStdOut<>'' then
    ChangeRedirOut(RedirStdOut,false);
  if RedirStdErr<>'stderr' then
    ChangeRedirError(RedirStdErr,false);
  DosExecute(ProgName,ComLine);
  RestoreRedirOut;
  RestoreRedirIn;
  RestoreRedirError;
  ExecuteRedir:=(IOStatus=0) and (RedirErrorOut=0) and
                (RedirErrorIn=0) and (RedirErrorError=0) and
                (ExecuteResult=0);
{$ifdef Windows}
  // reenable mouse events
  GetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), @mode);
  mode:=mode or ENABLE_MOUSE_INPUT;
  SetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), mode);
{$endif Windows}
End;

{............................................................................}

procedure RedirDisableAll;
  begin
    If RedirChangedIn and not InRedirDisabled then
      DisableRedirIn;
    If RedirChangedOut and not OutRedirDisabled then
      DisableRedirOut;
    If RedirChangedError and not ErrorRedirDisabled then
      DisableRedirError;
  end;

{............................................................................}

procedure RedirEnableAll;
  begin
    If RedirChangedIn and InRedirDisabled then
      EnableRedirIn;
    If RedirChangedOut and OutRedirDisabled then
      EnableRedirOut;
    If RedirChangedError and ErrorRedirDisabled then
      EnableRedirError;
  end;


procedure InitRedir;
begin
{$ifndef FPC}
  PrefSeg:=PrefixSeg;
{$endif FPC}
end;

{$else not  implemented}


{*****************************************************************************
                                 Fake
*****************************************************************************}

{$IFDEF SHELL_IMPLEMENTED}
{$I-}
function FileExist(const FileName : PathStr) : Boolean;
var
  f : file;
  Attr : word;
begin
  Assign(f, FileName);
  GetFAttr(f, Attr);
  FileExist := DosError = 0;
end;

function CompleteDir(const Path: string): string;
begin
  { keep c: untouched PM }
  if (Path<>'') and (Path[Length(Path)]<>DirSep) and
     (Path[Length(Path)]<>':') then
   CompleteDir:=Path+DirSep
  else
   CompleteDir:=Path;
end;


function LocateExeFile(var FileName:string): boolean;
var
  dir,s,d,n,e : string;
  i : longint;
begin
  LocateExeFile:=False;
  if FileExist(FileName) then
    begin
      LocateExeFile:=true;
      Exit;
    end;

  Fsplit(Filename,d,n,e);

  if (e='') and FileExist(FileName+exeext) then
    begin
      FileName:=FileName+exeext;
      LocateExeFile:=true;
      Exit;
    end;

  S:=GetEnv('PATH');
  While Length(S)>0 do
    begin
      i:=1;
      While (i<=Length(S)) and not (S[i] in ListSep) do
        Inc(i);
      Dir:=CompleteDir(Copy(S,1,i-1));
      if i<Length(S) then
        Delete(S,1,i)
      else
        S:='';
      if FileExist(Dir+FileName) then
        Begin
           FileName:=Dir+FileName;
           LocateExeFile:=true;
           Exit;
        End;
   end;
end;

function ExecuteRedir (Const ProgName, ComLine, RedirStdIn, RedirStdOut, RedirStdErr: String): boolean;
var
 CmdLine2: string;
begin
 CmdLine2 := ComLine;
 if RedirStdIn <> '' then CmdLine2 := CmdLine2 + ' < ' + RedirStdIn;
 if RedirStdOut <> '' then CmdLine2 := CmdLine2 + ' > ' + RedirStdOut;
 if RedirStdErr <> '' then
 begin
  if RedirStdErr = RedirStdOut
          then CmdLine2 := CmdLine2 + ' 2>&1'
                              else CmdLine2 := CmdLine2 + ' 2> ' + RedirStdErr;
 end;
 DosExecute (ProgName, CmdLine2);
 ExecuteRedir := true;
end;
{$ELSE SHELL_IMPLEMENTED}
function ExecuteRedir (Const ProgName, ComLine, RedirStdIn, RedirStdOut, RedirStdErr : String) : boolean;
begin
  ExecuteRedir:=false;
end;
{$ENDIF SHELL_IMPLEMENTED}

function  ChangeRedirOut(Const Redir : String; AppendToFile : Boolean) : Boolean;
begin
  ChangeRedirOut:=false;
end;


procedure RestoreRedirOut;
begin
end;


procedure DisableRedirOut;
begin
end;


procedure EnableRedirOut;
begin
end;


function  ChangeRedirIn(Const Redir : String) : Boolean;
begin
  ChangeRedirIn:=false;
end;


procedure RestoreRedirIn;
begin
end;


procedure DisableRedirIn;
begin
end;


procedure EnableRedirIn;
begin
end;


function  ChangeRedirError(Const Redir : String; AppendToFile : Boolean) : Boolean;
begin
  ChangeRedirError:=false;
end;


procedure RestoreRedirError;
begin
end;


procedure DisableRedirError;
begin
end;


procedure EnableRedirError;
begin
end;


procedure RedirDisableAll;
begin
end;


procedure RedirEnableAll;
begin
end;


procedure InitRedir;
begin
end;
{$endif not implemented}


{............................................................................}

  procedure DosExecute(ProgName, ComLine : String);
{$ifdef Windows}
    var
      StoreInherit : BOOL;
{$endif Windows}

  Begin
{$IfDef MsDos}
  SmallHeap;
{$EndIf MsDos}
    SwapVectors;
    { Must use shell() for linux for the wildcard expansion (PFV) }
{$ifdef UNIX}
    IOStatus:=0;
    ExecuteResult:=Shell(MaybeQuoted(FixPath(Progname))+' '+Comline);
  {$ifdef ver1_0}
    { Signal that causes the stop of the shell }
    IOStatus:=ExecuteResult and $7F;
    { Exit Code seems to be in the second byte,
      is this also true for BSD ??
      $80 bit is a CoreFlag apparently }
    ExecuteResult:=(ExecuteResult and $ff00) shr 8;
  {$else}
    if ExecuteResult<0 then
      begin
        IOStatus:=(-ExecuteResult) and $7f;
        ExecuteResult:=((-ExecuteResult) and $ff00) shr 8;
      end;
  {$endif}
{$else}
  {$ifdef Windows}
    StoreInherit:=ExecInheritsHandles;
    ExecInheritsHandles:=true;
  {$endif Windows}
    DosError:=0;
    If UseComSpec then
      Dos.Exec (Getenv('COMSPEC'),'/C '+MaybeQuoted(FixPath(progname))+' '+Comline)
    else
      begin
        if LocateExeFile(progname) then
          Dos.Exec(ProgName,Comline)
        else
          DosError:=2;
      end;
  {$ifdef Windows}
    ExecInheritsHandles:=StoreInherit;
  {$endif Windows}
    IOStatus:=DosError;
    ExecuteResult:=DosExitCode;
{$endif}
    SwapVectors;
{$ifdef CPU86}
    { reset the FPU }
    {$asmmode att}
    asm
      fninit
    end;
{$endif CPU86}
{$IfDef MsDos}
  Fullheap;
{$EndIf MsDos}
End;

{*****************************************************************************
                                  Initialize
*****************************************************************************}

initialization
  New(FIn); New(FOut); New(FErr);

finalization
  Dispose(FIn); Dispose(FOut); Dispose(FErr);
End.
