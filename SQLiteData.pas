unit SQLiteData;

interface

uses SysUtils, SQLite;

type
  TSQLiteConnection=class(TObject)
  private
    FHandle:HSQLiteDB;
  public
    constructor Create(FileName:UTF8String);
    destructor Destroy; override;
    //TODO: Exec
    property Handle:HSQLiteDB read FHandle;
  end;

  TSQLiteStatement=class(TObject)
  private
    FDB:HSQLiteDB;
    FHandle:HSQLiteStatement;
    FEOF,FGotColumnNames,FGotParamNames:boolean;
    FColumnNames,FParamNames:array of WideString;
    function GetField(Idx:OleVariant):OleVariant;
    function GetFieldName(Idx:integer):WideString;
    function GetFieldCount:integer;
    procedure GetColumnNames;
    procedure GetParamNames;
    function GetParameter(Idx: OleVariant): OleVariant;
    procedure SetParameter(Idx: OleVariant; Value: OleVariant);
    function GetParameterCount: integer;
    function GetParameterName(Idx: integer): WideString;
  public
    constructor Create(Connection:TSQLiteConnection;SQL:UTF8String);
    destructor Destroy; override;
    procedure ExecSQL;
    function Next:boolean;
    procedure Reset;
    property Field[Idx:OleVariant]:OleVariant read GetField; default;
    property FieldName[Idx:integer]:WideString read GetFieldName;
    property FieldCount:integer read GetFieldCount;
    property Parameter[Idx:OleVariant]:OleVariant read GetParameter write SetParameter;
    property ParameterName[Idx:integer]:WideString read GetParameterName;
    property ParameterCount:integer read GetParameterCount;
    property Eof:boolean read FEOF;
  end;

  ESQLiteDataException=class(Exception);

implementation

uses Variants;

{ TSQLiteConnection }

constructor TSQLiteConnection.Create(FileName: UTF8String);
begin
  inherited Create;
  sqlite3_check(sqlite3_open(PAnsiChar(FileName),FHandle));
end;

destructor TSQLiteConnection.Destroy;
begin
  {sqlite3_check}(sqlite3_close(FHandle));
  inherited;
end;

{ TSQLiteStatement }

constructor TSQLiteStatement.Create(Connection: TSQLiteConnection;
  SQL: UTF8String);
begin
  inherited Create;
  sqlite3_prepare_v2(Connection.Handle,PAnsiChar(SQL),Length(SQL)+1,FHandle,PAnsiChar(nil^));
  //TODO: tail!
  //TODO: keep a copy of Connection.Handle for sqlite3_check
  FDB:=Connection.Handle;
  FEOF:=sqlite3_data_count(FHandle)<>0;
  FGotColumnNames:=false;
  FGotParamNames:=false;
end;

destructor TSQLiteStatement.Destroy;
begin
  {sqlite3_check}(sqlite3_finalize(FHandle));
  inherited;
end;

procedure TSQLiteStatement.GetColumnNames;
var
  i,l:integer;
begin
  if not FGotColumnNames then
   begin
    l:=sqlite3_column_count(FHandle);
    SetLength(FColumnNames,l);
    for i:=0 to l-1 do FColumnNames[i]:=sqlite3_column_name16(FHandle,i);
    FGotColumnNames:=true;
   end;
end;

function TSQLiteStatement.GetField(Idx: OleVariant): OleVariant;
var
  i,l:integer;
  s:WideString;
  p:pointer;
begin
  l:=sqlite3_column_count(FHandle);
  if VarIsNumeric(Idx) then i:=Idx else
   begin
    GetColumnNames;
    i:=0;
    s:=VarToWideStr(Idx);
    while (i<l) and (WideCompareText(s,FColumnNames[i])<>0) do inc(i);
   end;
  if (i<0) or (i>=l) then
    raise ESQLiteDataException.Create('Invalid column index "'+VarToStr(Idx)+'"');
  //TODO: use HSQLiteValue?
  case sqlite3_column_type(FHandle,i) of
    SQLITE_INTEGER:Result:=sqlite3_column_int(FHandle,i);
    SQLITE_FLOAT:Result:=sqlite3_column_double(FHandle,i);
    SQLITE_TEXT:Result:=WideString(sqlite3_column_text16(FHandle,i));
    SQLITE_BLOB:
     begin
      l:=sqlite3_column_bytes(FHandle,i);
      if l=0 then Result:=Null else
       begin
        Result:=VarArrayCreate([0,l-1],varByte);
        p:=VarArrayLock(Result);
        try
          Move(sqlite3_column_blob(FHandle,i)^,p^,l);
        finally
          VarArrayUnlock(Result);
        end;
       end;
     end;
    SQLITE_NULL:Result:=Null;
    else
      Result:=EmptyParam;//??
  end;
end;

function TSQLiteStatement.GetFieldCount: integer;
begin
  Result:=sqlite3_column_count(FHandle);
end;

function TSQLiteStatement.GetFieldName(Idx: integer): WideString;
begin
  GetColumnNames;
  if (Idx<0) or (Idx>=Length(FColumnNames)) then
    raise ESQLiteDataException.Create('Invalid column index "'+IntToStr(Idx)+'"');
  Result:=FColumnNames[Idx];
end;

procedure TSQLiteStatement.GetParamNames;
var
  i,l:integer;
begin
  if not FGotParamNames then
   begin
    l:=sqlite3_bind_parameter_count(FHandle);
    SetLength(FParamNames,l);
    for i:=0 to l-1 do FParamNames[i]:=UTF8Decode(sqlite3_bind_parameter_name(FHandle,i));
    FGotParamNames:=true;
   end;
end;

function TSQLiteStatement.GetParameter(Idx: OleVariant): OleVariant;
begin
  raise ESQLiteDataException.Create('Get parameter value not supported');
end;

procedure TSQLiteStatement.SetParameter(Idx: OleVariant; Value: OleVariant);
var
  i,j,l:integer;
  s:WideString;
  vt:TVarType;
  p:pointer;
begin
  l:=sqlite3_bind_parameter_count(FHandle);
  if VarIsNumeric(Idx) then i:=Idx else
   begin
    GetParamNames;
    i:=0;
    s:=VarToWideStr(Idx);
    while (i<l) and (WideCompareText(s,FParamNames[i])<>0) do inc(i);
    inc(i);
   end;
  if (i<1) or (i>l) then
    raise ESQLiteDataException.Create('Invalid parameter index "'+VarToStr(Idx)+'"');
  vt:=VarType(Value);
  if (vt and varArray)<>0 then
    case vt and varTypeMask of
      //TODO: support other array element types!
      varByte:
       begin
        l:=1;
        for j:=1 to VarArrayDimCount(Value) do
          l:=l*(VarArrayHighBound(Value,j)-VarArrayLowBound(Value,j));
        p:=VarArrayLock(Value);
        try
          sqlite3_bind_blob(FHandle,i,p^,l,nil);
        finally
          VarArrayUnlock(Value);
        end;
       end;
      else raise ESQLiteDataException.Create('Unsupported variant array type');
    end
  else
    case vt and varTypeMask of
      varNull:
        sqlite3_bind_null(FHandle,i);
      varSmallint,varInteger,varShortInt,varByte,varWord,varLongWord:
        sqlite3_bind_int(FHandle,i,Value);
      varInt64:
        sqlite3_bind_int64(FHandle,i,Value);
      varSingle,varDouble:
        sqlite3_bind_double(FHandle,i,Value);
      //varDate?
      //varBoolean
      varOleStr:
       begin
        s:=VarToWideStr(Value);
        sqlite3_bind_text16(FHandle,i,PWideChar(s),Length(s)+1,nil);
       end;
      //varVariant?
      //varUnknown IPersist? IStream?
      else raise ESQLiteDataException.Create('Unsupported variant type');
    end;
end;

function TSQLiteStatement.GetParameterCount: integer;
begin
  Result:=sqlite3_bind_parameter_count(FHandle);
end;

function TSQLiteStatement.GetParameterName(Idx: integer): WideString;
begin
  GetParamNames;
  if (Idx<0) or (Idx>=Length(FParamNames)) then
    raise ESQLiteDataException.Create('Invalid parameter index "'+IntToStr(Idx)+'"');
  Result:=FParamNames[Idx];
end;

procedure TSQLiteStatement.ExecSQL;
var
  r:integer;
begin
  r:=sqlite3_step(FHandle);
  case r of
    //SQLITE_BUSY://TODO: wait a little and retry?
    SQLITE_DONE:;//ok!
    SQLITE_ROW:raise ESQLiteDataException.Create('ExecSQL with unexpected data, use Next instead.');
    //SQLITE_ERROR
    //SQLITE_MISUSE
    else sqlite3_check(r);
  end;
end;

function TSQLiteStatement.Next: boolean;
var
  r:integer;
begin
  Result:=false;//default
  if not FEOF then
   begin
    r:=sqlite3_step(FHandle);
    case r of
      //SQLITE_BUSY://TODO: wait a little and retry?
      SQLITE_DONE:FEOF:=true;
      SQLITE_ROW:Result:=true;
      //SQLITE_ERROR
      //SQLITE_MISUSE
      else sqlite3_check(FDB,r);
    end;
   end;
end;

procedure TSQLiteStatement.Reset;
begin
  sqlite3_check(sqlite3_reset(FHandle));
  sqlite3_check(sqlite3_clear_bindings(FHandle));//TODO: switch?
  FEOF:=false;
  FGotColumnNames:=false;
  FGotParamNames:=false;
end;

end.
