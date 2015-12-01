{ *************************************************************************** }
{                          Delphi Auxiliary Toolkit                           }
{                                                                             }
{   ModuleName  :   ATLogger                                                  }
{   Author      :   ZY                                                        }
{   EMail       :   zylove619@hotmail.com                                     }
{   Description :   ATLogger provides a very lightweight logging for          }
{                   delphi based applications, it is simple, efficient        }
{                   and flexible.                                             }
{                                                                             }
{ *************************************************************************** }

(* ***** BEGIN LICENSE BLOCK *****
 *
 * The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is ATLogger.
 * Unit owner : ZY (zylove619@hotmail.com) All rights reserved.
 *
 * ***** END LICENSE BLOCK ***** *)

(*

  Change log:
  
  Version 1.001 by ZY:
    (2014.09.10) + First version created.
                 + Added a simple logger for debugging.
                 + Provided an asynchronous logging.
                 + Added a file logger.

  Version 1.002 by ZY:
    (2014.10.01) + Added a log header to the logger file.
    (2014.12.01) + Support static file name for file logger.

  Version 1.003 by ZY:
    (2015.03.11) + Added a log file cleaner.
    (2015.03.16) * Refactored.
    (2015.03.26) + Added TATTextReadWrapper and TATTextReadWrapper.
    (2015.04.20) + Added TATCSVLogFormater.

  Version 1.004 by ZY:
    (2015.05.20) + Added a log instance counter, the log instances
                   will be limited to this value now.
                 + Added a log single file max size var.
                 * Some classes refactored.

  Version 1.005 by ZY:
    (2015.09.01) + Added OS info to the file logger header.
                 + Fixed the cleaner that cannt clear the empty root dir.

*)

unit ATLogger;

{$I AT.inc}
{$WARN SYMBOL_PLATFORM OFF}

interface

{$DEFINE WAIT_FOR_FINISHED_WHEN_TERMINATED}

uses

  Classes, SyncObjs, StrUtils
{$IFDEF DXEAndUp}
  , DateUtils
{$ENDIF}
{$IFDEF MSWINDOWS}
  {$IFDEF HAS_UNIT_SCOPE}
  , Winapi.Windows, System.Win.Registry, Vcl.Forms
  {$ELSE}
  , Windows, Registry, Forms
  {$ENDIF}
{$ELSE}
  , FMX.Forms
{$ENDIF}
  , SysUtils
{$IFDEF TLIST_DEPRECATED}
  , System.Generics.Collections
{$ENDIF}
{$IFDEF HAS_IOUTILS}
  , System.IOUtils
{$ENDIF}
{$IFDEF ANDROID}
  , Androidapi.Log
{$ENDIF}
{$IFDEF IOS}
  , iOSApi.Foundation
{$ENDIF}
{$IFDEF MACOS}
  , Macapi.ObjectiveC
{$ENDIF}
;

const

  ATLoggerVersion = '1.005';

type

  TATLogLevel = (llAll, llTrace, llDebug, llInfo, llWarn, llError, llFatal, llOff);

const

  LOG_DEFAULT_LEVEL = llDebug;

  LOG_LEVEL_CAPTIONS: array[TATLogLevel] of string =
    ('[All]', '[Trace]', '[Debug]', '[Info]', '[Warn]', '[Error]', '[Fatal]', '[Off]');

type

  ELogException = class(Exception);
  ELogTooManyInstances = class(ELogException);

{$IFDEF HAS_ANONYMOUSMETHOD}
  TATLogFileNameFunc  = reference to function: string;
  TATLogFileFoundFunc = reference to function(const AFileName: string): Boolean;
{$ELSE}
  TATLogFileNameFunc  = function: string;
  TATLogFileFoundFunc = function(const AFileName: string): Boolean;
{$ENDIF}

  TATCustomLogObject = class(TInterfacedObject);

{ LogElement }

  PATLogElement = ^TATLogElement;
  TATLogElement = record
    Log: string;
    LogTriggerTime: TDateTime;
    LogLevel: TATLogLevel;
  end;

{ LogFormater }

  IATLogFormater = interface
    ['{BF31162D-4408-496B-B680-E616BBF97DA3}']
    function LogFormat(const ALogElement: PATLogElement): string;
  end;

  TATCustomLogFormater = class(TATCustomLogObject, IATLogFormater)
  private
    FFormatSettings: TFormatSettings;
    FDelimiter: string;
    FDateTimeFormat: string;
    FTimeZone: string;
  protected
    function LogFormat(const ALogElement: PATLogElement): string; virtual; abstract;
  public
    constructor Create; virtual;
    property FormatSettings: TFormatSettings read FFormatSettings;
    property Delimiter: string read FDelimiter write FDelimiter;
    property DateTimeFormat: string read FDateTimeFormat write FDateTimeFormat;
    property TimeZone: string read FTimeZone; 
  end;

  TATDefaultLogFormater = class(TATCustomLogFormater)
  protected
    function LogFormat(const ALogElement: PATLogElement): string; override;
  end;

  TATCSVLogFormater = class(TATDefaultLogFormater)
  public
    constructor Create; override;
  end;

{ LogOutputter }

  IATLogOutputter = interface
    ['{AE122257-7EBF-47EB-8B70-ACA3E5C6FAFA}']
    procedure Output(const ALog: string; const ALogLevel: TATLogLevel);
  end;

  TATCustomLogOutputter = class(TATCustomLogObject, IATLogOutputter)
  private
    FLogFormater: IATLogFormater;
  protected
    procedure Output(const ALog: string; const ALogLevel: TATLogLevel); virtual; abstract;
    property LogFormater: IATLogFormater read FLogFormater;
  public
    constructor Create(const ALogFormater: IATLogFormater); virtual;
  end;

{ LogElementList }

  TATLogElementList = class({$IFDEF TLIST_DEPRECATED}TList<PATLogElement>{$ELSE}TList{$ENDIF})
  private
    function GetElement(AIndex: Integer): PATLogElement;
  public
    destructor Destroy; override;
    procedure CleanAllElements;
    function Add(const ALog: string; const ALogLevel: TATLogLevel): Integer; overload;
    property Elements[AIndex: Integer]: PATLogElement read GetElement; default;
  end;  

  TATCustomLogThread = TThread;

  TATAsyncLogOutputter = class(TATCustomLogOutputter)
  private
    FLogSiblingLists: array[Boolean] of TATLogElementList;
    FConsumerSibling: Boolean;
    FSynchroObject: TSynchroObject;
    FLogOutputWorker: TATCustomLogThread;
    function GetProducer: TATLogElementList;
    function GetConsumer: TATLogElementList;
  protected
    procedure DoAsycLog(const ALogs: TATLogElementList); virtual; abstract;
    function CreateSynchroObject: TSynchroObject; virtual;
    procedure Output(const ALog: string; const ALogLevel: TATLogLevel); override;
    procedure SiblingSwitch;
  {$IFDEF WAIT_FOR_FINISHED_WHEN_TERMINATED}  
    procedure WaitForFinished;
  {$ENDIF}
    procedure Lock;   {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure UnLock; {$IFDEF HAS_INLINE}inline;{$ENDIF}
    property Producer: TATLogElementList read GetProducer;
    property Consumer: TATLogElementList read GetConsumer;
  public
    constructor Create(const ALogFormater: IATLogFormater); override;
    destructor Destroy; override;
  end;

{ Logger }

  IATLogger = interface
    ['{48B0835C-EAE5-4A93-BBEB-89B7AA666992}']
    { Property methods }
    function GetLogLevel: TATLogLevel;
    procedure SetLogLevel(const ALogLevel: TATLogLevel);
    function GetEnabled: Boolean;
    procedure SetEnabled(const Value: Boolean);
    { Methods}
    procedure T(const ATraceStr: string);
    procedure D(const ADebugStr: string);
    procedure I(const AInfoStr : string);
    procedure W(const AWarnStr : string);
    procedure E(const AErrorStr: string);
    procedure F(const AFatalStr: string);
    { Properties }
    property LogLevel: TATLogLevel read GetLogLevel write SetLogLevel;
    property Enabled: Boolean read GetEnabled write SetEnabled;
  end;

{ GetDefaultLogger:
    
   The default logger that uses a default formater and outputter
   for outputting logs via native methods on different platforms.

  Useage:

    // Get the Logger.
    Logger := GetDefaultLogger;

    // Set Logger's Level, otherwise, llDebug is Default.
    Logger.LogLevel := llInfo;

    // Will be executed.
    Logger.I('My Info Strings');

    // Will also be executed.
    Logger.E('My Error Strings');

    // Here, Logger.D will not be executed.
    Logger.D('My Debug Strings');

    // Logging stopped.
    Log.Enabled := False;

    // Do nothing.
    Logger.I('My Info Strings');

    // Logging continued.
    Log.Enabled := True;

    // Will be executed again.
    Logger.I('My Info Strings');

    // The logger will auto destroyed when it no longer be used.

    // NOTE: if you are using ATlogger in a DLL, do not free
    //       any loggers in the finalization which will cause
    //       an infinite loop(the waitfor always return timeout)
    //       , and you should free it manually.
 }
function GetDefaultLogger: IATLogger;

{ NewLogger:

  Create a new logger instance.

  Useage:

  MyLogger := NewLogger(TMyOutputter.Create(TMyLogFormater.Create));

  // Or
  MyLogger := NewLogger(ExistingIMyOutputter);
}
function NewLogger(const AOutputter: IATLogOutputter; const ALevel: TATLogLevel = LOG_DEFAULT_LEVEL): IATLogger;

{ NewFileLogger:
    
  Useage:

    - Simple demo:

      // Use a static file name.
      MyFileLogger := NewFileLogger('C:\MyLogs.log');

      // Output a debug info.
      MyFileLogger.D('Debug info will be written to a file.');
      
      ...
      
    - Write logs to files every day:

      // NOTE: 1. EveryDayLogFileName is called in thread, so CAREFULLY
      //          use the global vars and VCL objects.
      //       2. NEVER use multiple log instances to write to the same
      //          file, it's not safe.
      //       3. If an exception occured inside this function, an empty
      //          string will be returned.

      function EveryDayLogFileName: string;
      begin
        
        // NOTE: FormatDateTime and others similar functions are reading
        //       global formatsettings. so, if your application does not
        //       change these settings for these function calls, then it
        //       is thread safe.

        Result := ExtractFilePath(ParamStr(0)) + 'Logs' + PathDelim +
          FormatDateTime('YYYY-MM-DD', Date()) + '.log';
      end;

      EveryDayLogger := NewFileLogger(EveryDayLogFileName, llTrace);
      EveryDayLogger.T(' The system runs ok now.');
      ...
      
    - Write logs to csv file.

      CSVFileLogger := NewFileLogger(EveryDayLogFileName, TATCSVLogFormater.Create);
      ...
}
function NewFileLogger(ALogFileNameFunc: TATLogFileNameFunc; const ALogFormater: IATLogFormater = nil; ALogLevel: TATLogLevel = LOG_DEFAULT_LEVEL): IATLogger; overload;
function NewFileLogger(const ALogFileName: string = ''; const ALogFormater: IATLogFormater = nil; ALogLevel: TATLogLevel = LOG_DEFAULT_LEVEL): IATLogger; overload;

{ CleanLogFiles:

  Useage:
         
    - Simple delete.

    // Delete all log files from "C:\DebugLogs" and "D:\ErrorLogs".
    CleanLogFiles(['C:\DebugLogs', 'D:\ErrorLogs']);

    - Use LogFileFoundFunc

    // NOTE: If an exception occured inside this function, false
    //       will be returned.
    
    function LogFileNameLen5(const AFileName: string): Boolean;
    begin
      Result := Length( ChangeFileExt(ExtractFileName(AFileName), '') ) = 5;
    end;

    // Delete all log files from "C:\DebugLogs" where the length of
    // the filename is 5.
    CleanLogFiles(['C:\DebugLogs'], LogFileNameLen5);

    // Delete all log files from "C:\DebugLogs" synchronize.
    CleanLogFiles(['C:\DebugLogs'], nil, False);
}
procedure CleanLogFiles(const ALogFileDirs: array of string; ALogFileFoundFunc: TATLogFileFoundFunc = nil;
  ASubDir: Boolean = True; Async: Boolean = True);

implementation

{$IFNDEF RELEASE}
  {.$DEFINE DEBUG_LOG}
{$ENDIF !RELEASE}

resourcestring

  sLogTooManyInstances = 'Too many log instances created, the max count current supported is %d.';

const

  { The max count of the log elements. }
  LOG_MAX_ITEMCOUNT     = 4 * 1024 * 1024;

  { The list's initial capacity. }
  LOG_LIST_IC           = 64 * 1024;

  { The list's capacity shrink upper limit. }
  LOG_LIST_IC_SHRINK    = 4 * LOG_LIST_IC;

  { The max log instance count current supported, if
    you creating more. an exception will be raised. }
  LOG_MAX_INSTANCECOUNT = 20;

var

(* Internal vars *)

  { A singleton logger that use the default log formater. }
  InternalDefaultLogger   : IATLogger;

  { An internal global synchro object. }
  InternalThreadLock      : TSynchroObject;

  { a logger instance counter for internal use. }
  InternalLogInstanceCount: Integer;  

  
(* Internal immutable vars *)

  { Cached OS name. }
  InternalOSName  : string;

  { App name for internal use. }
  InternalAppName : string;

  { Time zone for internal use. }
  InternalTimeZone: string;

  { The DefaultLogFileName(with path) used when you creating
    a log file with a empty name. }
  InternalDefaultLogFileName   : string;

  { Default format settings for internal use. }
  InternalDefaultFormatSettings: TFormatSettings;

function Atomic_Inc(var ATarget: Integer): Integer;
begin
{$IFDEF DXEAndUp}
  Result := TInterlocked.Increment(ATarget);
{$ELSE}
  Result := InterlockedIncrement(ATarget);
{$ENDIF}
end;

function Atomic_Dec(var ATarget: Integer): Integer;
begin
{$IFDEF DXEAndUp}
  Result := TInterlocked.Decrement(ATarget);
{$ELSE}
  Result := InterlockedDecrement(ATarget);
{$ENDIF}
end;

function Atomic_Read(var ATarget: Integer): Integer;
begin
{$IFDEF DXEAndUp}
  Result := TInterlocked.CompareExchange(ATarget, 0, 0);
{$ELSE}
  Result := InterlockedExchangeAdd(@ATarget, 0);
{$ENDIF}
end;

function GetFormatSettings: TFormatSettings;
begin
{$IFDEF DXEAndUp}
  Result := TFormatSettings.Create;
{$ELSE}
  GetLocaleFormatSettings(SysLocale.DefaultLCID, Result);
{$ENDIF}
end;

function GetTimeZone: string;
{$IFNDEF DXEAndUp}
const
  CGMT   = 'GMT';  { Do not localize }
{$IFDEF MSWINDOWS}
  CPlus  = '+';    { Do not localize }
  CMinus = '-';    { Do not localize }
var
  LTimeZone: TTimeZoneInformation;
  LOffset  : Integer;
  LSignChar: Char;
{$ENDIF MSWINDOWS}
{$ENDIF !DXEAndUp}
begin
{$IFDEF DXEAndUp}
  Result := TTimeZone.Local.Abbreviation;
{$ELSE}
  {$IFDEF MSWINDOWS}
  GetTimeZoneInformation(LTimeZone);

  LOffset := LTimeZone.Bias div -60;
  if LOffset > 0 then
    LSignChar := CPlus
  else
    LSignChar := CMinus;

  Result := Format('%s%s%.2d', [CGMT, LSignChar, Abs(LOffset)],
                                InternalDefaultFormatSettings);
  {$ELSE}
  Result := CGMT;
  {$ENDIF}
{$ENDIF}
end;

function GetOSName: string;
const
  CUnknownOsName = 'Unknown OS';

{$IFDEF MSWINDOWS}
  function GetWinOSArchitecture: string;
  const
    CProcessorArchitectureAMD64 = 9;
    CArchitecture32     = '32-bit';
    CArchitecture64     = '64-bit';
    CArchitectureUnknow = 'Unknow-bit';
  var
    LSystemInfo: TSystemInfo;
    LGetNativeSystemInfo: procedure(var lpSystemInformation: TSystemInfo); stdcall;
  begin
    LGetNativeSystemInfo := GetProcAddress(GetModuleHandle(Kernel32), 'GetNativeSystemInfo');
    if Assigned(LGetNativeSystemInfo) then
    begin
      ZeroMemory(@LSystemInfo, SizeOf(LSystemInfo));
      LGetNativeSystemInfo(LSystemInfo);
      if (LSystemInfo.wProcessorArchitecture = CProcessorArchitectureAMD64) then
        Result := CArchitecture64
      else
        Result := CArchitecture32;
    end else
      Result := CArchitectureUnknow;
  end;

  function GetWinOSVersion: string;
  var
    LRegistry: TRegistry;
    LProductName,
    LVersion,
    LCSDVersion: string;
  begin
    LRegistry := TRegistry.Create(KEY_READ);
    LRegistry.RootKey := HKEY_LOCAL_MACHINE;
  
    try
      if LRegistry.OpenKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', False) then
        try
          LProductName := LRegistry.ReadString('ProductName');

          if LRegistry.ValueExists('CurrentMajorVersionNumber') then
            LVersion := Format('%d.%d.%s', [LRegistry.ReadInteger('CurrentMajorVersionNumber'),
                                            LRegistry.ReadInteger('CurrentMinorVersionNumber'),
                                            LRegistry.ReadString ('CurrentBuildNumber')],
                                            InternalDefaultFormatSettings)
          else
            LVersion := Format('%s.%s', [LRegistry.ReadString('CurrentVersion'),
                                         LRegistry.ReadString('CurrentBuildNumber')],
                                         InternalDefaultFormatSettings);

          if LRegistry.ValueExists('CSDVersion') then
          begin
            LCSDVersion := LRegistry.ReadString('CSDVersion');
            if LCSDVersion <> '' then
              LCSDVersion := ' ' + LCSDVersion + ' ';
          end;
          
          Result := Format('%s%s(Version %s, %s)', [LProductName, LCSDVersion,
                                                    LVersion, GetWinOSArchitecture],
                                                    InternalDefaultFormatSettings);
        except
          Result := CUnknownOsName;
        end
      else
        Result := CUnknownOsName;
    finally
      LRegistry.Free;
    end;
  end;
{$ENDIF MSWINDOWS}

begin
{$IFDEF MSWINDOWS}
  Result := GetWinOSVersion;
{$ELSE}
  {$IFDEF HAS_TOSVERSION}
  Result := TOSVersion.ToString;
  {$ELSE}
  Result := CUnknownOsName;
  {$ENDIF}
{$ENDIF}
end;

function GetFileSize(AFileName: string): Int64;
var
  LSR: TSearchRec;
begin
  if FindFirst(AFileName, faAnyFile, LSR) = 0 then
  begin
 {$IFDEF D2006AndUp}
    Result := LSR.Size;
 {$ELSE}
    Result := (Int64(LSR.FindData.nFileSizeHigh) shl 32) + LSR.FindData.nFileSizeLow;
 {$ENDIF}
    FindClose(LSR);
  end else
    Result := -1;
end;

procedure DelDirectory(const ADir: string);
begin
{$IFDEF HAS_IOUTILS}
  System.IOUtils.TDirectory.Delete(ADir);
{$ELSE}
  RemoveDir(ADir);
{$ENDIF}
end;

procedure DelFile(const AFileName: string);
begin
{$IFDEF HAS_IOUTILS}
  System.IOUtils.TFile.Delete(AFileName);
{$ELSE}
  DeleteFile(AFileName);
{$ENDIF}
end;

function GetDefaultLogPath: string;
begin
{$IFDEF MSWINDOWS}
  Result := ExtractFilePath(ParamStr(0));
{$ELSE}
  Result := TPath.GetPublicPath;
{$ENDIF}
  Result := IncludeTrailingPathDelimiter(Result) + 'Logs' + PathDelim;
end;

type

  TATLogIdentifier = class
    class function GetLogIdentifier: string; {$IFDEF HAS_INLINE}inline;{$ENDIF}
    class function IsLogIdentifier(const AStr: string): Boolean; {$IFDEF HAS_INLINE}inline;{$ENDIF}
    class function ContainLogIdentifier(const AStr: string): Boolean; {$IFDEF HAS_INLINE}inline;{$ENDIF}
  end;

  TATDefaultLogOutputter = class(TATAsyncLogOutputter)
  protected
    procedure DoAsycLog(const ALogs: TATLogElementList); override;
  public
    class procedure NativeOutput(const ALog: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
  end;

  TATFileLogOutputter = class(TATAsyncLogOutputter)
  private
    FMaxSingleFileSize: Cardinal;
    procedure SetMaxSingleFileSize(const Value: Cardinal);
  protected
    function GetLogFileName: string; virtual;
    function GetOutputLogFileName: string; virtual;
    procedure DoAsycLog(const ALogs: TATLogElementList); override;
  public
    class function GetLogHeader: string;
    class function IsLogFile(const AFileName: string): Boolean;
    constructor Create(const ALogFormater: IATLogFormater); override;

    { The original output log file name. }
    property LogFileName: string read GetLogFileName;

    { The actual outout log file name. }
    property OutputLogFileName: string read GetOutputLogFileName;

    { The max size of each log file.      
      Note: The Log file size may not equal to this value, as
            it will be checked after the last log buffer flush
            to the file. }
    property MaxSingleFileSize: Cardinal read FMaxSingleFileSize write SetMaxSingleFileSize;
  end;

  TATStaticFileNameLogOutputter = class(TATFileLogOutputter)
  private
    FLogFileName: string;
  protected
    function GetLogFileName: string; override;
  public
    constructor Create(const ALogFormater: IATLogFormater; const ALogFileName: string = ''); reintroduce;
  end;

  TATEventFileNameOutputter = class(TATFileLogOutputter)
  private
    FLogFileNameFunc: TATLogFileNameFunc;
  protected
    function GetLogFileName: string; override;
  public
    constructor Create(const ALogFormater: IATLogFormater; const ALogFileNameFunc: TATLogFileNameFunc); reintroduce;
  end;

{ Log file cleaner }

  TATLogFileCleaner = class(TATCustomLogThread)
  private
    FSearchDirs: array of string;
    FNeedSubDir: Boolean;
    FLogFileFoundFunc: TATLogFileFoundFunc;
  protected
    procedure Execute; override;
    procedure DoFileFound(const AFileName: string); virtual;
    procedure DoDirFound(const ADir: string); virtual;
  public
    constructor Create(const ADirs: array of string; ALogFileFoundFunc: TATLogFileFoundFunc;
      ASubDir: Boolean = True; ACreateSuspended: Boolean = False; AFreeOnTerminate: Boolean = True);
  end;  

{ TATLoggerContext }

  TATLoggerContext = class(TInterfacedObject, IATLogger)
  private
    FLogOutputter: IATLogOutputter;
    FLogLevel: TATLogLevel;
    FEnabled: Boolean;
    procedure DoLog(const ALog: string; const ALogLevel: TATLogLevel); {$IFDEF HAS_INLINE}inline;{$ENDIF}
  public
    constructor Create(const AOutputter: IATLogOutputter; const ALevel: TATLogLevel = LOG_DEFAULT_LEVEL);
    destructor Destroy; override;
    { IATLogger }
    procedure T(const ATraceStr: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure D(const ADebugStr: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure I(const AInfoStr : string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure W(const AWarnStr : string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure E(const AErrorStr: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure F(const AFatalStr: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    function GetLogLevel: TATLogLevel;
    procedure SetLogLevel(const Value: TATLogLevel);
    function GetEnabled: Boolean;
    procedure SetEnabled(const Value: Boolean);
  end;

{ TATLoggerContext }

constructor TATLoggerContext.Create(const AOutputter: IATLogOutputter; const ALevel: TATLogLevel);
begin
  inherited Create;

  Atomic_Inc(InternalLogInstanceCount);

  SetLogLevel(ALevel);
  FEnabled := True;

  FLogOutputter := AOutputter;
end;

procedure TATLoggerContext.D(const ADebugStr: string);
begin
  DoLog(ADebugStr, llDebug);
end;

destructor TATLoggerContext.Destroy;
begin
  { Stop outputting. }
  SetEnabled(False);

  Atomic_Dec(InternalLogInstanceCount);

  FLogOutputter := nil;

  inherited;
end;

procedure TATLoggerContext.DoLog(const ALog: string; const ALogLevel: TATLogLevel);
begin
  if FEnabled and (ALogLevel >= FLogLevel) then
    FLogOutputter.Output(ALog, ALogLevel);
end;

procedure TATLoggerContext.E(const AErrorStr: string);
begin
  DoLog(AErrorStr, llError);
end;

procedure TATLoggerContext.F(const AFatalStr: string);
begin
  DoLog(AFatalStr, llFatal);
end;

function TATLoggerContext.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

function TATLoggerContext.GetLogLevel: TATLogLevel;
begin
  Result := FLogLevel;
end;

procedure TATLoggerContext.I(const AInfoStr: string);
begin
  DoLog(AInfoStr, llInfo);
end;

procedure TATLoggerContext.SetEnabled(const Value: Boolean);
begin
  FEnabled := Value;
end;

procedure TATLoggerContext.SetLogLevel(const Value: TATLogLevel);
begin
{$IFDEF DEBUG_LOG}
  Assert((Value >= Low(TATLogLevel)) and (Value <= High(TATLogLevel)),
    'Invalid LogLevel ' + IntToStr(Ord(Value)));
{$ENDIF}
  FLogLevel := Value;
end;
 
procedure TATLoggerContext.T(const ATraceStr: string);
begin
  DoLog(ATraceStr, llTrace);
end;

procedure TATLoggerContext.W(const AWarnStr: string);
begin
  DoLog(AWarnStr, llWarn);
end;

function GetDefaultLogger: IATLogger;
begin
  InternalThreadLock.Acquire;
  try
    if not Assigned(InternalDefaultLogger) then
      InternalDefaultLogger := NewLogger(TATDefaultLogOutputter.Create(TATDefaultLogFormater.Create));
    Result := InternalDefaultLogger;
  finally
    InternalThreadLock.Release;
  end;
end;

function NewFileLogger(ALogFileNameFunc: TATLogFileNameFunc; const ALogFormater: IATLogFormater; ALogLevel: TATLogLevel): IATLogger;
begin
  Result := NewLogger(TATEventFileNameOutputter.Create(ALogFormater, ALogFileNameFunc) as IATLogOutputter, ALogLevel);
end;

function NewFileLogger(const ALogFileName: string; const ALogFormater: IATLogFormater; ALogLevel: TATLogLevel): IATLogger;
begin
  Result := NewLogger(TATStaticFileNameLogOutputter.Create(ALogFormater, ALogFileName) as IATLogOutputter, ALogLevel);
end;

function NewLogger(const AOutputter: IATLogOutputter; const ALevel: TATLogLevel): IATLogger;
begin
  if Atomic_Read(InternalLogInstanceCount) = LOG_MAX_INSTANCECOUNT then
    raise ELogTooManyInstances.CreateResFmt(@sLogTooManyInstances, [LOG_MAX_INSTANCECOUNT]);

  Result := TATLoggerContext.Create(AOutputter, ALevel);
end;

procedure CleanLogFiles(const ALogFileDirs: array of string; ALogFileFoundFunc: TATLogFileFoundFunc;
  ASubDir: Boolean; Async: Boolean);
begin
  if Length(ALogFileDirs) = 0 then
    Exit;

  if Async then
    TATLogFileCleaner.Create(ALogFileDirs, ALogFileFoundFunc, ASubDir)
  else
  { Sync }
    with TATLogFileCleaner.Create(ALogFileDirs, ALogFileFoundFunc, ASubDir, False, False) do
      try
        WaitFor;
      finally
        Free;
      end;  
end;

{ TATLogElementList }

{$IFDEF WIN32}

{ Avoid calling the wrong overload function. }
function InternalFileTimeToLocalFileTime(const lpFileTime: TFileTime; var lpLocalFileTime: TFileTime): BOOL; stdcall;
  external kernel32 name 'FileTimeToLocalFileTime';

// http://guildalfa.ru/alsha/node/6
function Now: TDateTime;
const
  MsPerDay     = 1440 * 60 * 1000;              //Day in milliseconds
  DateTimeBase = 693594;                        //Days between 01/01/0001 and 12/31/1899
  FileTimeBase = 584389;                        //Days between 01/01/0001 and 01/01/1601
  DeltaInDays  = DateTimeBase - FileTimeBase;   //Days between 01/01/1601 and 12/31/1899
const
  DeltaInMs    = int64(DeltaInDays) * MsPerDay; //Milliseconds between 01/01/1601 and 12/31/1899
  DeltaInMsLo  = DeltaInMs and $FFFFFFFF;
  DeltaInMsHi  = DeltaInMs shr 32;
const
  OneMs: extended = 1 / MsPerDay;                 //Millisecond in days
const
  //Magic constant to replace 64-bit integer division by 625 with multiplication
  Magic625Inverted   = $346DC5D63886594B;
  Magic625InvertedLo = Magic625Inverted and $FFFFFFFF;
  Magic625InvertedHi = Magic625Inverted shr 32;
asm
  add esp, -20
  mov [esp+16], ebx
  lea ebx, [esp+8]
  push ebx
  call GetSystemTimeAsFileTime
  push esp
  push ebx
  call InternalFileTimeToLocalFileTime
 
  //Convert TFileTime to milliseconds: divide pint64(esp)^ by 10000, result in edx:eax
  mov eax, Magic625InvertedLo
  xor ebx, ebx
  mul [esp]
  mov eax, Magic625InvertedLo
  mov ecx, edx
  mul [esp+4]
  add ecx, eax
  mov eax, Magic625InvertedHi
  adc ebx, edx
  mul [esp]
  add ecx, eax
  mov eax, Magic625InvertedHi
  adc ebx, edx
  mov ecx, 0
  adc ecx, ecx
  mul [esp+4]
  add eax, ebx
  adc edx, ecx
  shrd eax, edx, 11
  shr edx, 11
 
  sub eax, DeltaInMsLo
  sbb edx, DeltaInMsHi
  mov [esp], eax
  mov [esp+4], edx
  fild qword ptr [esp]
  mov ebx, [esp+16]
  fld OneMs
  add esp, 20
  fmulp
end;
{$ENDIF WIN32}  

function TATLogElementList.Add(const ALog: string;
  const ALogLevel: TATLogLevel): Integer;
var
  LLogElement: PATLogElement;
begin
  New(LLogElement);
  LLogElement^.Log := ALog;
  LLogElement^.LogTriggerTime := Now;
  LLogElement^.LogLevel := ALogLevel;
  Result := Add(LLogElement);
end;

procedure TATLogElementList.CleanAllElements;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    Dispose(Elements[I]);

  Count := 0;
  if Capacity >= LOG_LIST_IC_SHRINK then
    Capacity := LOG_LIST_IC;
end;

destructor TATLogElementList.Destroy;
begin
  CleanAllElements;
  inherited;
end;

function TATLogElementList.GetElement(AIndex: Integer): PATLogElement;
begin
  Result := PATLogElement(Items[AIndex]);
end;

{ TATCustomLogFormater }

constructor TATCustomLogFormater.Create;
begin
  inherited;
  FFormatSettings := GetFormatSettings;
  FDelimiter      := ' ';
  FDateTimeFormat := 'yyyy-mm-dd hh:nn:ss.zzz';
  FTimeZone       := GetTimeZone;
end;

{ TATDefaultLogFormater }

function TATDefaultLogFormater.LogFormat(const ALogElement: PATLogElement): string;
begin
  { e.g. 2014-10-01 11:25:16.123 [Debug] Text }
  with ALogElement^ do
    Result := FormatDateTime(FDateTimeFormat, LogTriggerTime, FFormatSettings) +
              LOG_LEVEL_CAPTIONS[LogLevel] + FDelimiter +
              Log;
end;

{ TATCSVLogFormater }

constructor TATCSVLogFormater.Create;
begin
  inherited;
  Delimiter := ',';
end;

{ TATCustomLogOutputter }

constructor TATCustomLogOutputter.Create(const ALogFormater: IATLogFormater);
begin
  inherited Create;
  FLogFormater := ALogFormater;

  if not Assigned(FLogFormater) then
    FLogFormater := TATDefaultLogFormater.Create;
end;

type

  TAsyncOutputEvent = procedure(const ALogs: TATLogElementList) of object;

  TAsyncLogThread = class(TATCustomLogThread)
  private
    FLastLogErrorMsg: string;
    {$IFDEF AUTOREFCOUNT}[Weak]{$ENDIF} FOwner: TATAsyncLogOutputter;
    FAsyncOutputEvent: TAsyncOutputEvent;
    procedure SetLogErrorMsg(const AException: Exception); {$IFDEF HAS_INLINE}inline;{$ENDIF}
    procedure ThreadSwitch(const AItemCount: Integer); {$IFDEF HAS_INLINE}inline;{$ENDIF}
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TATAsyncLogOutputter; AAsyncOutputEvent: TAsyncOutputEvent;
      ACreateSuspended: Boolean);
    property LastLogErrorMsg: string read FLastLogErrorMsg;
  end;

{ TAsyncLogThread }

constructor TAsyncLogThread.Create(AOwner: TATAsyncLogOutputter;
  AAsyncOutputEvent: TAsyncOutputEvent; ACreateSuspended: Boolean);
begin
  FOwner := AOwner;
  FAsyncOutputEvent := AAsyncOutputEvent;
  FreeOnTerminate := False;
  inherited Create(ACreateSuspended);
end;

procedure TAsyncLogThread.ThreadSwitch(const AItemCount: Integer);
{$WARN SYMBOL_PLATFORM OFF}
const
  // 131072 lines
  NormalCount = 128 * 1024;
{$IFDEF MSWINDOWS}
var
  LNeedPriority: TThreadPriority;
{$ENDIF}
begin

  // Normal work
  if AItemCount <= NormalCount then
  begin
{$IFDEF MSWINDOWS}
    LNeedPriority := tpNormal;
{$ENDIF}
    Sleep(10);
  end else
  begin
  // Heavy work
{$IFDEF MSWINDOWS}
    LNeedPriority := tpHigher;
{$ENDIF}
    Sleep(1);
  end;
  
{$IFDEF MSWINDOWS}
  if Priority <> LNeedPriority then
    Priority := LNeedPriority;
{$ENDIF}

{$WARN SYMBOL_PLATFORM ON}
end;

procedure TAsyncLogThread.Execute;
begin
  while not Terminated do
    with FOwner do
    begin
    
      Lock;
      try
        SiblingSwitch;
      finally
        UnLock;
      end;

      ThreadSwitch(Consumer.Count);

      if (Consumer.Count > 0) then
        try
          if Assigned(FAsyncOutputEvent) then
            try
              FAsyncOutputEvent(Consumer);
            except
              on E: Exception do
                SetLogErrorMsg(E);
            end;
        finally
          { Ensure Consumer is cleared even FAsyncOutputEvent = nil. }
          Consumer.CleanAllElements;
        end;
        
    end;
end;

procedure TAsyncLogThread.SetLogErrorMsg(const AException: Exception);
begin
  { e.g. TLogOutputterClass\ExceptionClass: msg }
  FLastLogErrorMsg := FOwner.ClassName + '\' +
                      AException.ClassName + ': ' + AException.Message;
end;

{$IFDEF HAS_OBJECTLOCK}
type
  TObjectSynchro = class(TSynchroObject)
  public
    procedure Acquire; override;
    procedure Release; override;
  end;

{ TObjectSynchro }

procedure TObjectSynchro.Acquire;
begin
  System.TMonitor.Enter(Self);
end;

procedure TObjectSynchro.Release;
begin
  System.TMonitor.Exit(Self);
end;
{$ENDIF HAS_OBJECTLOCK}

{$IFDEF MSWINDOWS}
type
  TATCriticalSectionSpin = class(TSynchroObject)
  protected
    FSection: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Acquire; override;
    procedure Release; override;
  end;

constructor TATCriticalSectionSpin.Create;
begin
  inherited Create;
  InitializeCriticalSectionAndSpinCount(FSection, 4000);
end;

destructor TATCriticalSectionSpin.Destroy;
begin
  DeleteCriticalSection(FSection);
  inherited Destroy;
end;

procedure TATCriticalSectionSpin.Acquire;
begin
  EnterCriticalSection(FSection);
end;

procedure TATCriticalSectionSpin.Release;
begin
  LeaveCriticalSection(FSection);
end;
{$ENDIF MSWINDOWS}

type 
{$IFDEF HAS_OBJECTLOCK}
    TATLogSynchro = class(TObjectSynchro)
{$ELSE}
  {$IFDEF MSWINDOWS}
    TATLogSynchro = class(TATCriticalSectionSpin)
  {$ELSE}
    TATLogSynchro = class(TCriticalSection)
  {$ENDIF}
{$ENDIF};

{ TATAsyncLogOutputter }

constructor TATAsyncLogOutputter.Create(const ALogFormater: IATLogFormater);
var
  LB: Boolean;
begin
  inherited;
  FSynchroObject := CreateSynchroObject;

  for LB := False to True do
  begin
    FLogSiblingLists[LB] := TATLogElementList.Create;
    FLogSiblingLists[LB].Capacity := LOG_LIST_IC;
  end;

  FConsumerSibling := False;

  FLogOutputWorker := TAsyncLogThread.Create(Self, DoAsycLog, True);
{$IFDEF D2010AndUp}
  FLogOutputWorker.Start;
{$ELSE}
  FLogOutputWorker.Resume;
{$ENDIF}
end;

function TATAsyncLogOutputter.CreateSynchroObject: TSynchroObject;
begin
  Result := TATLogSynchro.Create;
end;

destructor TATAsyncLogOutputter.Destroy;
begin
{$IFDEF WAIT_FOR_FINISHED_WHEN_TERMINATED}
  WaitForFinished;
{$ENDIF}

  with TAsyncLogThread(FLogOutputWorker) do
    if LastLogErrorMsg <> '' then
      TATDefaultLogOutputter.NativeOutput(LastLogErrorMsg);

  FreeAndNil(FLogOutputWorker);
  FreeAndNil(FLogSiblingLists[False]);
  FreeAndNil(FLogSiblingLists[True]);
  FreeAndNil(FSynchroObject);
  inherited;
end;

function TATAsyncLogOutputter.GetConsumer: TATLogElementList;
begin
  Result := FLogSiblingLists[FConsumerSibling];
end;

function TATAsyncLogOutputter.GetProducer: TATLogElementList;
begin
  Result := FLogSiblingLists[not FConsumerSibling];
end;

procedure TATAsyncLogOutputter.Lock;
begin
  FSynchroObject.Acquire;
end;

procedure TATAsyncLogOutputter.Output(const ALog: string; const ALogLevel: TATLogLevel);
label
  WaitFor;
begin

  WaitFor:

    Lock;
    try
      if Producer.Count < LOG_MAX_ITEMCOUNT then
      begin
        Producer.Add(ALog, ALogLevel);
        Exit;
      end;
    finally
      UnLock;
    end;

    if {$IFDEF MSWINDOWS}GetCurrentThreadId
       {$ELSE}TThread.CurrentThread.ThreadID
       {$ENDIF} = MainThreadID then
      { There is still a change to output logs in main thread.}
      Application.ProcessMessages;

    Sleep(50);

  { Wait until FLogList.Count < MAX_ITEMCOUNT. }
  goto WaitFor;

end;

procedure TATAsyncLogOutputter.SiblingSwitch;
begin
  FConsumerSibling := not FConsumerSibling;
end;

procedure TATAsyncLogOutputter.UnLock;
begin
  FSynchroObject.Release;
end;

{$IFDEF WAIT_FOR_FINISHED_WHEN_TERMINATED}
procedure TATAsyncLogOutputter.WaitForFinished;
begin
  { The outputter has stopped, now waiting for the final flush work. }
  while True do
  begin
    Lock;
    try
      if (FLogSiblingLists[False].Count = 0) and
         (FLogSiblingLists[True].Count = 0) then
        Exit;
    finally
      UnLock;
    end;
  end;
end;
{$ENDIF)

{ TATDefaultLogOutputter }

procedure TATDefaultLogOutputter.DoAsycLog(const ALogs: TATLogElementList);
var
  I: Integer;
begin
  for I := 0 to ALogs.Count - 1 do
    NativeOutput(FLogFormater.LogFormat(ALogs[I]));
end;

class procedure TATDefaultLogOutputter.NativeOutput(const ALog: string);

{$IFDEF IOS}
  function PNSStr(const AStr: string): PNSString;
  begin
    Result := (NSStr(AStr) as ILocalObject).GetObjectID;
  end;
{$ENDIF}

{$IFDEF ANDROID}
var
  LMarshaller: TMarshaller;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}

 { You can see the results in Delphi (View - Debug Windows - Event Log)
   in debug mode, or use the tool: dbgview.exe from "http://www.sysinternals.com" . }  
  OutputDebugString(PChar(ALog));
{$ENDIF}

{$IFDEF IOS}
  NSLog(PNSStr(ALog));
{$ENDIF}

{$IFDEF MACOS}
  {$IFDEF DXE3AndUp}
  Log.d(ALog);
  {$ENDIF}
{$ENDIF}

{$IFDEF ANDROID}

  { The log type was not classified in Android, we current only use
    the info type, others types please see Androidapi.Log.pas. }
  LOGI(LMarshaller.AsAnsi(ALog).ToPointer);
{$ENDIF}
end;

{ TATLogIdentifier }

class function TATLogIdentifier.ContainLogIdentifier(
  const AStr: string): Boolean;
begin
  Result := AnsiContainsText(AStr, GetLogIdentifier);
end;

class function TATLogIdentifier.GetLogIdentifier: string;
begin
  { ATLog unique identifier. }
  Result := '{57CDB29C-82BC-4BA8-A928-9724F95D7E04}';
end;

class function TATLogIdentifier.IsLogIdentifier(const AStr: string): Boolean;
var
  LLogID: string;
begin
  LLogID := GetLogIdentifier;
  Result := SameText(LeftStr(Trim(AStr), Length(LLogID)), LLogID);
end;

{ Text file read and write }

const

  { The Log max file size(in bytes). }
  TEXTFILE_MAXSIZE       = 1024 * 1024 * 1024;

  { Default max single file size. }
  TEXTFILE_MAXSINGLESIZE = 100 * 1024 * 1024;

  { In bytes. }
  TEXT_BUFFERSIZE        = 4 * 1024;

{$IFNDEF HAS_TEXT_READER_AND_WRITER}

  { The max Textfile size limit to 2GB. }
  TEXTFILE_LIMITSIZE     = 2147483648;

  UTF8BOM                = #$EF + #$BB + #$BF;
{$ENDIF !HAS_TEXT_READER_AND_WRITER}

type

{$IFNDEF HAS_TEXT_READER_AND_WRITER}
  TATTextBuffer = array[0..TEXT_BUFFERSIZE - 1] of Byte;
{$ENDIF !HAS_TEXT_READER_AND_WRITER}

  TATTextWriteWrapper = class(TObject)
  private
  {$IFDEF HAS_TEXT_READER_AND_WRITER}
    FStreamWriter: TStreamWriter;
  {$ELSE}
    FAccessSuccessful: Boolean;                                  
    FTextFile: TextFile;
    FTextBuffer: TATTextBuffer;
  {$ENDIF}
  public
    constructor Create(const AFileName: string; AAppend: Boolean); virtual;
    destructor Destroy; override;
    procedure WriteStrln(const AStr: string); {$IFDEF HAS_INLINE}inline;{$ENDIF}
  end;

  TATTextReadWrapper = class(TObject)
  private
  {$IFDEF HAS_TEXT_READER_AND_WRITER}
    FStreamReader: TStreamReader;
  {$ELSE}
    FAccessSuccessful: Boolean;
    FIsUtf8BomLine: Boolean;
    FTextFile: TextFile;
    FTextBuffer: TATTextBuffer;
  {$ENDIF}
  public
    constructor Create(const AFileName: string); virtual;
    destructor Destroy; override;
    function ReadStrln: string; {$IFDEF HAS_INLINE}inline;{$ENDIF}
  end;

{ TATTextWriteWrapper }

constructor TATTextWriteWrapper.Create(const AFileName: string; AAppend: Boolean);
var
  LFilePath: string;
begin
  inherited Create;

  { If it is a new file, make sure the dest directory exists. }
  if not AAppend then
  begin
    LFilePath := ExtractFilePath(AFileName);
    if not DirectoryExists(LFilePath) then
      ForceDirectories(LFilePath);  
  end;

{$IFDEF HAS_TEXT_READER_AND_WRITER}
  FStreamWriter := TStreamWriter.Create(AFileName, AAppend, TEncoding.UTF8, TEXT_BUFFERSIZE);
{$ELSE}
  AssignFile(FTextFile, AFileName);
  SetTextBuf(FTextFile, FTextBuffer);

  if AAppend then
    Append(FTextFile)
  else begin
    Rewrite(FTextFile);
    { Write UTF-8 BOM, compatible with the unicode version. }
    Write(FTextFile, UTF8BOM);
  end;

  FAccessSuccessful := True;
{$ENDIF}
end;

destructor TATTextWriteWrapper.Destroy;
begin
{$IFDEF HAS_TEXT_READER_AND_WRITER}
  FreeAndNil(FStreamWriter);
{$ELSE}
  if FAccessSuccessful then
  begin
    try
      Flush(FTextFile);
    except
    end;
    CloseFile(FTextFile);
  end;
{$ENDIF}
  inherited;
end;

procedure TATTextWriteWrapper.WriteStrln(const AStr: string);
begin
{$IFDEF HAS_TEXT_READER_AND_WRITER}
  FStreamWriter.WriteLine(AStr);
{$ELSE}
  if FAccessSuccessful then
    Writeln(FTextFile, AnsiToUtf8(AStr));
{$ENDIF}
end;

{ TATTextReadWrapper }

constructor TATTextReadWrapper.Create(const AFileName: string);
begin
  inherited Create;
{$IFDEF HAS_TEXT_READER_AND_WRITER}
  FStreamReader := TStreamReader.Create(AFileName, TEncoding.UTF8, True, TEXT_BUFFERSIZE);
{$ELSE}

  if GetFileSize(AFileName) > TEXTFILE_LIMITSIZE then
    Exit;

  AssignFile(FTextFile, AFileName);
  SetTextBuf(FTextFile, FTextBuffer);
  Reset(FTextFile);

  FIsUtf8BomLine := True;
  FAccessSuccessful := True;
{$ENDIF}
end;

destructor TATTextReadWrapper.Destroy;
begin
{$IFDEF HAS_TEXT_READER_AND_WRITER}
  FreeAndNil(FStreamReader);
{$ELSE}
  if FAccessSuccessful then
    CloseFile(FTextFile);
{$ENDIF}
  inherited;
end;

function TATTextReadWrapper.ReadStrln: string;
begin
{$IFDEF HAS_TEXT_READER_AND_WRITER}
  Result := FStreamReader.ReadLine;
{$ELSE}
  Result := '';

  if not FAccessSuccessful then
    Exit;

  Readln(FTextFile, Result);
  if FIsUtf8BomLine then
  begin
    { Skip the UTF-8 BOM }
    Result := Copy(Result, Length(UTF8BOM) + 1, MaxInt);
    FIsUtf8BomLine := False;
  end;
  Result := Utf8ToAnsi(Result);
{$ENDIF}
end;

{ TATFileLogOutputter }

function TATFileLogOutputter.GetLogFileName: string;
begin
  Result := InternalDefaultLogFileName;
end;

class function TATFileLogOutputter.GetLogHeader: string;
const
  HeaderTemplate =
     { Make sure the id is on the first line. }  
    '#  %s' + sLineBreak +
    '#********************************************************************' + sLineBreak +
    '#  This header was auto generated by ATlogger V%s.'                    + sLineBreak +
    '#  OSName   : %s' + sLineBreak +
    '#  TimeZone : %s' + sLineBreak +    
    '#  AppName  : %s' + sLineBreak +
    '#********************************************************************';
begin
  Result := Format(HeaderTemplate, [TATLogIdentifier.GetLogIdentifier,
                                    ATLoggerVersion,
                                    InternalOSName, 
                                    InternalTimeZone,
                                    InternalAppName
                                    ], InternalDefaultFormatSettings);
end;

function TATFileLogOutputter.GetOutputLogFileName: string;

  function GetNextFileName(const AOriginalLogFileName: string): string;
  const
    FILENAME_SUFFIX = '_';
  var
    LNameWithoutExt, LFileNameExt: string;
    LFileNameIndex: Int64;
  begin
    Result := AOriginalLogFileName;

    if FMaxSingleFileSize = 0 then
      Exit;

    LFileNameIndex  := 1;
    LNameWithoutExt := ChangeFileExt(AOriginalLogFileName, '');
    LFileNameExt    := ExtractFileExt(AOriginalLogFileName);

    while GetFileSize(Result) > FMaxSingleFileSize do
    begin
      Result := LNameWithoutExt + FILENAME_SUFFIX + IntToStr(LFileNameIndex) + LFileNameExt;
      Inc(LFileNameIndex);
    end;
  end;

begin
  Result := GetNextFileName(LogFileName);
end;

class function TATFileLogOutputter.IsLogFile(const AFileName: string): Boolean;
var
  LTextReader: TATTextReadWrapper;
  LHeader: string;
begin
  LTextReader := TATTextReadWrapper.Create(AFileName);
  try
    try
      LHeader := LTextReader.ReadStrln;
      Result := TATLogIdentifier.ContainLogIdentifier(LHeader);
    except
      Result := False;
    end;
  finally
    LTextReader.Free;
  end;
end;

procedure TATFileLogOutputter.SetMaxSingleFileSize(const Value: Cardinal);
begin
  if Value > TEXTFILE_MAXSIZE then
    FMaxSingleFileSize := TEXTFILE_MAXSIZE
  else if Value = 0 then
    FMaxSingleFileSize := TEXTFILE_MAXSINGLESIZE
  else
    FMaxSingleFileSize := Value;
end;

constructor TATFileLogOutputter.Create(const ALogFormater: IATLogFormater);
begin
  inherited;
  MaxSingleFileSize := TEXTFILE_MAXSINGLESIZE;
end;

procedure TATFileLogOutputter.DoAsycLog(const ALogs: TATLogElementList);

  {$IFDEF DEBUG_LOG}
  function GetDebugString: string;

     {$IFDEF MSWINDOWS}
     function GetPriorityStr(const AThreadHandle: THandle): string;
     const
       Priorities: array [TThreadPriority] of Integer =
         (THREAD_PRIORITY_IDLE, THREAD_PRIORITY_LOWEST, THREAD_PRIORITY_BELOW_NORMAL,
          THREAD_PRIORITY_NORMAL, THREAD_PRIORITY_ABOVE_NORMAL,
          THREAD_PRIORITY_HIGHEST, THREAD_PRIORITY_TIME_CRITICAL);

       ThreadPriorityStrs: array[TThreadPriority] of string = 
         ('tpIdle', 'tpLowest', 'tpLower', 'tpNormal', 'tpHigher', 'tpHighest', 'tpTimeCritical');
      var
        LP: Integer;
        I, LR: TThreadPriority;
      begin
        LP := GetThreadPriority(AThreadHandle);
        if (LP = THREAD_PRIORITY_ERROR_RETURN) then
        begin
          Result := 'Error';
          Exit;
        end;

        LR := tpNormal;
        for I := Low(TThreadPriority) to High(TThreadPriority) do
          if Priorities[I] = LP then
          begin
            LR := I;
            Break;
          end;

        Result := ThreadPriorityStrs[LR];
      end;
     {$ENDIF}
  begin
    Result := ' @Outputed Count = ' + IntToStr(ALogs.Count) +
              ' @Customer = ' + BoolToStr(FConsumerSibling, True);
  {$IFDEF MSWINDOWS}
    Result := Result +
              ' @CurThreadID = ' + IntToStr(GetCurrentThreadId) +
              ' @Priority = ' + GetPriorityStr(GetCurrentThread);
  {$ELSE}
    Result := Result +
              ' @CurThreadID = ' + IntToStr(TThread.CurrentThread.ThreadID);
  {$ENDIF}
  end;
  {$ENDIF DEBUG_LOG}

var
  I: Integer;
  LFileWriter: TATTextWriteWrapper;
  LFileName, LFormatedLog: string;
  LIsNewFile: Boolean;
begin
  { We are in a thread here. }

  if (ALogs.Count = 0) then
    Exit;

  LFileName := OutputLogFileName;
  if LFileName = '' then
    Exit;

  LIsNewFile := not FileExists(LFileName);
  LFileWriter := TATTextWriteWrapper.Create(LFileName, not LIsNewFile);

  try
    if LIsNewFile then
      LFileWriter.WriteStrln(GetLogHeader());

  {$IFDEF DEBUG_LOG}
    LFileWriter.WriteStrln(LTextFile, GetDebugString);
  {$ENDIF}
      
    for I := 0 to ALogs.Count - 1 do
    begin
      LFormatedLog := LogFormater.LogFormat(ALogs[I]);
      LFileWriter.WriteStrln(LFormatedLog);
    end;
  finally
    LFileWriter.Free;
  end;
end;

{ TATStaticFileNameLogOutputter }

constructor TATStaticFileNameLogOutputter.Create(const ALogFormater: IATLogFormater;
  const ALogFileName: string);
begin
  inherited Create(ALogFormater);
  
  if ALogFileName <> '' then
    FLogFileName := ALogFileName
  else
    FLogFileName := inherited GetLogFileName();
end;

function TATStaticFileNameLogOutputter.GetLogFileName: string;
begin
  Result := FLogFileName;
end;

{ TATEventFileNameOutputter }

constructor TATEventFileNameOutputter.Create(const ALogFormater: IATLogFormater;
  const ALogFileNameFunc: TATLogFileNameFunc);
begin
  inherited Create(ALogFormater);
  FLogFileNameFunc := ALogFileNameFunc;
end;

function TATEventFileNameOutputter.GetLogFileName: string;
begin
  if Assigned(FLogFileNameFunc) then
    try
      Result := FLogFileNameFunc()
    except
      Result := '';
    end
  else
    Result := inherited GetLogFileName();  
end;

{ TATLogFileCleaner }

procedure TATLogFileCleaner.DoDirFound(const ADir: string);

  function IsDirectoryEmpty(const ADirectory: string): Boolean;
  var
    LSearchRec: TSearchRec;
  begin
    try
      Result := (FindFirst(IncludeTrailingPathDelimiter(ADirectory) + '*.*', faAnyFile, LSearchRec) = 0) and
                (FindNext(LSearchRec) = 0) and
                (FindNext(LSearchRec) <> 0);
    finally
      FindClose(LSearchRec);
    end;
  end;

begin
  if IsDirectoryEmpty(ADir) then
    DelDirectory(ADir);
end;

procedure TATLogFileCleaner.DoFileFound(const AFileName: string);
var
  LLogFileNeedDeleted: Boolean;
begin
  if not TATFileLogOutputter.IsLogFile(AFileName) then
    Exit;

  try
    LLogFileNeedDeleted := not Assigned(FLogFileFoundFunc) or FLogFileFoundFunc(AFileName);
  except
    LLogFileNeedDeleted := False;
  end;

  if LLogFileNeedDeleted then
    DelFile(AFileName);
end;

constructor TATLogFileCleaner.Create(const ADirs: array of string;
  ALogFileFoundFunc: TATLogFileFoundFunc; ASubDir: Boolean; ACreateSuspended: Boolean;
  AFreeOnTerminate: Boolean);
var
  I: Integer;
begin
  SetLength(FSearchDirs, Length(ADirs));
  for I := Low(ADirs) to High(ADirs) do
    FSearchDirs[I] := ADirs[I];

  FLogFileFoundFunc := ALogFileFoundFunc;
  FNeedSubDir := ASubDir;

  FreeOnTerminate := AFreeOnTerminate;

  inherited Create(ACreateSuspended);
end;

procedure TATLogFileCleaner.Execute;

  procedure FileWalk(ADir: string; ASubDir: Boolean);
  var
    LSearchRec: TSearchRec;
    LFound: Integer;
    LRootDir, LDir: string;
  begin
    ADir := IncludeTrailingPathDelimiter(ADir);
    LRootDir := ADir;
    
    LFound := FindFirst(ADir + '*', faAnyFile, LSearchRec);
    try
      while (LFound = 0) and not Terminated do
      begin
        if (LSearchRec.Name <> '.') and (LSearchRec.Name <> '..') then
        begin
          if (LSearchRec.Attr and faDirectory > 0) then
          begin
            LDir := ADir + LSearchRec.Name;
            if ASubDir then
              FileWalk(LDir, ASubDir);
          end else
            DoFileFound(ADir + LSearchRec.Name);
        end;
        LFound := FindNext(LSearchRec);
      end;
    finally
      FindClose(LSearchRec);
    end;

    DoDirFound(LRootDir);
  end;

var
  I: Integer;
begin
  for I := Low(FSearchDirs) to High(FSearchDirs) do
  begin
    FileWalk(FSearchDirs[I], FNeedSubDir);
    if Terminated then
      Exit;
  end;
end;

initialization;

  InternalThreadLock := TATLogSynchro.Create;

  InternalOSName   := GetOSName;
  InternalAppName  := {$IFDEF MSWINDOWS}Application.Title{$ELSE}Application.DefaultTitle{$ENDIF};
  InternalTimeZone := GetTimeZone;

  InternalDefaultLogFileName    := GetDefaultLogPath + InternalAppName + '.log';
  InternalDefaultFormatSettings := GetFormatSettings;

finalization

  InternalDefaultLogger := nil;
  FreeAndNil(InternalThreadLock);
{$IFDEF DEBUG_LOG}
  Assert(InternalLogInstanceCount = 0);
{$ENDIF}  

end.