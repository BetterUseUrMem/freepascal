{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2014 by Michael Van Canneyt

    Pascal to Javascript converter class.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************
}(*
Abstract:
  Converts TPasElements into TJSElements.

Works:
- units, programs
- unit interface function
- uses list
- use $impl for implementation declarations, can be disabled
- interface vars
- implementation vars
- external vars
- initialization section
- option to add "use strict";
- procedures
  - params
  - local vars
  - default values
  - function results
  - modifier external 'name'
  - local const: declare in singleton parent function as local var
  - give procedure overloads in module unique names by appending $1, $2, ...
  - give nested procedure overloads unique names by appending $1, $2, ...
  - untyped parameter
  - varargs
- assign statements
- char literals
- string
  - literals
  - setlength(s,newlen) -> s.length == newlen
  - read and write char aString[]
- for loop
  - if loopvar is used afterwards append  if($loopend>i)i--;
- repeat..until
- while..do
- try..finally
- try..except, try..except on else
- raise, raise E
- asm..end
- assembler; asm..end;
- break
- continue
- type alias
- inc/dec to += -=
- case-of
- convert "a div b" to "Math.floor(a / b)"
- and, or, xor, not: logical and bitwise
- rename name conflicts with js identifiers: apply, bind, call, prototype, ...
- record
  - types and vars
  - assign
  - clone record member
  - clone set member
  - clone when passing as argument
  - equal, not equal
- classes
  - declare using createClass
  - constructor
  - destructor
  - vars, init on create, clear references on destroy
  - class vars
  - external vars
  - ancestor
  - virtual, override, abstract
  - "is" operator
  - "as" operator
  - call inherited "inherited;", "inherited funcname;"
  - call class method
  - read/write class var
  - property
    - param list
    - property of type array
  - class property
    - accessors non static
  - Assigned()
  - default property
  - type casts
  - overloads, reintroduce  append $1, $2, ...
  - reintroduced variables
- dynamic arrays
  - init as "arr = []"  arrays must never be null
  - SetLength(arr,len) becomes  arr = SetLength(arr,len,defaultvalue)
  - length(arr)
  - assign nil -> []  arrays must never be null
  - read, write element arr[index]
  - low(), high()
  - multi dimensional [index1,index2] -> [index1][index2]
  - array of record
  - equal, unequal nil -> array.length == 0
  - when passing nil to an array argument, pass []
- static arrays
  - range: enumtype
  - init as arr = rtl.arrayNewMultiDim([dim1,dim2,...],value)
  - init with expression
  - length(1-dim array)
  - low(1-dim array), high(1-dim array)
- enums
  - type with values and names
  - option to write numbers instead of variables
  - ord(), low(), high(), pred(), succ()
  - type cast number to enumtype
- sets
  - set of enum
  - include, exclude, clone when referenced
  - assign :=   set state referenced
  - constant set: enums, enum vars, ranges
  - set operators +, -, *, ><, =, <>, >=, <=
  - in-operator
  - low(), high()
  - when passing as argument set state referenced
- with-do  using local var
  - with record do i:=v;
  - with classinstance do begin create; i:=v; f(); i:=a[]; end;
- pass by reference
  - pass local var to a var/out parameter
  - pass variable to a var/out parameter
  - pass reference to a var/out parameter
  - pass array element to a var/out parameter
- procedure types
  - implemented as immutable wrapper function
  - assign := nil, proctype (not clone), @function, @method
  - call  explicit and implicit
  - compare equal and notequal with nil, proctype, address, function
  - assigned(proctype)
  - pass as argument
  - methods
  - mode delphi: proctype:=proc
  - mode delphi: functype=funcresulttype
- class-of
  - assign :=   nil, var
  - call class method
  - call constructor
  - operators =, <>
  - class var, property, method
  - Self in class method
  - typecast
- ECMAScript6:
  - use 0b for binary literals
  - use 0o for octal literals

ToDos:
- TTestModule.TestSet_Property pass set as parameter
- Combine TAssignContext tail statements

Not in Version 1.0:
- writeln
- arrays
  - static array: clone on assign and pass as argument
  - static array: non 0 start index, length
  - array of static array: setlength
  - array range char, char rangge, integer range, enum range
  - open arrays
  - array of const
- sets
  - set of char, boolean, integer range, char range, enum range
  - set of (enum,enum2)  - anonymous enumtype
- call array of proc element without ()
- record const
- enums with custom values
- library
- hint: local var not used
- hint: local proc not used
- hint: private member not used
- option typecast checking -CR
- option range checking -Cr
- option overflow checking -Co
- option trash local vars -gt
- optimizations:
  set operators on literals without temporary arrays
  use a number for small sets
  -O1 remove not used identifiers and units in unit
  -O1 with -Jc whole program optimization: remove not used identifiers
  -O1 insert local/unit vars for global type references:
      at start of intf var $r1;
      at end of impl: $r1=path;
  -O1 insert unit vars for complex literals
  -O1 no function Result var when assigned only once
- dotted unit names
- pointer of record
- objects, interfaces, advanced records
- class helpers, type helpers, record helpers,
- nested types in class
- generics
- operator overloading
- enumeration  for..in..do
- inline

Compile flags for debugging: -d<x>
   VerbosePas2JS
*)
unit fppas2js;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Classes, SysUtils, math, contnrs, jsbase, jstree, PasTree, PScanner,
  PasResolver;

// message numbers
const
  nPasElementNotSupported = 4001;
  nIdentifierNotFound = 4002;
  nUnaryOpcodeNotSupported = 4003;
  nBinaryOpcodeNotSupported = 4004;
  nInvalidNumber = 4005;
  nInitializedArraysNotSupported = 4006;
  nMemberExprMustBeIdentifier = 4007;
  nCantWriteSetLiteral = 4008;
  nVariableIdentifierExpected = 4009;
  nExpectedXButFoundY = 4010;
  nInvalidFunctionReference = 4011;
  nMissingExternalName = 4012;
// resourcestring patterns of messages
resourcestring
  sPasElementNotSupported = 'Pascal element not supported: %s';
  sIdentifierNotFound = 'Identifier not found "%s"';
  sUnaryOpcodeNotSupported = 'Unary OpCode not yet supported "%s"';
  sBinaryOpcodeNotSupported = 'Binary OpCode not yet supported "%s"';
  sInvalidNumber = 'Invalid number "%s"';
  sInitializedArraysNotSupported = 'Initialized array variables not yet supported';
  sMemberExprMustBeIdentifier = 'Member expression must be an identifier';
  sCantWriteSetLiteral = 'Cannot write set literal';
  sVariableIdentifierExpected = 'Variable identifier expected';
  sExpectedXButFoundY = 'Expected %s, but found %s';
  sInvalidFunctionReference = 'Invalid function reference';
  sMissingExternalName = 'Missing external name';

const
  DefaultFuncNameArray_SetLength = 'arraySetLength'; // rtl.arraySetLength
  DefaultFuncNameArray_NewMultiDim = 'arrayNewMultiDim'; // rtl.arrayNewMultiDim
  DefaultFuncNameAs = 'as'; // rtl.as
  DefaultFuncNameCreateClass = 'createClass'; // rtl.createClass
  DefaultFuncNameFreeClassInstance = '$destroy';
  DefaultFuncNameNewClassInstance = '$create';
  DefaultFuncNameProcType_Create = 'createCallback'; // rtl.createCallback
  DefaultFuncNameProcType_Equal = 'eqCallback'; // rtl.eqCallback
  DefaultFuncNameRecordEqual = '$equal';
  DefaultFuncNameSetCharAt = 'setCharAt'; // rtl.setCharAt
  DefaultFuncNameSet_Clone = 'cloneSet'; // rtl.cloneSet
  DefaultFuncNameSet_Create = 'createSet'; // rtl.createSet [...]
  DefaultFuncNameSet_Difference = 'diffSet'; // rtl.diffSet -
  DefaultFuncNameSet_Equal = 'eqSet'; // rtl.eqSet =
  DefaultFuncNameSet_Exclude = 'excludeSet'; // rtl.excludeSet
  DefaultFuncNameSet_GreaterEqual = 'geSet'; // rtl.geSet superset >=
  DefaultFuncNameSet_Include = 'includeSet'; // rtl.includeSet
  DefaultFuncNameSet_Intersect = 'intersectSet'; // rtl.intersectSet *
  DefaultFuncNameSet_LowerEqual = 'leSet'; // rtl.leSet subset <=
  DefaultFuncNameSet_NotEqual = 'neSet'; // rtl.neSet <>
  DefaultFuncNameSet_Reference = 'refSet'; // rtl.refSet
  DefaultFuncNameSet_SymDiffSet = 'symDiffSet'; // rtl.symDiffSet >< (symmetrical difference)
  DefaultFuncNameSet_Union = 'unionSet'; // rtl.unionSet +
  DefaultVarNameImplementation = '$impl';
  DefaultVarNameLoopEnd = '$loopend';
  DefaultVarNameModules = 'pas';
  DefaultVarNameRTL = 'rtl';
  DefaultVarNameWith = '$with';

  JSReservedWords: array[0..61] of string = (
     // keep sorted, first uppercase, then lowercase !
     'Array',
     'Infinity',
     'Math',
     'NaN',
     'Number',
     'Object',
     'String',
     '__extends',
     '_super',
     'anonymous',
     'apply',
     'arguments',
     'array',
     'await',
     'bind',
     'break',
     'call',
     'case',
     'catch',
     'class',
     'constructor',
     'continue',
     'default',
     'delete',
     'do',
     'each',
     'else',
     'enum',
     'export',
     'extends',
     'false',
     'for',
     'function',
     'getPrototypeOf',
     'if',
     'implements',
     'import',
     'in',
     'instanceof',
     'interface',
     'isPrototypeOf',
     'let',
     'new',
     'null',
     'package',
     'private',
     'protected',
     'prototype',
     'public',
     'return',
     'static',
     'super',
     'switch',
     'this',
     'throw',
     'true',
     'try',
     'undefined',
     'var',
     'while',
     'with',
     'yield'
    );

const
  ClassVarModifiersType = [vmClass,vmStatic];
  LowJSInteger = -$10000000000000;
  HighJSInteger = $fffffffffffff;
  LowJSBoolean = false;
  HighJSBoolean = true;

Type

  { EPas2JS }

  EPas2JS = Class(Exception)
  public
    PasElement: TPasElement;
    MsgNumber: integer;
    Args: TMessageArgs;
    Id: int64;
    MsgType: TMessageType;
  end;

//------------------------------------------------------------------------------
// TConvertContext
type
  TCtxJSElementKind = (
    cjkRoot,
    cjkObject,
    cjkFunction,
    cjkArray,
    cjkDot);

  TCtxAccess = (
    caRead,  // normal read
    caAssign, // needs setter
    caByReference // needs path, getter and setter
    );

  TFunctionContext = Class;

  { TConvertContext }

  TConvertContextClass = Class of TConvertContext;
  TConvertContext = Class(TObject)
  public
    PasElement: TPasElement;
    JSElement: TJSElement;
    Resolver: TPasResolver;
    Parent: TConvertContext;
    Kind: TCtxJSElementKind;
    IsSingleton: boolean;
    Access: TCtxAccess;
    AccessContext: TConvertContext;
    TmpVarCount: integer;
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); virtual;
    function GetRootModule: TPasModule;
    function GetThis: TPasElement;
    function GetThisContext: TFunctionContext;
    function GetContextOfType(aType: TConvertContextClass): TConvertContext;
    function CreateLocalIdentifier(const Prefix: string): string;
    function CurrentModeswitches: TModeSwitches;
    function GetSingletonFunc: TFunctionContext;
  end;

  { TRootContext }

  TRootContext = Class(TConvertContext)
  public
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TFunctionContext }

  TFunctionContext = Class(TConvertContext)
  public
    This: TPasElement;
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TObjectContext }

  TObjectContext  = Class(TConvertContext)
  public
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TInterfaceContext }

  TInterfaceContext = Class(TFunctionContext)
  public
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TDotContext - used for converting eopSubIdent }

  TDotContext = Class(TConvertContext)
  public
    LeftResolved: TPasResolverResult;
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TAssignContext - used for left side of an assign statement }

  TAssignContext = Class(TConvertContext)
  public
    // set when creating:
    LeftResolved: TPasResolverResult;
    RightResolved: TPasResolverResult;
    RightSide: TJSElement;
    // created by ConvertElement:
    PropertyEl: TPasProperty;
    Setter: TPasElement;
    Call: TJSCallExpression;
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

  { TParamContext }

  TParamContext = Class(TConvertContext)
  public
    // set when creating:
    Arg: TPasArgument;
    Expr: TPasExpr;
    ResolvedExpr: TPasResolverResult;
    // created by ConvertElement:
    Getter: TJSElement;
    Setter: TJSElement;
    ReusingReference: boolean; // truer = result is a reference, do not create another
    constructor Create(PasEl: TPasElement; JSEl: TJSElement; aParent: TConvertContext); override;
  end;

//------------------------------------------------------------------------------
// Element CustomData
type

  { TPas2JsElementData }

  TPas2JsElementData = Class(TPasElementBase)
  private
    FElement: TPasElementBase;
    procedure SetElement(const AValue: TPasElementBase);
  public
    Owner: TObject; // e.g. a TPasToJSConverter
    Next: TPas2JsElementData; // TPasToJSConverter uses this for its memory chain
    constructor Create; virtual;
    destructor Destroy; override;
    property Element: TPasElementBase read FElement write SetElement; // can be TPasElement or TResolveData
  end;
  TPas2JsElementDataClass = class of TPas2JsElementData;

  { TP2JWithData }

  TP2JWithData = Class(TPas2JsElementData)
  public
    // Element is TPasWithExprScope
    WithVarName: string;
  end;

  { TP2JConstExprData - CustomData of a const TPasExpr }

  TP2JConstExprData = Class(TPas2JsElementData)
  public
    // Element is TPasExpr
    Value: TJSValue;
    destructor Destroy; override;
  end;

//------------------------------------------------------------------------------
// TPas2JSResolver
const
  DefaultPasResolverOptions = [
    proFixCaseOfOverrides,
    proClassPropertyNonStatic,
    proAllowPropertyAsVarParam
    ];
type
  TPas2JSResolver = class(TPasResolver)
  protected
    FOverloadScopes: TFPList; // list of TPasIdentifierScope
    function GetOverloadIndex(Identifiers: TPasIdentifierScope;
      StopAt: TPasElement): integer;
    function GetOverloadIndex(El: TPasElement): integer;
    function RenameOverload(El: TPasElement): boolean;
    procedure RenameOverloadsInSection(aSection: TPasSection);
    procedure RenameOverloads(Declarations: TFPList);
    procedure RenameSubOverloads(Declarations: TFPList);
    procedure PushOverloadScope(Scope: TPasIdentifierScope);
    procedure PopOverloadScope;
    procedure FinishModule(CurModule: TPasModule); override;
  public
    constructor Create;
  end;

//------------------------------------------------------------------------------
// TPasToJSConverter
type
  TPasToJsConverterOption = (
    coLowerCase, // lowercase all identifiers, except conflicts with JS reserved words
    coSwitchStatement, // convert case-of into switch instead of if-then-else
    coEnumNumbers, // use enum numbers instead of names
    coUseStrict    // insert 'use strict'
    );
  TPasToJsConverterOptions = set of TPasToJsConverterOption;

  TPasToJsProcessor = (
    pECMAScript5,
    pECMAScript6
    );
  TPasToJsProcessors = set of TPasToJsProcessor;
const
  PasToJsProcessorNames: array[TPasToJsProcessor] of string = (
   'ECMAScript5',
   'ECMAScript6'
    );

type
  TRefPathKind = (
    rpkPath,      // e.g. "TObject"
    rpkPathWithDot, // e.g. "TObject."
    rpkPathAndName // e.g. "TObject.ClassName"
    );

  { TPasToJSConverter }

  TPasToJSConverter = Class(TObject)
  private
    // inline at top, only functions declared after the inline implementation actually use it
    function GetUseEnumNumbers: boolean; inline;
    function GetUseLowerCase: boolean; inline;
    function GetUseSwitchStatement: boolean; inline;
  private
    type
      TForLoopFindData = record
        ForLoop: TPasImplForLoop;
        LoopVar: TPasElement;
        FoundLoop: boolean;
        LoopVarWrite: boolean; // true if first acces of LoopVar after loop is a write
        LoopVarRead: boolean; // true if first acces of LoopVar after loop is a read
      end;
      PForLoopFindData = ^TForLoopFindData;
    procedure ForLoop_OnProcBodyElement(El: TPasElement; arg: pointer);
  private
    type
      TTryExceptFindData = record
        HasRaiseWithoutObject: boolean;
      end;
      PTryExceptFindData = ^TTryExceptFindData;
    procedure TryExcept_OnElement(El: TPasElement; arg: pointer);
  private
    FFirstElementData, FLastElementData: TPas2JsElementData;
    FFuncNameArray_NewMultiDim: String;
    FFuncNameArray_SetLength: String;
    FFuncNameAs: String;
    FFuncNameCreateClass: String;
    FFuncNameFreeClassInstance: String;
    FFuncNameMain: String;
    FFuncNameNewClassInstance: String;
    FFuncNameProcType_Create: String;
    FFuncNameProcType_Equal: String;
    FFuncNameRecordEqual: String;
    FFuncNameSetCharAt: String;
    FFuncNameSet_Clone: String;
    FFuncNameSet_Create: String;
    FFuncNameSet_Difference: String;
    FFuncNameSet_Equal: String;
    FFuncNameSet_Exclude: String;
    FFuncNameSet_GreaterEqual: String;
    FFuncNameSet_Include: String;
    FFuncNameSet_Intersect: String;
    FFuncNameSet_LowerEqual: String;
    FFuncNameSet_NotEqual: String;
    FFuncNameSet_Reference: String;
    FFuncNameSet_SymDiffSet: String;
    FFuncNameSet_Union: String;
    FOptions: TPasToJsConverterOptions;
    FTargetProcessor: TPasToJsProcessor;
    FVarNameImplementation: String;
    FVarNameLoopEnd: String;
    FVarNameModules: String;
    FVarNameRTL: String;
    FVarNameWith: String;
    Function CreateBuiltInIdentifierExpr(AName: string): TJSPrimaryExpressionIdent;
    Function CreateConstDecl(El: TPasConst; AContext: TConvertContext): TJSElement;
    Function CreateDeclNameExpression(El: TPasElement; const Name: string;
      AContext: TConvertContext): TJSPrimaryExpressionIdent;
    function CreateElementData(DataClass: TPas2JsElementDataClass;
      El: TPasElementBase): TPas2JsElementData;
    Function CreateIdentifierExpr(AName: string; El: TPasElement; AContext: TConvertContext): TJSPrimaryExpressionIdent;
    Function CreateSwitchStatement(El: TPasImplCaseOf; AContext: TConvertContext): TJSElement;
    Function CreateTypeDecl(El: TPasType; AContext: TConvertContext): TJSElement;
    Function CreateVarDecl(El: TPasVariable; AContext: TConvertContext): TJSElement;
    function GetElementData(El: TPasElementBase;
      DataClass: TPas2JsElementDataClass): TPas2JsElementData;
    procedure AddElementData(Data: TPas2JsElementData);
    Procedure AddToSourceElements(Src: TJSSourceElements; El: TJSElement);
    procedure SetTargetProcessor(const AValue: TPasToJsProcessor);
    procedure SetUseEnumNumbers(const AValue: boolean);
    procedure SetUseLowerCase(const AValue: boolean);
    procedure SetUseSwitchStatement(const AValue: boolean);
    {$IFDEF EnableOldClass}
    Function ConvertClassConstructor(El: TPasConstructor; AContext: TConvertContext): TJSElement; virtual;
    Function GetFunctionDefinitionInUnary(const fd: TJSFunctionDeclarationStatement;const funname: TJSString; inunary: boolean): TJSFunctionDeclarationStatement;
    Function GetFunctionUnaryName(var je: TJSElement;out fundec: TJSFunctionDeclarationStatement): TJSString;
    Procedure AddProcedureToClass(sl: TJSStatementList; E: TJSElement;const P: TPasProcedure);
    {$ENDIF}
  protected
    // Error functions
    Procedure DoError(Id: int64; Const Msg : String);
    Procedure DoError(Id: int64; Const Msg : String; Const Args : Array of Const);
    Procedure DoError(Id: int64; MsgNumber: integer; const MsgPattern: string; Const Args : Array of Const; El: TPasElement);
    procedure RaiseNotSupported(El: TPasElement; AContext: TConvertContext; Id: int64; const Msg: string = '');
    procedure RaiseIdentifierNotFound(Identifier: string; El: TPasElement; Id: int64);
    procedure RaiseInconsistency(Id: int64);
    // Computation, value conversions
    Function GetExpressionValueType(El: TPasExpr; AContext: TConvertContext ): TJSType; virtual;
    Function GetPasIdentValueType(AName: String; AContext: TConvertContext): TJSType; virtual;
    Function ComputeConst(Expr: TPasExpr; AContext: TConvertContext): TJSValue; virtual;
    Function TransFormStringLiteral(El: TPasElement; AContext: TConvertContext; const S: String): TJSString; virtual;
    // Name mangling
    {$IFDEF EnableOldClass}
    Function TransformIdent(El: TJSPrimaryExpressionIdent): TJSPrimaryExpressionIdent;virtual;
    {$ENDIF}
    Function TransformVariableName(El: TPasElement; Const AName: String; AContext : TConvertContext): String; virtual;
    Function TransformVariableName(El: TPasElement; AContext : TConvertContext) : String; virtual;
    Function TransformModuleName(El: TPasModule; AContext : TConvertContext) : String; virtual;
    Function IsPreservedWord(aName: string): boolean; virtual;
    Function GetExceptionObjectName(AContext: TConvertContext) : string;
    // Never create an element manually, always use the below functions
    Function CreateElement(C: TJSElementClass; Src: TPasElement): TJSElement; virtual;
    {$IFDEF EnableOldClass}
    Function CreateCallStatement(const JSCallName: string; JSArgs: array of string): TJSCallExpression;
    Function CreateCallStatement(const FunNameEx: TJSElement; JSArgs: array of string): TJSCallExpression;
    Function CreateProcedureDeclaration(const El: TPasElement):TJSFunctionDeclarationStatement;
    {$ENDIF}
    Function CreateFreeOrNewInstanceExpr(Ref: TResolvedReference;
      AContext : TConvertContext): TJSCallExpression; virtual;
    Function CreateFunction(El: TPasElement; WithBody: boolean = true): TJSFunctionDeclarationStatement;
    Procedure CreateProcedureCall(var Call: TJSCallExpression; Args: TParamsExpr;
      TargetProc: TPasProcedureType; AContext: TConvertContext); virtual;
    Procedure CreateProcedureCallArgs(Elements: TJSArrayLiteralElements;
      Args: TParamsExpr; TargetProc: TPasProcedureType; AContext: TConvertContext); virtual;
    Function CreateProcCallArg(El: TPasExpr; TargetArg: TPasArgument;
      AContext: TConvertContext): TJSElement; virtual;
    Function CreateProcCallArgRef(El: TPasExpr; ResolvedEl: TPasResolverResult;
      TargetArg: TPasArgument;  AContext: TConvertContext): TJSElement; virtual;
    Function CreateUnary(Members: array of string; E: TJSElement): TJSUnary;
    Function CreateMemberExpression(Members: array of string): TJSDotMemberExpression;
    Function CreateCallExpression(El: TPasElement): TJSCallExpression;
    Function CreateUsesList(UsesSection: TPasSection; AContext : TConvertContext): TJSArrayLiteral;
    Procedure AddToStatementList(var First, Last: TJSStatementList;
      Add: TJSElement; Src: TPasElement);
    Function CreateValInit(PasType: TPasType; Expr: TPasElement; El: TPasElement; AContext: TConvertContext): TJSElement;virtual;
    Function CreateVarInit(El: TPasVariable; AContext: TConvertContext): TJSElement; virtual;
    Function CreateLiteralNumber(El: TPasElement; const n: TJSNumber): TJSLiteral; virtual;
    Function CreateLiteralString(El: TPasElement; const s: string): TJSLiteral; virtual;
    Function CreateLiteralJSString(El: TPasElement; const s: TJSString): TJSLiteral; virtual;
    Function CreateLiteralBoolean(El: TPasElement; b: boolean): TJSLiteral; virtual;
    Function CreateLiteralNull(El: TPasElement): TJSLiteral; virtual;
    Function CreateLiteralUndefined(El: TPasElement): TJSLiteral; virtual;
    Function CreateRecordInit(aRecord: TPasRecordType; Expr: TPasElement;
      El: TPasElement; AContext: TConvertContext): TJSElement; virtual;
    Function CreateArrayInit(ArrayType: TPasArrayType; Expr: TPasElement;
      El: TPasElement; AContext: TConvertContext): TJSElement; virtual;
    Function CreateReferencePath(El: TPasElement; AContext : TConvertContext;
      Kind: TRefPathKind; Full: boolean = false; Ref: TResolvedReference = nil): string; virtual;
    Function CreateReferencePathExpr(El: TPasElement; AContext : TConvertContext; Full: boolean = false; Ref: TResolvedReference = nil): TJSPrimaryExpressionIdent;virtual;
    Procedure CreateImplementationSection(El: TPasModule; Src: TJSSourceElements; AContext: TConvertContext);
    Procedure CreateInitSection(El: TPasModule; Src: TJSSourceElements; AContext: TConvertContext);
    Function CreateDotExpression(aParent: TPasElement; Left, Right: TJSElement): TJSElement;virtual;
    Function CreateReferencedSet(El: TPasElement; SetExpr: TJSElement): TJSElement; virtual;
    Function CreateCloneRecord(El: TPasElement; ResolvedEl: TPasResolverResult;
      RecordExpr: TJSElement; AContext: TConvertContext): TJSElement; virtual;
    Function CreateCallback(El: TPasElement; ResolvedEl: TPasResolverResult;
      AContext: TConvertContext): TJSElement; virtual;
    // Statements
    Function ConvertImplBlockElements(El: TPasImplBlock; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertBeginEndStatement(El: TPasImplBeginBlock; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertStatement(El: TPasImplStatement; AContext: TConvertContext ): TJSElement;virtual;
    Function ConvertAssignStatement(El: TPasImplAssign; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertRaiseStatement(El: TPasImplRaise; AContext: TConvertContext ): TJSElement; virtual;
    Function ConvertIfStatement(El: TPasImplIfElse; AContext: TConvertContext ): TJSElement; virtual;
    Function ConvertWhileStatement(El: TPasImplWhileDo; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertRepeatStatement(El: TPasImplRepeatUntil; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertForStatement(El: TPasImplForLoop; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertFinalizationSection(El: TFinalizationSection; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertInitializationSection(El: TInitializationSection; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertSimpleStatement(El: TPasImplSimple; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertWithStatement(El: TPasImplWithDo; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertTryStatement(El: TPasImplTry; AContext: TConvertContext ): TJSElement;virtual;
    Function ConvertExceptOn(El: TPasImplExceptOn; AContext: TConvertContext): TJSElement;
    Function ConvertCaseOfStatement(El: TPasImplCaseOf; AContext: TConvertContext): TJSElement;
    Function ConvertAsmStatement(El: TPasImplAsmStatement; AContext: TConvertContext): TJSElement;
    // Expressions
    Function ConvertArrayValues(El: TArrayValues; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertInheritedExpression(El: TInheritedExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertNilExpr(El: TNilExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertParamsExpression(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertArrayParams(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertFuncParams(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertSetLiteral(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInLength(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInSetLength(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInExcludeInclude(El: TParamsExpr; AContext: TConvertContext; IsInclude: boolean): TJSElement;virtual;
    Function ConvertBuiltInContinue(El: TPasExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInBreak(El: TPasExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInExit(El: TPasExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInIncDec(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInAssigned(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInOrd(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInLow(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInHigh(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInPred(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBuiltInSucc(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertRecordValues(El: TRecordValues; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertSelfExpression(El: TSelfExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBinaryExpression(El: TBinaryExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertSubIdentExpression(El: TBinaryExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertBoolConstExpression(El: TBoolConstExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertPrimitiveExpression(El: TPrimitiveExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertIdentifierExpr(El: TPrimitiveExpr; AContext : TConvertContext): TJSElement;virtual;
    Function ConvertUnaryExpression(El: TUnaryExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertCallExpression(El: TParamsExpr; AContext: TConvertContext): TJSElement;virtual;
    // Convert declarations
    Function ConvertElement(El : TPasElement; AContext: TConvertContext) : TJSElement; virtual;
    Function ConvertProperty(El: TPasProperty; AContext: TConvertContext ): TJSElement;virtual;
    Function ConvertCommand(El: TPasImplCommand; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertCommands(El: TPasImplCommands; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertConst(El: TPasConst; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertDeclarations(El: TPasDeclarations; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertExportSymbol(El: TPasExportSymbol; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertExpression(El: TPasExpr; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertImplBlock(El: TPasImplBlock; AContext: TConvertContext ): TJSElement;virtual;
    Function ConvertLabelMark(El: TPasImplLabelMark; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertLabels(El: TPasLabels; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertModule(El: TPasModule; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertPackage(El: TPasPackage; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertProcedure(El: TPasProcedure; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertResString(El: TPasResString; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertVariable(El: TPasVariable; AContext: TConvertContext): TJSElement;virtual;
    Function ConvertRecordType(El: TPasRecordType; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertClassType(El: TPasClassType; AContext: TConvertContext): TJSElement; virtual;
    Function ConvertEnumType(El: TPasEnumType; AContext: TConvertContext): TJSElement; virtual;
  Public
    Constructor Create;
    destructor Destroy; override;
    procedure ClearElementData;
    Function ConvertPasElement(El : TPasElement; Resolver: TPasResolver) : TJSElement;
    // options
    Property Options: TPasToJsConverterOptions read FOptions write FOptions;
    Property TargetProcessor: TPasToJsProcessor read FTargetProcessor write SetTargetProcessor;
    Property UseLowerCase: boolean read GetUseLowerCase write SetUseLowerCase default true;
    Property UseSwitchStatement: boolean read GetUseSwitchStatement write SetUseSwitchStatement;// default false, because slower than "if" in many engines
    Property UseEnumNumbers: boolean read GetUseEnumNumbers write SetUseEnumNumbers; // default false
    // names
    Property FuncNameArray_NewMultiDim: String read FFuncNameArray_NewMultiDim write FFuncNameArray_NewMultiDim;
    Property FuncNameArray_SetLength: String read FFuncNameArray_SetLength write FFuncNameArray_SetLength;
    Property FuncNameAs: String read FFuncNameAs write FFuncNameAs;
    Property FuncNameCreateClass: String read FFuncNameCreateClass write FFuncNameCreateClass;
    Property FuncNameFreeClassInstance: String read FFuncNameFreeClassInstance write FFuncNameFreeClassInstance;
    Property FuncNameMain: String Read FFuncNameMain Write FFuncNameMain;
    Property FuncNameNewClassInstance: String read FFuncNameNewClassInstance write FFuncNameNewClassInstance;
    Property FuncNameProcType_Create: String read FFuncNameProcType_Create write FFuncNameProcType_Create;
    Property FuncNameProcType_Equal: String read FFuncNameProcType_Equal write FFuncNameProcType_Equal;
    Property FuncNameRecordEqual: String read FFuncNameRecordEqual write FFuncNameRecordEqual;
    Property FuncNameSetCharAt: String read FFuncNameSetCharAt write FFuncNameSetCharAt;
    Property FuncNameSet_Clone: String read FFuncNameSet_Clone write FFuncNameSet_Clone; // rtl.cloneSet
    Property FuncNameSet_Create: String read FFuncNameSet_Create write FFuncNameSet_Create; // rtl.createSet [...]
    Property FuncNameSet_Difference: String read FFuncNameSet_Difference write FFuncNameSet_Difference; // rtl.diffSet -
    Property FuncNameSet_Equal: String read FFuncNameSet_Equal write FFuncNameSet_Equal; // rtl.eqSet =
    Property FuncNameSet_Exclude: String read FFuncNameSet_Exclude write FFuncNameSet_Exclude; // rtl.excludeSet
    Property FuncNameSet_GreaterEqual: String read FFuncNameSet_GreaterEqual write FFuncNameSet_GreaterEqual; // rtl.geSet superset >=
    Property FuncNameSet_Include: String read FFuncNameSet_Include write FFuncNameSet_Include; // rtl.includeSet
    Property FuncNameSet_Intersect: String read FFuncNameSet_Intersect write FFuncNameSet_Intersect; // rtl.intersectSet *
    Property FuncNameSet_LowerEqual: String read FFuncNameSet_LowerEqual write FFuncNameSet_LowerEqual; // rtl.leSet subset <=
    Property FuncNameSet_NotEqual: String read FFuncNameSet_NotEqual write FFuncNameSet_NotEqual; // rtl.neSet <>
    Property FuncNameSet_Reference: String read FFuncNameSet_Reference write FFuncNameSet_Reference; // rtl.refSet
    Property FuncNameSet_SymDiffSet: String read FFuncNameSet_SymDiffSet write FFuncNameSet_SymDiffSet; // rtl.symDiffSet (symmetrical difference ><
    Property FuncNameSet_Union: String read FFuncNameSet_Union write FFuncNameSet_Union; // rtl.unionSet +
    Property VarNameImplementation: String read FVarNameImplementation write FVarNameImplementation;// empty to not use, default '$impl'
    Property VarNameLoopEnd: String read FVarNameLoopEnd write FVarNameLoopEnd;
    Property VarNameModules: String read FVarNameModules write FVarNameModules;
    Property VarNameRTL: String read FVarNameRTL write FVarNameRTL;
    Property VarNameWith: String read FVarNameWith write FVarNameWith;
  end;

var
  DefaultJSExceptionObject: string = '$e';

function CodePointToJSString(u: cardinal): TJSString;
function PosLast(c: char; const s: string): integer;

implementation

const
  TempRefObjGetterName = 'get';
  TempRefObjSetterName = 'set';
  TempRefObjSetterArgName = 'v';

function CodePointToJSString(u: cardinal): TJSString;
begin
  if u < $10000 then
    // Note: codepoints $D800 - $DFFF are reserved
    Result:=WideChar(u)
  else
    Result:=WideChar($D800+((u - $10000) shr 10))+WideChar($DC00+((u - $10000) and $3ff));
end;

function PosLast(c: char; const s: string): integer;
begin
  Result:=length(s);
  while (Result>0) and (s[Result]<>c) do dec(Result);
end;

{ TPas2JSResolver }

function TPas2JSResolver.GetOverloadIndex(Identifiers: TPasIdentifierScope;
  StopAt: TPasElement): integer;
// if not found return number of overloads
// if found return index in overloads
var
  Identifier: TPasIdentifier;
  El: TPasElement;
  ProcScope: TPasProcedureScope;
begin
  Result:=0;
  // find last added
  Identifier:=Identifiers.FindLocalIdentifier(StopAt.Name);
  // iterate from last added to first added
  while Identifier<>nil do
    begin
    El:=Identifier.Element;
    Identifier:=Identifier.NextSameIdentifier;
    if El=StopAt then
      begin
      Result:=0;
      continue;
      end;
    if El is TPasProcedure then
      begin
      if TPasProcedure(El).IsOverride or TPasProcedure(El).IsExternal then
        continue;
      ProcScope:=TPasProcedureScope(El.CustomData);
      if ProcScope.DeclarationProc<>nil then
        // implementation proc -> only count the header -> skip
        continue;
      end;
    inc(Result);
    end;
end;

function TPas2JSResolver.GetOverloadIndex(El: TPasElement): integer;
var
  i: Integer;
begin
  Result:=0;
  for i:=FOverloadScopes.Count-1 downto 0 do
    inc(Result,GetOverloadIndex(TPasIdentifierScope(FOverloadScopes[i]),El));
end;

function TPas2JSResolver.RenameOverload(El: TPasElement): boolean;
var
  OverloadIndex: Integer;
  NewName: String;
begin
  // => count overloads in this section
  OverloadIndex:=GetOverloadIndex(El);
  if OverloadIndex=0 then
    exit(false); // there is no overload
  NewName:=El.Name+'$'+IntToStr(OverloadIndex);
  {$IFDEF VerbosePas2JS}
  writeln('TPas2JSResolver.RenameOverload "',El.Name,'" has overload. NewName="',NewName,'"');
  {$ENDIF}
  El.Name:=NewName;
  Result:=true;
end;

procedure TPas2JSResolver.RenameOverloadsInSection(aSection: TPasSection);
var
  ImplSection: TImplementationSection;
  SectionClass: TClass;
begin
  if aSection=nil then exit;
  PushOverloadScope(aSection.CustomData as TPasIdentifierScope);
  RenameOverloads(aSection.Declarations);
  SectionClass:=aSection.ClassType;
  if SectionClass=TInterfaceSection then
    begin
    // unit interface
    // first rename all overloads in interface and implementation
    ImplSection:=(aSection.Parent as TPasModule).ImplementationSection;
    if ImplSection<>nil then
      begin
      PushOverloadScope(ImplSection.CustomData as TPasIdentifierScope);
      RenameOverloads(ImplSection.Declarations);
      end;
    // and then rename all nested overloads (e.g. methods)
    // Important: nested overloads must check both interface and implementation
    RenameSubOverloads(aSection.Declarations);
    if ImplSection<>nil then
      begin
      RenameSubOverloads(ImplSection.Declarations);
      PopOverloadScope;
      end;
    end
  else
    begin
    // program or library
    RenameSubOverloads(aSection.Declarations);
    end;
  PopOverloadScope;
end;

procedure TPas2JSResolver.RenameOverloads(Declarations: TFPList);
var
  i: Integer;
  El: TPasElement;
  Proc: TPasProcedure;
  ProcScope: TPasProcedureScope;
begin
  for i:=0 to Declarations.Count-1 do
    begin
    El:=TPasElement(Declarations[i]);
    if (El is TPasProcedure) then
      begin
      Proc:=TPasProcedure(El);
      if Proc.IsOverride or Proc.IsExternal then
        continue;
      ProcScope:=Proc.CustomData as TPasProcedureScope;
      //writeln('TPas2JSResolver.RenameOverloads Proc=',Proc.Name,' DeclarationProc=',GetObjName(ProcScope.DeclarationProc),' ImplProc=',GetObjName(ProcScope.ImplProc),' ClassScope=',GetObjName(ProcScope.ClassScope));
      if ProcScope.DeclarationProc<>nil then
        begin
        if ProcScope.ImplProc<>nil then
          RaiseInternalError(20170221110853);
        // proc implementation (not forward) -> skip
        continue;
        end;
      // proc declaration (header, not body)
      if RenameOverload(Proc) then
        if ProcScope.ImplProc<>nil then
          ProcScope.ImplProc.Name:=Proc.Name;
      end;
    end;
end;

procedure TPas2JSResolver.RenameSubOverloads(Declarations: TFPList);
var
  i, OldScopeCount: Integer;
  El: TPasElement;
  Proc, ImplProc: TPasProcedure;
  ProcScope: TPasProcedureScope;
  ClassScope, aScope: TPasClassScope;
  ClassEl: TPasClassType;
begin
  for i:=0 to Declarations.Count-1 do
    begin
    El:=TPasElement(Declarations[i]);
    if (El is TPasProcedure) then
      begin
      Proc:=TPasProcedure(El);
      if Proc.IsAbstract or Proc.IsExternal then continue;
      ProcScope:=Proc.CustomData as TPasProcedureScope;
      //writeln('TPas2JSResolver.RenameSubOverloads Proc=',Proc.Name,' DeclarationProc=',GetObjName(ProcScope.DeclarationProc),' ImplProc=',GetObjName(ProcScope.ImplProc),' ClassScope=',GetObjName(ProcScope.ClassScope));
      if ProcScope.DeclarationProc<>nil then
        // proc implementation (not forward) -> skip
        continue;
      ImplProc:=Proc;
      if ProcScope.ImplProc<>nil then
        begin
        // this proc has a separate implementation
        // -> switch to implementation
        ImplProc:=ProcScope.ImplProc;
        ProcScope:=ImplProc.CustomData as TPasProcedureScope;
        end;
      PushOverloadScope(ProcScope);
      // first rename all overloads on this level
      RenameOverloads(ImplProc.Body.Declarations);
      // then process nested procedures
      RenameSubOverloads(ImplProc.Body.Declarations);
      PopOverloadScope;
      end
    else if El.ClassType=TPasClassType then
      begin
      ClassEl:=TPasClassType(El);
      ClassScope:=El.CustomData as TPasClassScope;
      OldScopeCount:=FOverloadScopes.Count;

      // add class and ancestors scopes
      aScope:=ClassScope;
      repeat
        PushOverloadScope(aScope);
        aScope:=aScope.AncestorScope;
      until aScope=nil;

      // first rename all overloads on this level
      RenameOverloads(ClassEl.Members);
      // then process nested procedures
      RenameSubOverloads(ClassEl.Members);

      while FOverloadScopes.Count>OldScopeCount do
        PopOverloadScope;
      end
    else if (El is TPasConst) then
      RenameOverload(El)
    else if (El is TPasVariable) and (El.Parent.ClassType=TPasClassType) then
      RenameOverload(El);
    end;
end;

procedure TPas2JSResolver.PushOverloadScope(Scope: TPasIdentifierScope);
begin
  FOverloadScopes.Add(Scope);
end;

procedure TPas2JSResolver.PopOverloadScope;
begin
  FOverloadScopes.Delete(FOverloadScopes.Count-1);
end;

procedure TPas2JSResolver.FinishModule(CurModule: TPasModule);
var
  ModuleClass: TClass;
begin
  inherited FinishModule(CurModule);
  FOverloadScopes:=TFPList.Create;
  try
    ModuleClass:=CurModule.ClassType;
    if ModuleClass=TPasModule then
      RenameOverloadsInSection(CurModule.InterfaceSection)
    else if ModuleClass=TPasProgram then
      RenameOverloadsInSection(TPasProgram(CurModule).ProgramSection)
    else if CurModule.ClassType=TPasLibrary then
      RenameOverloadsInSection(TPasLibrary(CurModule).LibrarySection)
    else
      RaiseNotYetImplemented(20170221000032,CurModule);
  finally
    FOverloadScopes.Free;
  end;
end;

constructor TPas2JSResolver.Create;
begin
  inherited;
  StoreSrcColumns:=true;
  Options:=Options+DefaultPasResolverOptions;
end;

{ TP2JConstExprData }

destructor TP2JConstExprData.Destroy;
begin
  FreeAndNil(Value);
  inherited Destroy;
end;

{ TParamContext }

constructor TParamContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited Create(PasEl, JSEl, aParent);
  Access:=caAssign;
  AccessContext:=Self;
end;

{ TPas2JsElementData }

procedure TPas2JsElementData.SetElement(const AValue: TPasElementBase);
begin
  if FElement=AValue then Exit;
  if FElement<>nil then
    if FElement.CustomData<>Self then
      raise EPas2JS.Create('')
    else
      FElement.CustomData:=nil;
  FElement:=AValue;
  if FElement<>nil then
    if FElement.CustomData<>nil then
      raise EPas2JS.Create('')
    else
      FElement.CustomData:=Self;
end;

constructor TPas2JsElementData.Create;
begin

end;

destructor TPas2JsElementData.Destroy;
begin
  Element:=nil;
  Next:=nil;
  Owner:=nil;
  inherited Destroy;
end;

{ TAssignContext }

constructor TAssignContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited Create(PasEl, JSEl, aParent);
  Access:=caAssign;
  AccessContext:=Self;
end;

{ TDotContext }

constructor TDotContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited Create(PasEl, JSEl, aParent);
  Kind:=cjkDot;
end;

{ TInterfaceContext }

constructor TInterfaceContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited;
  IsSingleton:=true;
end;

{ TObjectContext }

constructor TObjectContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited;
  Kind:=cjkObject;
end;

{ TFunctionContext }

constructor TFunctionContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited;
  Kind:=cjkFunction;
end;

{ TRootContext }

constructor TRootContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  inherited;
  Kind:=cjkRoot;
end;

{ TConvertContext }

constructor TConvertContext.Create(PasEl: TPasElement; JSEl: TJSElement;
  aParent: TConvertContext);
begin
  PasElement:=PasEl;
  JSElement:=JsEl;
  Parent:=aParent;
  if Parent<>nil then
    begin
    Resolver:=Parent.Resolver;
    Access:=aParent.Access;
    AccessContext:=aParent.AccessContext;
    end;
end;

function TConvertContext.GetRootModule: TPasModule;
var
  aContext: TConvertContext;
begin
  aContext:=Self;
  while aContext.Parent<>nil do
    aContext:=aContext.Parent;
  if aContext.PasElement is TPasModule then
    Result:=TPasModule(aContext.PasElement)
  else
    Result:=nil;
end;

function TConvertContext.GetThis: TPasElement;
var
  ctx: TFunctionContext;
begin
  ctx:=GetThisContext;
  if ctx<>nil then
    Result:=ctx.This
  else
    Result:=nil;
end;

function TConvertContext.GetThisContext: TFunctionContext;
begin
  Result:=TFunctionContext(GetContextOfType(TFunctionContext));
end;

function TConvertContext.GetContextOfType(aType: TConvertContextClass
  ): TConvertContext;
var
  ctx: TConvertContext;
begin
  Result:=nil;
  ctx:=Self;
  repeat
    if ctx is aType then
      exit(ctx);
    ctx:=ctx.Parent;
  until ctx=nil;
end;

function TConvertContext.CreateLocalIdentifier(const Prefix: string): string;
begin
  inc(TmpVarCount);
  Result:=Prefix+IntToStr(TmpVarCount);
end;

function TConvertContext.CurrentModeswitches: TModeSwitches;
begin
  if Resolver=nil then
    Result:=OBJFPCModeSwitches
  else
    Result:=Resolver.CurrentParser.CurrentModeswitches;
end;

function TConvertContext.GetSingletonFunc: TFunctionContext;
var
  Ctx: TConvertContext;
begin
  Ctx:=Self;
  while (Ctx<>nil) do
    begin
    if Ctx.IsSingleton and (Ctx.JSElement<>nil) and (Ctx is TFunctionContext) then
      exit(TFunctionContext(Ctx));
    Ctx:=Ctx.Parent;
    end;
end;

{ TPasToJSConverter }

// inline
function TPasToJSConverter.GetUseEnumNumbers: boolean;
begin
  Result:=coEnumNumbers in FOptions;
end;

// inline
function TPasToJSConverter.GetUseLowerCase: boolean;
begin
  Result:=coLowerCase in FOptions;
end;

// inline
function TPasToJSConverter.GetUseSwitchStatement: boolean;
begin
  Result:=coSwitchStatement in FOptions;
end;

procedure TPasToJSConverter.AddToSourceElements(Src: TJSSourceElements;
  El: TJSElement);

Var
  List : TJSStatementList;
  AddEl : TJSElement;

begin
  While El<>nil do
  begin
    if El is TJSStatementList then
      begin
      List:=El as TJSStatementList;
      // List.A is first statement, List.B is next in list, chained.
      // -> add A, continue with B and free List
      AddEl:=List.A;
      El:=List.B;
      List.A:=Nil;
      List.B:=Nil;
      FreeAndNil(List);
      end
    else
      begin
      AddEl:=El;
      El:=Nil;
      end;
    Src.Statements.AddNode.Node:=AddEl;
  end;
end;

function TPasToJSConverter.ConvertModule(El: TPasModule;
  AContext: TConvertContext): TJSElement;
(* Format:
   rtl.module('<unitname>',
      [<interface uses1>,<uses2>, ...],
      function(){
        <interface>
        <implementation>
        this.$init=function(){
          <initialization>
          };
      },
      [<implementation uses1>,<uses2>, ...]);
*)
Var
  OuterSrc , Src: TJSSourceElements;
  RegModuleCall: TJSCallExpression;
  ArgArray: TJSArguments;
  UsesList: TFPList;
  FunDef: TJSFuncDef;
  FunBody: TJSFunctionBody;
  FunDecl: TJSFunctionDeclarationStatement;
  UsesSection: TPasSection;
  ModuleName: String;
  IntfContext: TInterfaceContext;
  VarSt: TJSVariableStatement;
  VarDecl: TJSVarDeclaration;
  AssignSt: TJSSimpleAssignStatement;
begin
  Result:=Nil;
  OuterSrc:=TJSSourceElements(CreateElement(TJSSourceElements, El));
  Result:=OuterSrc;

  // create 'rtl.module(...)'
  RegModuleCall:=CreateCallExpression(El);
  AddToSourceElements(OuterSrc,RegModuleCall);
  RegModuleCall.Expr:=CreateMemberExpression([VarNameRTL,'module']);
  ArgArray := RegModuleCall.Args;
  RegModuleCall.Args:=ArgArray;

  // add unitname parameter: unitname
  ModuleName:=TransformModuleName(El,AContext);
  ArgArray.Elements.AddElement.Expr:=CreateLiteralString(El,ModuleName);

  // add interface-uses-section parameter: [<interface uses1>,<uses2>, ...]
  UsesSection:=nil;
  if (El is TPasProgram) then
    UsesSection:=TPasProgram(El).ProgramSection
  else if (El is TPasLibrary) then
    UsesSection:=TPasLibrary(El).LibrarySection
  else
    UsesSection:=El.InterfaceSection;
  ArgArray.Elements.AddElement.Expr:=CreateUsesList(UsesSection,AContext);

  // add interface parameter: function(){}
  FunDecl:=TJSFunctionDeclarationStatement.Create(0,0);
  ArgArray.Elements.AddElement.Expr:=FunDecl;
  FunDef:=TJSFuncDef.Create;
  FunDecl.AFunction:=FunDef;
  FunDef.Name:='';
  FunBody:=TJSFunctionBody.Create(0,0);
  FunDef.Body:=FunBody;
  Src:=TJSSourceElements(CreateElement(TJSSourceElements, El));
  FunBody.A:=Src;

  if coUseStrict in Options then
    AddToSourceElements(Src,CreateLiteralString(El,'use strict'));

  IntfContext:=TInterfaceContext.Create(El,Src,AContext);
  try
    IntfContext.This:=El;
    if (El is TPasProgram) then
      begin // program
      if Assigned(TPasProgram(El).ProgramSection) then
        AddToSourceElements(Src,ConvertDeclarations(TPasProgram(El).ProgramSection,IntfContext));
      CreateInitSection(El,Src,IntfContext);
      end
    else if El is TPasLibrary then
      begin // library
      if Assigned(TPasLibrary(El).LibrarySection) then
        AddToSourceElements(Src,ConvertDeclarations(TPasLibrary(El).LibrarySection,IntfContext));
      CreateInitSection(El,Src,IntfContext);
      end
    else
      begin // unit
      // add interface section
      if (VarNameImplementation<>'') and Assigned(El.ImplementationSection) then
        begin
        // add 'var $impl = {};'
        VarSt:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
        AddToSourceElements(Src,VarSt);
        VarDecl:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El));
        VarSt.A:=VarDecl;
        VarDecl.Name:=VarNameImplementation;
        VarDecl.Init:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El.ImplementationSection));
        // add 'this.$impl = $impl;'
        AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
        AddToSourceElements(Src,AssignSt);
        AssignSt.LHS:=CreateBuiltInIdentifierExpr('this.'+VarNameImplementation);
        AssignSt.Expr:=CreateBuiltInIdentifierExpr(VarNameImplementation);
        end;
      if Assigned(El.InterfaceSection) then
        AddToSourceElements(Src,ConvertDeclarations(El.InterfaceSection,IntfContext));
      CreateImplementationSection(El,Src,IntfContext);
      CreateInitSection(El,Src,IntfContext);

      // add optional implementation uses list: [<implementation uses1>,<uses2>, ...]
      if Assigned(El.ImplementationSection) then
        begin
        UsesList:=El.ImplementationSection.UsesList;
        if (UsesList<>nil) and (UsesList.Count>0) then
          ArgArray.Elements.AddElement.Expr:=CreateUsesList(El.ImplementationSection,AContext);
        end;
      end;
  finally
    IntfContext.Free;
  end;
end;

function TPasToJSConverter.CreateElement(C: TJSElementClass; Src: TPasElement
  ): TJSElement;

var
  Line, Col: Integer;
begin
  if Assigned(Src) then
    begin
    TPasResolver.UnmangleSourceLineNumber(Src.SourceLinenumber,Line,Col);
    Result:=C.Create(Line,Col,Src.SourceFilename);
    end
  else
    Result:=C.Create(0,0);
end;

function TPasToJSConverter.CreateFreeOrNewInstanceExpr(Ref: TResolvedReference;
  AContext: TConvertContext): TJSCallExpression;
// create "$create("funcname");"
var
  ok: Boolean;
  C: TJSCallExpression;
  Proc: TPasProcedure;
  ProcScope: TPasProcedureScope;
  ClassScope: TPasClassScope;
  aClass: TPasElement;
  ArgEx: TJSLiteral;
  ArgElems: TJSArrayLiteralElements;
  FunName: String;
begin
  Result:=nil;
  //writeln('TPasToJSConverter.CreateNewInstanceStatement Ref.Declaration=',GetObjName(Ref.Declaration));
  Proc:=Ref.Declaration as TPasProcedure;
  if Proc.Name='' then
    RaiseInconsistency(20170125191914);
  //writeln('TPasToJSConverter.CreateNewInstanceStatement Proc.Name=',Proc.Name);
  ProcScope:=Proc.CustomData as TPasProcedureScope;
  //writeln('TPasToJSConverter.CreateNewInstanceStatement ProcScope.Element=',GetObjName(ProcScope.Element),' ProcScope.ClassScope=',GetObjName(ProcScope.ClassScope),' ProcScope.DeclarationProc=',GetObjName(ProcScope.DeclarationProc),' ProcScope.ImplProc=',GetObjName(ProcScope.ImplProc),' ProcScope.CustomData=',GetObjName(ProcScope.CustomData));
  ClassScope:=ProcScope.ClassScope;
  aClass:=ClassScope.Element;
  if aClass.Name='' then
    RaiseInconsistency(20170125191923);
  //writeln('TPasToJSConverter.CreateNewInstanceStatement aClass.Name=',aClass.Name);
  C:=CreateCallExpression(Ref.Element);
  ok:=false;
  try
    // add "$create()"
    if rrfNewInstance in Ref.Flags then
      FunName:=FuncNameNewClassInstance
    else
      FunName:=FuncNameFreeClassInstance;
    FunName:=CreateReferencePath(Proc,AContext,rpkPathWithDot,false,Ref)+FunName;
    C.Expr:=CreateBuiltInIdentifierExpr(FunName);
    ArgElems:=C.Args.Elements;
    // parameter: "funcname"
    ArgEx := CreateLiteralString(Ref.Element,TransformVariableName(Proc,AContext));
    ArgElems.AddElement.Expr:=ArgEx;
    ok:=true;
  finally
    if not ok then
      C.Free;
  end;
  Result:=C;
end;

function TPasToJSConverter.CreateFunction(El: TPasElement; WithBody: boolean
  ): TJSFunctionDeclarationStatement;
var
  FuncDef: TJSFuncDef;
  FuncSt: TJSFunctionDeclarationStatement;
begin
  FuncSt:=TJSFunctionDeclarationStatement(CreateElement(TJSFunctionDeclarationStatement,El));
  Result:=FuncSt;
  FuncDef:=TJSFuncDef.Create;
  FuncSt.AFunction:=FuncDef;
  if WithBody then
    FuncDef.Body:=TJSFunctionBody(CreateElement(TJSFunctionBody,El));
end;

function TPasToJSConverter.ConvertUnaryExpression(El: TUnaryExpr;
  AContext: TConvertContext): TJSElement;

  procedure NotSupported;
  begin
    DoError(20170215134950,nUnaryOpcodeNotSupported,sUnaryOpcodeNotSupported,
            [OpcodeStrings[El.OpCode]],El);
  end;

Var
  U : TJSUnaryExpression;
  E : TJSElement;
  ResolvedOp, ResolvedEl: TPasResolverResult;
  BitwiseNot: Boolean;

begin
  if AContext=nil then ;
  Result:=Nil;
  U:=nil;
  Case El.OpCode of
    eopAdd:
      begin
      E:=ConvertElement(El.Operand,AContext);
      U:=TJSUnaryPlusExpression(CreateElement(TJSUnaryPlusExpression,El));
      U.A:=E;
      end;
    eopSubtract:
      begin
      E:=ConvertElement(El.Operand,AContext);
      U:=TJSUnaryMinusExpression(CreateElement(TJSUnaryMinusExpression,El));
      U.A:=E;
      end;
    eopNot:
      begin
      E:=ConvertElement(El.Operand,AContext);
      BitwiseNot:=true;
      if AContext.Resolver<>nil then
        begin
        AContext.Resolver.ComputeElement(El.Operand,ResolvedOp,[]);
        BitwiseNot:=ResolvedOp.BaseType in btAllInteger;
        end;
      if BitwiseNot then
        U:=TJSUnaryInvExpression(CreateElement(TJSUnaryInvExpression,El))
      else
        U:=TJSUnaryNotExpression(CreateElement(TJSUnaryNotExpression,El));
      U.A:=E;
      end;
    eopAddress:
      begin
      if AContext.Resolver=nil then
        NotSupported;
      AContext.Resolver.ComputeElement(El.Operand,ResolvedEl,[rcNoImplicitProc]);
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertUnaryExpression ',GetResolverResultDesc(ResolvedEl));
      {$ENDIF}
      if ResolvedEl.BaseType=btProc then
        begin
        if ResolvedEl.IdentEl is TPasProcedure then
          begin
          Result:=CreateCallback(El.Operand,ResolvedEl,AContext);
          exit;
          end;
        end;
      end;
  end;
  if U=nil then
    NotSupported;
  Result:=U;
end;

function TPasToJSConverter.ConvertCallExpression(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
begin
  if AContext=nil then ;
  RaiseNotSupported(El,AContext,20161024191225,'ConvertCallExpression');
  Result:=nil;
end;

function TPasToJSConverter.GetExpressionValueType(El: TPasExpr;
  AContext: TConvertContext): TJSType;

  Function CombineValueType(A,B : TJSType) : TJSType;

  begin
    If (A=jstUNDEFINED) then
      Result:=B
    else if (B=jstUNDEFINED) then
      Result:=A
    else
      Result:=A; // pick the first
  end;

Var
  A,B : TJSType;

begin
  if (El is TBoolConstExpr) then
    Result:=jstBoolean
  else if (El is TPrimitiveExpr) then
    begin
    Case El.Kind of
      pekIdent : Result:=GetPasIdentValueType(El.Name,AContext);
      pekNumber : Result:=jstNumber;
      pekString : Result:=jstString;
      pekSet : Result:=jstUNDEFINED;
      pekNil : Result:=jstNull;
      pekBoolConst : Result:=jstBoolean;
      pekRange : Result:=jstUNDEFINED;
      pekFuncParams : Result:=jstUNDEFINED;
      pekArrayParams : Result:=jstUNDEFINED;
      pekListOfExp : Result:=jstUNDEFINED;
      pekInherited : Result:=jstUNDEFINED;
      pekSelf : Result:=jstObject;
    end
    end
  else if (El is TUnaryExpr) then
    Result:=GetExpressionValueType(TUnaryExpr(El).Operand,AContext)
  else if (El is TBinaryExpr) then
    begin
    A:=GetExpressionValueType(TBinaryExpr(El).Left,AContext);
    B:=GetExpressionValueType(TBinaryExpr(El).Right,AContext);
    Result:=CombineValueType(A,B);
    end
  else
    result:=jstUndefined
end;

function TPasToJSConverter.GetPasIdentValueType(AName: String;
  AContext: TConvertContext): TJSType;

begin
  if AContext=nil then ;
  if AName='' then ;
  Result:=jstUNDEFINED;
end;

function TPasToJSConverter.ComputeConst(Expr: TPasExpr;
  AContext: TConvertContext): TJSValue;
var
  Prim: TPrimitiveExpr;
  V: TJSValue;
begin
  Result:=nil;
  if Expr=nil then
    RaiseInconsistency(20170215123600);
  V:=nil;
  try
    if Expr.ClassType=TPrimitiveExpr then
      begin
      Prim:=TPrimitiveExpr(Expr);
      if Prim.Kind=pekString then
        V:=TJSValue.Create(TransFormStringLiteral(Prim,AContext,Prim.Value))
      else
        RaiseNotSupported(Prim,AContext,20170215124733);
      end
    else
      RaiseNotSupported(Expr,AContext,20170215124746);
    Result:=V;
  finally
    if Result=nil then
      V.Free;
  end;
end;

function TPasToJSConverter.TransFormStringLiteral(El: TPasElement;
  AContext: TConvertContext; const S: String): TJSString;
{ S is a Pascal string literal
    ''  empty string
    '''' => "'"
    #decimal
    #$hex
    ^l  l is a letter a-z
}
var
  p, StartP: PChar;
  c: Char;
  i: Integer;
begin
  Result:='';
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.TransFormStringLiteral "',S,'"');
  {$ENDIF}
  if S='' then
    RaiseInconsistency(20170207154543);
  p:=PChar(S);
  repeat
    case p^ of
    #0: break;
    '''':
      begin
      inc(p);
      StartP:=p;
      repeat
        c:=p^;
        case c of
        #0:
          RaiseInconsistency(20170207155120);
        '''':
          begin
          if p>StartP then
            Result:=Result+TJSString(copy(S,StartP-PChar(S)+1,p-StartP));
          inc(p);
          StartP:=p;
          if p^<>'''' then
            break;
          Result:=Result+'''';
          inc(p);
          StartP:=p;
          end;
        else
          inc(p);
        end;
      until false;
      if p>StartP then
        Result:=Result+TJSString(copy(S,StartP-PChar(S)+1,p-StartP));
      end;
    '#':
      begin
      inc(p);
      if p^='$' then
        begin
        // #$hexnumber
        inc(p);
        StartP:=p;
        i:=0;
        repeat
          c:=p^;
          case c of
          #0: break;
          '0'..'9': i:=i*16+ord(c)-ord('0');
          'a'..'f': i:=i*16+ord(c)-ord('a')+10;
          'A'..'F': i:=i*16+ord(c)-ord('A')+10;
          else break;
          end;
          if i>$10ffff then
            RaiseNotSupported(El,AContext,20170207164657,'maximum codepoint is $10ffff');
          inc(p);
        until false;
        if p=StartP then
          RaiseInconsistency(20170207164956);
        Result:=Result+CodePointToJSString(i);
        end
      else
        begin
        // #decimalnumber
        StartP:=p;
        i:=0;
        repeat
          c:=p^;
          case c of
          #0: break;
          '0'..'9': i:=i*10+ord(c)-ord('0');
          else break;
          end;
          if i>$10ffff then
            RaiseNotSupported(El,AContext,20170207171140,'maximum codepoint is $10ffff');
          inc(p);
        until false;
        if p=StartP then
          RaiseInconsistency(20170207171148);
        Result:=Result+CodePointToJSString(i);
        end;
      end;
    '^':
      begin
      // ^A is #1
      inc(p);
      c:=p^;
      case c of
      'a'..'z': Result:=Result+TJSChar(ord(c)-ord('a')+1);
      'A'..'Z': Result:=Result+TJSChar(ord(c)-ord('A')+1);
      else RaiseInconsistency(20170207160412);
      end;
      inc(p);
      end;
    else
      RaiseNotSupported(El,AContext,20170207154653,'ord='+IntToStr(ord(p^)));
    end;
  until false;
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.TransFormStringLiteral Result="',Result,'"');
  {$ENDIF}
end;

function TPasToJSConverter.ConvertBinaryExpression(El: TBinaryExpr;
  AContext: TConvertContext): TJSElement;
Const
  BinClasses : Array [TExprOpCode] of TJSBinaryClass = (
   Nil, //eopEmpty,
   TJSAdditiveExpressionPlus, // +
   TJSAdditiveExpressionMinus, // -
   TJSMultiplicativeExpressionMul, // *
   TJSMultiplicativeExpressionDiv, // /
   TJSMultiplicativeExpressionDiv, // div
   TJSMultiplicativeExpressionMod, // mod
   Nil, //eopPower
   TJSURShiftExpression, // shr
   TJSLShiftExpression, // shl
   Nil, // Not
   Nil, // And
   Nil, // Or
   Nil, // XOr
   TJSEqualityExpressionEQ,
   TJSEqualityExpressionNE,
   TJSRelationalExpressionLT,
   TJSRelationalExpressionGT,
   TJSRelationalExpressionLE,
   TJSRelationalExpressionGE,
   Nil, // In
   TJSRelationalExpressionInstanceOf, // is
   Nil, // As
   Nil, // Symmetrical diff
   Nil, // Address,
   Nil, // Deref
   Nil  // SubIndent,
  );

Var
  R : TJSBinary;
  C : TJSBinaryClass;
  A,B: TJSElement;
  UseBitwiseOp: Boolean;
  DotExpr: TJSDotMemberExpression;
  Call: TJSCallExpression;
  LeftResolved, RightResolved: TPasResolverResult;
  FunName: String;
  Bracket: TJSBracketMemberExpression;
  Flags: TPasResolverComputeFlags;
  ModeSwitches: TModeSwitches;
  NotEl: TJSUnaryNotExpression;
  CmpExpr: TJSBinaryExpression;
  {$IFDEF EnableOldClass}
  funname: string;
  {$ENDIF}

begin
  Result:=Nil;

  case El.OpCode of
  eopSubIdent:
    begin
    Result:=ConvertSubIdentExpression(El,AContext);
    exit;
    end;
  eopNone:
    if El.left is TInheritedExpr then
      begin
      Result:=ConvertInheritedExpression(TInheritedExpr(El.left),AContext);
      exit;
      end;
  end;

  if AContext.Access<>caRead then
    DoError(20170209152633,nVariableIdentifierExpected,sVariableIdentifierExpected,[],El);

  Call:=nil;
  A:=ConvertElement(El.left,AContext);
  B:=nil;
  try
    B:=ConvertElement(El.right,AContext);

    if AContext.Resolver<>nil then
      begin
      ModeSwitches:=AContext.CurrentModeswitches;
      // compute left
      Flags:=[];
      if El.OpCode in [eopEqual,eopNotEqual] then
        if not (msDelphi in ModeSwitches) then
          Flags:=[rcNoImplicitProcType];
      AContext.Resolver.ComputeElement(El.left,LeftResolved,Flags);

      // compute right
      Flags:=[];
      if (El.OpCode in [eopEqual,eopNotEqual])
          and not (msDelphi in ModeSwitches) then
        begin
        if LeftResolved.BaseType=btNil then
          Flags:=[rcNoImplicitProcType]
        else if AContext.Resolver.IsProcedureType(LeftResolved) then
          Flags:=[rcNoImplicitProcType]
        else
          Flags:=[];
        end;
      AContext.Resolver.ComputeElement(El.right,RightResolved,Flags);

      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertBinaryExpression Left=',GetResolverResultDesc(LeftResolved),' Right=',GetResolverResultDesc(RightResolved));
      {$ENDIF}
      if LeftResolved.BaseType=btSet then
        begin
        // set operators -> rtl.operatorfunction(a,b)
        case El.OpCode of
        eopAdd: FunName:=FuncNameSet_Union;
        eopSubtract: FunName:=FuncNameSet_Difference;
        eopMultiply: FunName:=FuncNameSet_Intersect;
        eopSymmetricaldifference: FunName:=FuncNameSet_SymDiffSet;
        eopEqual: FunName:=FuncNameSet_Equal;
        eopNotEqual: FunName:=FuncNameSet_NotEqual;
        eopGreaterThanEqual: FunName:=FuncNameSet_GreaterEqual;
        eopLessthanEqual: FunName:=FuncNameSet_LowerEqual;
        else
          DoError(20170209151300,nBinaryOpcodeNotSupported,sBinaryOpcodeNotSupported,[OpcodeStrings[El.OpCode]],El);
        end;
        Call:=CreateCallExpression(El);
        Call.Expr:=CreateMemberExpression([VarNameRTL,FunName]);
        Call.Args.Elements.AddElement.Expr:=A;
        Call.Args.Elements.AddElement.Expr:=B;
        Result:=Call;
        exit;
        end
      else if (RightResolved.BaseType=btSet) and (El.OpCode=eopIn) then
        begin
        // a in b -> b[a]
        Bracket:=TJSBracketMemberExpression(CreateElement(TJSBracketMemberExpression,El));
        Bracket.MExpr:=B;
        Bracket.Name:=A;
        Result:=Bracket;
        exit;
        end
      else if (El.OpCode=eopIs) then
        begin
        // convert "A is B" to "B.isPrototypeOf(A)"
        Call:=CreateCallExpression(El);
        Result:=Call;
        Call.Args.Elements.AddElement.Expr:=A; A:=nil;
        DotExpr:=TJSDotMemberExpression(CreateElement(TJSDotMemberExpression,El));
        DotExpr.MExpr:=B; B:=nil;
        DotExpr.Name:='isPrototypeOf';
        Call.Expr:=DotExpr;
        exit;
        end
      else if (El.OpCode in [eopEqual,eopNotEqual]) then
        begin
        if AContext.Resolver.IsProcedureType(LeftResolved) then
        begin
          if RightResolved.BaseType=btNil then
          else if AContext.Resolver.IsProcedureType(RightResolved) then
            begin
            // convert "proctypeA = proctypeB" to "rtl.eqCallback(proctypeA,proctypeB)"
            Call:=CreateCallExpression(El);
            Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameProcType_Equal]);
            Call.Args.Elements.AddElement.Expr:=A;
            Call.Args.Elements.AddElement.Expr:=B;
            if El.OpCode=eopNotEqual then
              begin
              // convert "proctypeA <> proctypeB" to "!rtl.eqCallback(proctypeA,proctypeB)"
              NotEl:=TJSUnaryNotExpression(CreateElement(TJSUnaryNotExpression,El));
              NotEl.A:=Call;
              Result:=NotEl;
              end
            else
              Result:=Call;
            exit;
            end;
          end
        else if LeftResolved.TypeEl is TPasRecordType then
          begin
          // convert "recordA = recordB" to "recordA.$equal(recordB)"
          Call:=CreateCallExpression(El);
          Call.Expr:=CreateDotExpression(El,A,CreateBuiltInIdentifierExpr(FuncNameRecordEqual));
          Call.Args.Elements.AddElement.Expr:=B;
          if El.OpCode=eopNotEqual then
            begin
            // convert "recordA = recordB" to "!recordA.$equal(recordB)"
            NotEl:=TJSUnaryNotExpression(CreateElement(TJSUnaryNotExpression,El));
            NotEl.A:=Call;
            Result:=NotEl;
            end
          else
            Result:=Call;
          exit;
          end
        else if LeftResolved.TypeEl is TPasArrayType then
          begin
          if RightResolved.BaseType=btNil then
            begin
            // convert "array = nil" to "array.length == 0"
            FreeAndNil(B);
            CmpExpr:=TJSEqualityExpressionEQ(CreateElement(BinClasses[El.OpCode],El));
            CmpExpr.A:=CreateDotExpression(El,A,CreateBuiltInIdentifierExpr('length'));
            A:=nil;
            CmpExpr.B:=CreateLiteralNumber(El.right,0);
            Result:=CmpExpr;
            exit;
            end;
          end
        else if RightResolved.TypeEl is TPasArrayType then
          begin
          if LeftResolved.BaseType=btNil then
            begin
            // convert "nil = array" to "0 == array.length"
            FreeAndNil(A);
            CmpExpr:=TJSEqualityExpressionEQ(CreateElement(BinClasses[El.OpCode],El));
            CmpExpr.A:=CreateLiteralNumber(El.left,0);
            CmpExpr.B:=CreateDotExpression(El,B,CreateBuiltInIdentifierExpr('length'));
            B:=nil;
            Result:=CmpExpr;
            exit;
            end;
          end;
        end;
      end;

    C:=BinClasses[El.OpCode];
    if C=nil then
      Case El.OpCode of
        eopAs :
          begin
          // convert "A as B" to "rtl.as(A,B)"
          Call:=CreateCallExpression(El);
          Call.Expr:=CreateBuiltInIdentifierExpr(VarNameRTL+'.'+FuncNameAs);
          Call.Args.Elements.AddElement.Expr:=A;
          Call.Args.Elements.AddElement.Expr:=B;
          Result:=Call;
          exit;
          end;
        eopAnd,
        eopOr,
        eopXor:
          begin
          if AContext.Resolver<>nil then
            UseBitwiseOp:=((LeftResolved.BaseType in btAllInteger)
                       or (RightResolved.BaseType in btAllInteger))
          else
            UseBitwiseOp:=(GetExpressionValueType(El.left,AContext)=jstNumber)
              or (GetExpressionValueType(El.right,AContext)=jstNumber);
          if UseBitwiseOp then
            Case El.OpCode of
              eopAnd : C:=TJSBitwiseAndExpression;
              eopOr : C:=TJSBitwiseOrExpression;
              eopXor : C:=TJSBitwiseXOrExpression;
            end
          else
            Case El.OpCode of
              eopAnd : C:=TJSLogicalAndExpression;
              eopOr : C:=TJSLogicalOrExpression;
            else
              DoError(20161024191234,nBinaryOpcodeNotSupported,sBinaryOpcodeNotSupported,['logical XOR'],El);
            end;
          end;
        {$IFDEF EnableOldClass}
        else if (A is TJSPrimaryExpressionIdent) and
            (TJSPrimaryExpressionIdent(A).Name = '_super') then
          begin
          Result := B;
          funname := String(TJSPrimaryExpressionIdent(TJSCallExpression(b).Expr).Name);
          TJSCallExpression(b).Args.Elements.AddElement.Expr :=
                                            CreateBuiltInIdentifierExpr('self');
          if TJSCallExpression(b).Args.Elements.Count > 1 then
            TJSCallExpression(b).Args.Elements.Exchange(
              0, TJSCallExpression(b).Args.Elements.Count - 1);
          if CompareText(funname, 'Create') = 0 then
            begin
            TJSCallExpression(B).Expr :=
              TJSDotMemberExpression(CreateElement(TJSDotMemberExpression, El));
            TJSDotMemberExpression(TJSCallExpression(b).Expr).MExpr := A;
            TJSDotMemberExpression(TJSCallExpression(b).Expr).Name := TJSString(funname);
            end
          else
            begin
            TJSCallExpression(B).Expr :=
              CreateMemberExpression(['_super', 'prototype', funname, 'call']);
            end;
          end
        {$ENDIF}
        else
          if C=nil then
            DoError(20161024191244,nBinaryOpcodeNotSupported,sBinaryOpcodeNotSupported,[OpcodeStrings[El.OpCode]],El);
      end;
    if (Result=Nil) and (C<>Nil) then
      begin
      R:=TJSBinary(CreateElement(C,El));
      R.A:=A; A:=nil;
      R.B:=B; B:=nil;
      Result:=R;

      if El.OpCode=eopDiv then
        begin
        // convert "a div b" to "Math.floor(a/b)"
        Call:=CreateCallExpression(El);
        Call.Args.Elements.AddElement.Expr:=R;
        Call.Expr:=CreateBuiltInIdentifierExpr('Math.floor');
        Result:=Call;
        end;
      end;
  finally
    if Result=nil then
      begin
      A.Free;
      B.Free;
      end;
  end;
end;

function TPasToJSConverter.ConvertSubIdentExpression(El: TBinaryExpr;
  AContext: TConvertContext): TJSElement;
// connect El.left and El.right with a dot.
var
  Left, Right: TJSElement;
  DotContext: TDotContext;
  OldAccess: TCtxAccess;
begin
  Result:=nil;
  // convert left side
  OldAccess:=AContext.Access;
  AContext.Access:=caRead;
  Left:=ConvertElement(El.left,AContext);
  if Left=nil then
    RaiseInconsistency(20170201140821);
  AContext.Access:=OldAccess;
  // convert right side
  DotContext:=TDotContext.Create(El,Left,AContext);
  Right:=nil;
  try
    if AContext.Resolver<>nil then
      AContext.Resolver.ComputeElement(El.left,DotContext.LeftResolved,[]);
    Right:=ConvertElement(El.right,DotContext);
  finally
    DotContext.Free;
    if Right=nil then
      Left.Free;
  end;
  // connect via dot
  Result:=CreateDotExpression(El,Left,Right);
end;

{$IFDEF EnableOldClass}
function TPasToJSConverter.TransformIdent(El: TJSPrimaryExpressionIdent
  ): TJSPrimaryExpressionIdent;

begin
  if UseLowerCase then
    El.Name:=TJSString(lowercase(El.Name));
  Result:=El;
end;
{$ENDIF}

function TPasToJSConverter.CreateIdentifierExpr(AName: string; El: TPasElement;
  AContext: TConvertContext): TJSPrimaryExpressionIdent;

Var
  I : TJSPrimaryExpressionIdent;

begin
  I:=TJSPrimaryExpressionIdent(CreateElement(TJSPrimaryExpressionIdent,El));
  AName:=TransformVariableName(El,AName,AContext);
  I.Name:=TJSString(AName);
  Result:=I;
end;

function TPasToJSConverter.CreateDeclNameExpression(El: TPasElement;
  const Name: string; AContext: TConvertContext): TJSPrimaryExpressionIdent;
var
  CurName: String;
begin
  CurName:=TransformVariableName(El,Name,AContext);
  if (VarNameImplementation<>'') and (El.Parent.ClassType=TImplementationSection) then
    CurName:=VarNameImplementation+'.'+CurName
  else
    CurName:='this.'+CurName;
  Result:=TJSPrimaryExpressionIdent(CreateElement(TJSPrimaryExpressionIdent,El));
  Result.Name:=TJSString(CurName);
end;

function TPasToJSConverter.ConvertPrimitiveExpression(El: TPrimitiveExpr;
  AContext: TConvertContext): TJSElement;

Var
  L : TJSLiteral;
  Number : TJSNumber;
  ConversionError : Integer;
  i: Int64;
  S: String;
begin
  {$IFDEF VerbosePas2JS}
  str(El.Kind,S);
  writeln('TPasToJSConverter.ConvertPrimitiveExpression El=',GetObjName(El),' Context=',GetObjName(AContext),' El.Kind=',S);
  {$ENDIF}
  Result:=Nil;
  case El.Kind of
    pekString:
      Result:=CreateLiteralJSString(El,TransFormStringLiteral(El,AContext,El.Value));
    pekNumber:
      begin
      case El.Value[1] of
      '0'..'9':
        begin
        Val(El.Value,Number,ConversionError);
        if ConversionError<>0 then
          DoError(20161024191248,nInvalidNumber,sInvalidNumber,[El.Value],El);
        L:=CreateLiteralNumber(El,Number);
        if El.Value[1] in ['0'..'9'] then
          L.Value.CustomValue:=TJSString(El.Value);
        end;
      '$','&','%':
        begin
          i:=StrToInt64Def(El.Value,-1);
          if i<0 then
            DoError(20161024224442,nInvalidNumber,sInvalidNumber,[El.Value],El);
          Number:=i;
          if Number<>i then
            // number was rounded -> we lost precision
            DoError(20161024230812,nInvalidNumber,sInvalidNumber,[El.Value],El);
          L:=CreateLiteralNumber(El,Number);
          S:=copy(El.Value,2,length(El.Value));
          case El.Value[1] of
          '$': S:='0x'+S;
          '&': if TargetProcessor=pECMAScript5 then
                 S:='0'+S
               else
                 S:='0o'+S;
          '%': if TargetProcessor=pECMAScript5 then
                 S:=''
               else
                 S:='0b'+S;
          end;
          L.Value.CustomValue:=TJSString(S);
        end;
      else
        DoError(20161024223232,nInvalidNumber,sInvalidNumber,[El.Value],El);
      end;
      Result:=L;
      end;
    pekIdent:
      Result:=ConvertIdentifierExpr(El,AContext);
    else
      RaiseNotSupported(El,AContext,20161024222543);
  end;
end;

function TPasToJSConverter.ConvertIdentifierExpr(El: TPrimitiveExpr;
  AContext: TConvertContext): TJSElement;
var
  Decl: TPasElement;
  Name: String;
  Ref: TResolvedReference;
  Call: TJSCallExpression;
  Proc: TPasProcedure;
  BuiltInProc: TResElDataBuiltInProc;
  Prop: TPasProperty;
  ImplicitCall: Boolean;
  AssignContext: TAssignContext;
  Arg: TPasArgument;
  ParamContext: TParamContext;
  ConstData: TP2JConstExprData;
  ResolvedEl: TPasResolverResult;
  ProcType: TPasProcedureType;
  aVar: TPasVariable;
begin
  Result:=nil;
  if AContext=nil then ;
  if El.Kind<>pekIdent then
    RaiseInconsistency(20161024191255);
  if El.CustomData is TResolvedReference then
    begin
    Ref:=TResolvedReference(El.CustomData);
    Decl:=Ref.Declaration;
    if [rrfNewInstance,rrfFreeInstance]*Ref.Flags<>[] then
      begin
      // call constructor, destructor
      Result:=CreateFreeOrNewInstanceExpr(Ref,AContext);
      exit;
      end;

    Prop:=nil;
    AssignContext:=nil;
    ImplicitCall:=rrfImplicitCallWithoutParams in Ref.Flags;

    if Decl.ClassType=TPasProperty then
      begin
      // Decl is a property -> redirect to getter/setter
      Prop:=TPasProperty(Decl);
      case AContext.Access of
        caAssign:
          begin
          Decl:=AContext.Resolver.GetPasPropertySetter(Prop);
          if Decl is TPasProcedure then
            begin
            AssignContext:=AContext.AccessContext as TAssignContext;
            if AssignContext.Call<>nil then
              RaiseNotSupported(El,AContext,20170206000310);
            AssignContext.PropertyEl:=Prop;
            AssignContext.Setter:=Decl;
            Call:=CreateCallExpression(El);
            AssignContext.Call:=Call;
            Call.Expr:=CreateReferencePathExpr(Decl,AContext,false,Ref);
            Call.Args.Elements.AddElement.Expr:=AssignContext.RightSide;
            AssignContext.RightSide:=nil;
            Result:=Call;
            exit;
            end;
          end;
        caRead:
          begin
          Decl:=AContext.Resolver.GetPasPropertyGetter(Prop);
          if (Decl is TPasFunction) and (Prop.Args.Count=0) then
            ImplicitCall:=true;
          end;
        else
          RaiseNotSupported(El,AContext,20170213212623);
      end;
      end
    else if Decl.ClassType=TPasArgument then
      begin
      Arg:=TPasArgument(Decl);
      if Arg.Access in [argVar,argOut] then
        begin
        // Arg is a reference object
        case AContext.Access of
          caRead:
            begin
            // create arg.get()
            Call:=CreateCallExpression(El);
            Call.Expr:=CreateDotExpression(El,
              CreateIdentifierExpr(Arg.Name,Arg,AContext),
              CreateBuiltInIdentifierExpr(TempRefObjGetterName));
            Result:=Call;
            exit;
            end;
          caAssign:
            begin
            // create arg.set(RHS)
            AssignContext:=AContext.AccessContext as TAssignContext;
            if AssignContext.Call<>nil then
              RaiseNotSupported(El,AContext,20170214120606);
            Call:=CreateCallExpression(El);
            AssignContext.Call:=Call;
            Call.Expr:=CreateDotExpression(El,
                          CreateIdentifierExpr(Arg.Name,Arg,AContext),
                          CreateBuiltInIdentifierExpr(TempRefObjSetterName));
            Call.Args.Elements.AddElement.Expr:=AssignContext.RightSide;
            AssignContext.RightSide:=nil;
            Result:=Call;
            exit;
            end;
          caByReference:
            begin
            // simply pass the reference
            ParamContext:=AContext.AccessContext as TParamContext;
            ParamContext.ReusingReference:=true;
            Result:=CreateIdentifierExpr(Arg.Name,Arg,AContext);
            exit;
            end;
          else
            RaiseNotSupported(El,AContext,20170214120739);
        end;
        end;
      end;

    //writeln('TPasToJSConverter.ConvertPrimitiveExpression pekIdent TResolvedReference ',GetObjName(Ref.Declaration),' ',GetObjName(Ref.Declaration.CustomData));
    if Decl.CustomData is TResElDataBuiltInProc then
      begin
      BuiltInProc:=TResElDataBuiltInProc(Decl.CustomData);
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertPrimitiveExpression ',Decl.Name,' ',ResolverBuiltInProcNames[BuiltInProc.BuiltIn]);
      {$ENDIF}
      case BuiltInProc.BuiltIn of
        bfBreak: Result:=ConvertBuiltInBreak(El,AContext);
        bfContinue: Result:=ConvertBuiltInContinue(El,AContext);
        bfExit: Result:=ConvertBuiltInExit(El,AContext);
      else
        RaiseNotSupported(El,AContext,20161130164955,'built in proc '+ResolverBuiltInProcNames[BuiltInProc.BuiltIn]);
      end;
      if Result=nil then
        RaiseInconsistency(20170214120048);
      exit;
      end;

    {$IFDEF VerbosePas2JS}
    writeln('TPasToJSConverter.ConvertIdentifierExpr ',GetObjName(El),' Decl=',GetObjName(Decl),' Decl.Parent=',GetObjName(Decl.Parent));
    {$ENDIF}
    if Decl is TPasModule then
      Name:=VarNameModules+'.'+TransformModuleName(TPasModule(Decl),AContext)
    else if (Decl is TPasFunctionType) and (CompareText(ResolverResultVar,El.Value)=0) then
      Name:=ResolverResultVar
    else if Decl.ClassType=TPasEnumValue then
      begin
      if UseEnumNumbers then
        begin
        Result:=CreateLiteralNumber(El,(Decl.Parent as TPasEnumType).Values.IndexOf(Decl));
        exit;
        end
      else
        begin
        // enums always need the full path
        Name:=CreateReferencePath(Decl,AContext,rpkPathAndName,true);
        end;
      end
    else if (Decl is TPasProcedure) and (TPasProcedure(Decl).LibrarySymbolName<>nil) then
      begin
      // an external function -> use the literal
      Proc:=TPasProcedure(Decl);
      ConstData:=TP2JConstExprData(GetElementData(Proc.LibrarySymbolName,TP2JConstExprData));
      if ConstData=nil then
        RaiseInconsistency(20170215131352);
      Name:=String(ConstData.Value.AsString);
      end
    else if (Decl is TPasVariable) and (TPasVariable(Decl).ExportName<>nil) then
      begin
      // an external variable -> use the literal
      aVar:=TPasVariable(Decl);
      ConstData:=TP2JConstExprData(GetElementData(aVar.ExportName,TP2JConstExprData));
      if ConstData=nil then
        RaiseInconsistency(20170227091555);
      Name:=String(ConstData.Value.AsString);
      end
    else
      Name:=CreateReferencePath(Decl,AContext,rpkPathAndName,false,Ref);
    if Result=nil then
      Result:=CreateBuiltInIdentifierExpr(Name);

    if ImplicitCall then
      begin
      // create a call with default parameters
      ProcType:=nil;
      if Decl is TPasProcedure then
        ProcType:=TPasProcedure(Decl).ProcType
      else
        begin
        AContext.Resolver.ComputeElement(El,ResolvedEl,[rcNoImplicitProc]);
        if ResolvedEl.TypeEl is TPasProcedureType then
          ProcType:=TPasProcedureType(ResolvedEl.TypeEl)
        else
          RaiseNotSupported(El,AContext,20170217005025);
        end;

      Call:=nil;
      try
        CreateProcedureCall(Call,nil,ProcType,AContext);
        Call.Expr:=Result;
        Result:=Call;
      finally
        if Result<>Call then
          Call.Free;
      end;
      end;
    end
  else if AContext.Resolver<>nil then
    RaiseIdentifierNotFound(El.Value,El,20161024191306)
  else
    // simple mode
    Result:=CreateIdentifierExpr(El.Value,El,AContext);
end;

function TPasToJSConverter.ConvertBoolConstExpression(El: TBoolConstExpr;
  AContext: TConvertContext): TJSElement;

begin
  if AContext=nil then ;
  Result:=CreateLiteralBoolean(El,El.Value);
end;

function TPasToJSConverter.ConvertNilExpr(El: TNilExpr;
  AContext: TConvertContext): TJSElement;
begin
  if AContext=nil then ;
  Result:=CreateLiteralNull(El);
end;

function TPasToJSConverter.ConvertInheritedExpression(El: TInheritedExpr;
  AContext: TConvertContext): TJSElement;

  function CreateAncestorCall(ParentEl: TPasElement; Apply: boolean;
    AncestorProc: TPasProcedure; ParamsExpr: TParamsExpr): TJSElement;
  var
    FunName: String;
    Call: TJSCallExpression;
  begin
    Result:=nil;
    FunName:=CreateReferencePath(AncestorProc,AContext,rpkPathAndName,true);
    if Apply then
      // create "ancestor.funcname.apply(this,arguments)"
      FunName:=FunName+'.apply'
    else
      // create "ancestor.funcname.call(this,param1,param2,...)"
      FunName:=FunName+'.call';
    Call:=nil;
    try
      Call:=CreateCallExpression(ParentEl);
      Call.Expr:=CreateBuiltInIdentifierExpr(FunName);
      Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr('this');
      if Apply then
        Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr('arguments')
      else
        CreateProcedureCall(Call,ParamsExpr,AncestorProc.ProcType,AContext);
      Result:=Call;
    finally
      if Result=nil then
        Call.Free;
    end;
  end;

var
  Right: TPasExpr;
  Ref: TResolvedReference;
  PrimExpr: TPrimitiveExpr;
  AncestorProc: TPasProcedure;
  ParamsExpr: TParamsExpr;
begin
  Result:=nil;
  {$IFDEF EnableOldClass}
  if AContext=nil then ;
  Result := CreateIdentifierExpr('_super',El);
  {$ELSE}
  if (El.Parent is TBinaryExpr) and (TBinaryExpr(El.Parent).OpCode=eopNone)
      and (TBinaryExpr(El.Parent).left=El) then
    begin
    // "inherited <name>"
    AncestorProc:=nil;
    ParamsExpr:=nil;
    Right:=TBinaryExpr(El.Parent).right;
    if Right.ClassType=TPrimitiveExpr then
      begin
      PrimExpr:=TPrimitiveExpr(Right);
      Ref:=PrimExpr.CustomData as TResolvedReference;
      if rrfImplicitCallWithoutParams in Ref.Flags then
        begin
        // inherited <function>
        // -> create "AncestorProc.call(this,defaultargs)"
        AncestorProc:=Ref.Declaration as TPasProcedure;
        end
      else
        begin
        // inherited <varname>
        // all variables have unique names -> simply access it
        Result:=ConvertPrimitiveExpression(PrimExpr,AContext);
        exit;
        end;
      end
    else if Right.ClassType=TParamsExpr then
      begin
      ParamsExpr:=TParamsExpr(Right);
      if ParamsExpr.Kind=pekFuncParams then
        begin
        if ParamsExpr.Value is TPrimitiveExpr then
          begin
          // inherited <function>(args)
          // -> create "AncestorProc.call(this,args,defaultargs)"
          PrimExpr:=TPrimitiveExpr(ParamsExpr.Value);
          Ref:=PrimExpr.CustomData as TResolvedReference;
          AncestorProc:=Ref.Declaration as TPasProcedure;
          end;
        end
      else
        begin
        // inherited <varname>[]
        // all variables have unique names -> simply access it
        Result:=ConvertElement(Right,AContext);
        exit;
        end;
      end;
    if AncestorProc=nil then
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertInheritedExpression Right=',GetObjName(Right));
      {$ENDIF}
      RaiseNotSupported(El,AContext,20170201190824);
      end;
    //writeln('TPasToJSConverter.ConvertInheritedExpression Func=',GetObjName(FuncContext.PasElement));
    Result:=CreateAncestorCall(Right,false,AncestorProc,ParamsExpr);
    end
  else
    begin
    // "inherited;"
    if El.CustomData=nil then
      exit; // "inherited;" when there is no AncestorProc proc -> silently ignore
    // create "AncestorProc.apply(this,arguments)"
    Ref:=TResolvedReference(El.CustomData);
    AncestorProc:=Ref.Declaration as TPasProcedure;
    Result:=CreateAncestorCall(El,true,AncestorProc,nil);
    end;
  {$ENDIF}
end;

function TPasToJSConverter.ConvertSelfExpression(El: TSelfExpr;
  AContext: TConvertContext): TJSElement;

begin
  if AContext=nil then ;
  Result:=TJSPrimaryExpressionThis(CreateElement(TJSPrimaryExpressionThis,El));
end;

function TPasToJSConverter.ConvertParamsExpression(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
begin
  Result:=Nil;
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertParamsExpression ',GetObjName(El),' El.Kind=',ExprKindNames[El.Kind]);
  {$ENDIF}
  Case El.Kind of
    pekFuncParams:
      Result:=ConvertFuncParams(El,AContext);
    pekArrayParams:
      Result:=ConvertArrayParams(El,AContext);
    pekSet:
      Result:=ConvertSetLiteral(El,AContext);
  else
    RaiseNotSupported(El,AContext,20170209103235,ExprKindNames[El.Kind]);
  end;
end;

function TPasToJSConverter.ConvertArrayParams(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
var
  ArgContext: TConvertContext;

  function GetValueReference: TResolvedReference;
  var
    Value: TPasExpr;
  begin
    Result:=nil;
    Value:=El.Value;
    if (Value.ClassType=TPrimitiveExpr)
        and (Value.CustomData is TResolvedReference) then
      exit(TResolvedReference(Value.CustomData));
  end;

  procedure ConvertStringBracket;
  var
    Call: TJSCallExpression;
    Param: TPasExpr;
    Expr: TJSAdditiveExpressionMinus;
    DotExpr: TJSDotMemberExpression;
    AssignContext: TAssignContext;
    Elements: TJSArrayLiteralElements;
    AssignSt: TJSSimpleAssignStatement;
    OldAccess: TCtxAccess;
  begin
    Param:=El.Params[0];
    case AContext.Access of
    caAssign:
      begin
      // s[index] := value  ->  s = rtl.setCharAt(s,index,value)
      AssignContext:=AContext.AccessContext as TAssignContext;
      AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
      try
        OldAccess:=AContext.Access;
        AContext.Access:=caRead;
        AssignSt.LHS:=ConvertElement(El.Value,AContext);
        // rtl.setCharAt
        Call:=CreateCallExpression(El);
        AssignContext.Call:=Call;
        AssignSt.Expr:=Call;
        Elements:=Call.Args.Elements;
        Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameSetCharAt]);
        // first param  s
        Elements.AddElement.Expr:=ConvertElement(El.Value,AContext);
        AContext.Access:=OldAccess;
        // second param  index
        Elements.AddElement.Expr:=ConvertElement(Param,ArgContext);
        // third param  value
        Elements.AddElement.Expr:=AssignContext.RightSide;
        AssignContext.RightSide:=nil;
        Result:=AssignSt
      finally
        if Result=nil then
          AssignSt.Free;
      end;
      end;
    caRead:
      begin
      Call:=CreateCallExpression(El);
      Elements:=Call.Args.Elements;
      try
        // s[index]  ->  s.charAt(index-1)
        // add string accessor
        DotExpr:=TJSDotMemberExpression(CreateElement(TJSDotMemberExpression,El));
        Call.Expr:=DotExpr;
        DotExpr.MExpr:=ConvertElement(El.Value,AContext);
        DotExpr.Name:='charAt';

        // add parameter "index-1"
        Expr:=TJSAdditiveExpressionMinus(CreateElement(TJSAdditiveExpressionMinus,Param));
        Elements.AddElement.Expr:=Expr;
        Expr.A:=ConvertElement(Param,ArgContext);
        Expr.B:=CreateLiteralNumber(Param,1);
        Result:=Call;
      finally
        if Result=nil then
          Call.Free;
      end;
      end;
    else
      RaiseNotSupported(El,AContext,20170213213101);
    end;
  end;

  procedure ConvertArray(ArrayEl: TPasArrayType);
  var
    B, Sub: TJSBracketMemberExpression;
    i, ArgNo: Integer;
    Arg: TJSElement;
    OldAccess: TCtxAccess;
  begin
    B:=TJSBracketMemberExpression(CreateElement(TJSBracketMemberExpression,El));
    try
      // add read accessor
      OldAccess:=AContext.Access;
      AContext.Access:=caRead;
      B.MExpr:=ConvertElement(El.Value,AContext);
      AContext.Access:=OldAccess;

      Result:=B;
      ArgNo:=0;
      repeat
        // Note: dynamic array has length(ArrayEl.Ranges)=0
        for i:=1 to Max(length(ArrayEl.Ranges),1) do
          begin
          // add parameter
          AContext.Access:=caRead;
          Arg:=ConvertElement(El.Params[ArgNo],ArgContext);
          ArgContext.Access:=OldAccess;
          if B.Name<>nil then
            begin
            Sub:=B;
            B:=TJSBracketMemberExpression(CreateElement(TJSBracketMemberExpression,El));
            B.MExpr:=Sub;
            end;
          B.Name:=Arg;
          inc(ArgNo);
          if ArgNo>length(El.Params) then
            RaiseInconsistency(20170206180553);
          end;
        if ArgNo=length(El.Params) then
          break;
        // continue in sub array
        ArrayEl:=AContext.Resolver.ResolveAliasType(ArrayEl.ElType) as TPasArrayType;
      until false;
      Result:=B;
    finally
      if Result=nil then
        B.Free;
    end;
  end;

  procedure ConvertIndexProperty(Prop: TPasProperty; AContext: TConvertContext);
  var
    Call: TJSCallExpression;
    i: Integer;
    TargetArg: TPasArgument;
    Elements: TJSArrayLiteralElements;
    Arg: TJSElement;
    AccessEl: TPasElement;
    AssignContext: TAssignContext;
    OldAccess: TCtxAccess;
  begin
    Result:=nil;
    AssignContext:=nil;
    Call:=CreateCallExpression(El);
    try
      case AContext.Access of
      caAssign:
        begin
        AssignContext:=AContext.AccessContext as TAssignContext;
        AccessEl:=AContext.Resolver.GetPasPropertySetter(Prop);
        AssignContext.PropertyEl:=Prop;
        AssignContext.Setter:=AccessEl;
        AssignContext.Call:=Call;
        end;
      caRead:
        AccessEl:=AContext.Resolver.GetPasPropertyGetter(Prop);
      else
        RaiseNotSupported(El,AContext,20170213213317);
      end;
      Call.Expr:=CreateReferencePathExpr(AccessEl,AContext,false,GetValueReference);

      Elements:=Call.Args.Elements;
      OldAccess:=ArgContext.Access;
      // add params
      i:=0;
      while i<Prop.Args.Count do
        begin
        TargetArg:=TPasArgument(Prop.Args[i]);
        Arg:=CreateProcCallArg(El.Params[i],TargetArg,ArgContext);
        Elements.AddElement.Expr:=Arg;
        inc(i);
        end;
      // fill up default values
      while i<Prop.Args.Count do
        begin
        TargetArg:=TPasArgument(Prop.Args[i]);
        if TargetArg.ValueExpr=nil then
          begin
          {$IFDEF VerbosePas2JS}
          writeln('TPasToJSConverter.ConvertArrayParams.ConvertIndexProperty missing default value: Prop=',Prop.Name,' i=',i);
          {$ENDIF}
          RaiseInconsistency(20170206185126);
          end;
        AContext.Access:=caRead;
        Arg:=ConvertElement(TargetArg.ValueExpr,ArgContext);
        Elements.AddElement.Expr:=Arg;
        inc(i);
        end;
      // finally add as last parameter the value
      if AssignContext<>nil then
        begin
        Elements.AddElement.Expr:=AssignContext.RightSide;
        AssignContext.RightSide:=nil;
        end;

      ArgContext.Access:=OldAccess;
      Result:=Call;
    finally
      if Result=nil then
        begin
        if (AssignContext<>nil) and (AssignContext.Call=Call) then
          AssignContext.Call:=nil;
        Call.Free;
        end;
    end;
  end;

  procedure ConvertDefaultProperty(Prop: TPasProperty);
  var
    DotContext: TDotContext;
    Left, Right: TJSElement;
    OldAccess: TCtxAccess;
  begin
    DotContext:=nil;
    Left:=nil;
    Right:=nil;
    try
      OldAccess:=AContext.Access;
      AContext.Access:=caRead;
      Left:=ConvertElement(El.Value,AContext);
      AContext.Access:=OldAccess;

      DotContext:=TDotContext.Create(El.Value,Left,AContext);
      AContext.Resolver.ComputeElement(El.Value,DotContext.LeftResolved,[]);
      ConvertIndexProperty(Prop,DotContext);
      Right:=Result;
      Result:=nil;
    finally
      DotContext.Free;
      if Right=nil then
        Left.Free;
    end;
    Result:=CreateDotExpression(El,Left,Right);
  end;

Var
  ResolvedEl: TPasResolverResult;
  TypeEl: TPasType;
  ClassScope: TPasClassScope;
  B: TJSBracketMemberExpression;
  OldAccess: TCtxAccess;
begin
  if El.Kind<>pekArrayParams then
    RaiseInconsistency(20170209113713);
  ArgContext:=AContext;
  while ArgContext is TDotContext do
    ArgContext:=ArgContext.Parent;
  if AContext.Resolver=nil then
    begin
    // without Resolver
    if Length(El.Params)<>1 then
      RaiseNotSupported(El,AContext,20170207151325,'Cannot convert 2-dim arrays');
    B:=TJSBracketMemberExpression(CreateElement(TJSBracketMemberExpression,El));
    try
      // add reference
      OldAccess:=AContext.Access;
      AContext.Access:=caRead;
      B.MExpr:=ConvertElement(El.Value,AContext);

      // add parameter
      OldAccess:=ArgContext.Access;
      ArgContext.Access:=caRead;
      B.Name:=ConvertElement(El.Params[0],ArgContext);
      ArgContext.Access:=OldAccess;

      Result:=B;
    finally
      if Result=nil then
        B.Free;
    end;
    exit;
    end;
  // has Resolver
  AContext.Resolver.ComputeElement(El.Value,ResolvedEl,[]);
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertArrayParams Value=',GetResolverResultDesc(ResolvedEl));
  {$ENDIF}
  if ResolvedEl.BaseType in btAllStrings then
    ConvertStringBracket
  else if (ResolvedEl.IdentEl is TPasProperty)
      and (TPasProperty(ResolvedEl.IdentEl).Args.Count>0) then
    ConvertIndexProperty(TPasProperty(ResolvedEl.IdentEl),AContext)
  else if ResolvedEl.BaseType=btContext then
    begin
    TypeEl:=ResolvedEl.TypeEl;
    if TypeEl.ClassType=TPasClassType then
      begin
      ClassScope:=TypeEl.CustomData as TPasClassScope;
      if ClassScope.DefaultProperty=nil then
        RaiseInconsistency(20170206180448);
      ConvertDefaultProperty(ClassScope.DefaultProperty);
      end
    else if TypeEl.ClassType=TPasClassOfType then
      begin
      ClassScope:=TPasClassOfType(TypeEl).DestType.CustomData as TPasClassScope;
      if ClassScope.DefaultProperty=nil then
        RaiseInconsistency(20170206180503);
      ConvertDefaultProperty(ClassScope.DefaultProperty);
      end
    else if TypeEl.ClassType=TPasArrayType then
      ConvertArray(TPasArrayType(TypeEl))
    else
      RaiseNotSupported(El,AContext,20170206181220,GetResolverResultDesc(ResolvedEl));
    end
  else
    RaiseNotSupported(El,AContext,20170206180222);
end;

function TPasToJSConverter.ConvertFuncParams(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
var
  Ref: TResolvedReference;
  Decl: TPasElement;
  BuiltInProc: TResElDataBuiltInProc;
  TargetProcType: TPasProcedureType;
  Call: TJSCallExpression;
  Elements: TJSArrayLiteralElements;
  E: TJSArrayLiteral;
  OldAccess: TCtxAccess;
  DeclResolved: TPasResolverResult;
begin
  Result:=nil;
  if El.Kind<>pekFuncParams then
    RaiseInconsistency(20170209113515);
  //writeln('TPasToJSConverter.ConvertFuncParams START pekFuncParams ',GetObjName(El.CustomData),' ',GetObjName(El.Value.CustomData));
  Call:=nil;
  Elements:=nil;
  TargetProcType:=nil;
  if El.Value.CustomData is TResolvedReference then
    begin
    Ref:=TResolvedReference(El.Value.CustomData);
    Decl:=Ref.Declaration;
    //writeln('TPasToJSConverter.ConvertFuncParams pekFuncParams TResolvedReference ',GetObjName(Ref.Declaration),' ',GetObjName(Ref.Declaration.CustomData));
    if Decl.CustomData is TResElDataBuiltInProc then
      begin
      BuiltInProc:=TResElDataBuiltInProc(Decl.CustomData);
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertFuncParams ',Decl.Name,' ',ResolverBuiltInProcNames[BuiltInProc.BuiltIn]);
      {$ENDIF}
      case BuiltInProc.BuiltIn of
        bfLength: Result:=ConvertBuiltInLength(El,AContext);
        bfSetLength: Result:=ConvertBuiltInSetLength(El,AContext);
        bfInclude: Result:=ConvertBuiltInExcludeInclude(El,AContext,true);
        bfExclude: Result:=ConvertBuiltInExcludeInclude(El,AContext,false);
        bfExit: Result:=ConvertBuiltInExit(El,AContext);
        bfInc,
        bfDec: Result:=ConvertBuiltInIncDec(El,AContext);
        bfAssigned: Result:=ConvertBuiltInAssigned(El,AContext);
        bfOrd: Result:=ConvertBuiltInOrd(El,AContext);
        bfLow: Result:=ConvertBuiltInLow(El,AContext);
        bfHigh: Result:=ConvertBuiltInHigh(El,AContext);
        bfPred: Result:=ConvertBuiltInPred(El,AContext);
        bfSucc: Result:=ConvertBuiltInSucc(El,AContext);
      else
        RaiseNotSupported(El,AContext,20161130164955,'built in proc '+ResolverBuiltInProcNames[BuiltInProc.BuiltIn]);
      end;
      if Result=nil then
        RaiseInconsistency(20170210121932);
      exit;
      end
    else if Decl is TPasProcedure then
      TargetProcType:=TPasProcedure(Decl).ProcType
    else if (Decl.ClassType=TPasEnumType)
        or (Decl.ClassType=TPasClassType)
        or (Decl.ClassType=TPasClassOfType) then
      begin
      // typecast:
      //  EnumType(value) -> value
      //  ClassType(value) -> value
      //  ClassOfType(value) -> value
      Result:=ConvertElement(El.Params[0],AContext);
      exit;
      end
    else if (Decl is TPasVariable) then
      begin
      AContext.Resolver.ComputeElement(Decl,DeclResolved,[rcType]);
      if DeclResolved.TypeEl is TPasProcedureType then
        TargetProcType:=TPasProcedureType(DeclResolved.TypeEl)
      else
        RaiseNotSupported(El,AContext,20170217115244);
      end
    else if (Decl.ClassType=TPasProcedureType)
        or (Decl.ClassType=TPasFunctionType) then
      begin
      TargetProcType:=TPasProcedureType(Decl);
      end
    else
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertFuncParams El=',GetObjName(El),' Decl=',GetObjName(Decl));
      {$ENDIF}
      RaiseNotSupported(El,AContext,20170215114337);
      end;
    if [rrfNewInstance,rrfFreeInstance]*Ref.Flags<>[] then
      // call constructor, destructor
      Call:=CreateFreeOrNewInstanceExpr(Ref,AContext);
    end;
  if Call=nil then
    begin
    Call:=CreateCallExpression(El);
    Elements:=Call.Args.Elements;
    end;
  OldAccess:=AContext.Access;
  try
    AContext.Access:=caRead;
    if Call.Expr=nil then
      Call.Expr:=ConvertElement(El.Value,AContext);
    if Call.Args=nil then
      begin
      // append ()
      Call.Args:=TJSArguments(CreateElement(TJSArguments,El));
      Elements:=Call.Args.Elements;
      end
    else if Elements=nil then
      begin
      // insert array parameter [], e.g. this.TObject.$create("create",[])
      Elements:=Call.Args.Elements;
      E:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El));
      Elements.AddElement.Expr:=E;
      Elements:=TJSArrayLiteral(E).Elements;
      end;
    CreateProcedureCallArgs(Elements,El,TargetProcType,AContext);
    if Elements.Count=0 then
      begin
      Call.Args.Free;
      Call.Args:=nil;
      end;
    Result:=Call;
  finally
    AContext.Access:=OldAccess;
    if Result=nil then
      Call.Free;
  end;
end;

function TPasToJSConverter.ConvertSetLiteral(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
var
  Call: TJSCallExpression;
  ArgContext: TConvertContext;
  i: Integer;
  Arg: TJSElement;
  ArgEl: TPasExpr;
begin
  if El.Kind<>pekSet then
    RaiseInconsistency(20170209112737);
  if AContext.Access<>caRead then
    DoError(20170209112926,nCantWriteSetLiteral,sCantWriteSetLiteral,[],El);
  if length(El.Params)=0 then
    Result:=TJSObjectLiteral(CreateElement(TJSObjectLiteral,El))
  else
    begin
    Result:=nil;
    ArgContext:=AContext;
    while ArgContext is TDotContext do
      ArgContext:=ArgContext.Parent;
    Call:=CreateCallExpression(El);
    try
      Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameSet_Create]);
      for i:=0 to length(El.Params)-1 do
        begin
        ArgEl:=El.Params[i];
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.ConvertSetLiteral ',i,' El.Params[i]=',GetObjName(ArgEl));
        {$ENDIF}
        if (ArgEl.ClassType=TBinaryExpr) and (TBinaryExpr(ArgEl).Kind=pekRange) then
          begin
          // range -> add three parameters: null,left,right
          // ToDo: error if left>right
          // add null
          Call.Args.Elements.AddElement.Expr:=CreateLiteralNull(ArgEl);
          // add left
          Arg:=ConvertElement(TBinaryExpr(ArgEl).left,ArgContext);
          Call.Args.Elements.AddElement.Expr:=Arg;
          // add right
          Arg:=ConvertElement(TBinaryExpr(ArgEl).right,ArgContext);
          Call.Args.Elements.AddElement.Expr:=Arg;
          end
        else
          begin
          Arg:=ConvertElement(ArgEl,ArgContext);
          Call.Args.Elements.AddElement.Expr:=Arg;
          end;
        end;
      Result:=Call;
    finally
      if Result=nil then
        Call.Free;
    end;
    end;
end;

function TPasToJSConverter.ConvertBuiltInLength(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// length(dynarray) -> array.length
// length(staticarray) -> number
// length(string) -> string.length
var
  Arg: TJSElement;
  Param: TPasExpr;
  ParamResolved, RangeResolved: TPasResolverResult;
  Ranges: TPasExprArray;
begin
  Result:=nil;
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ParamResolved,[]);
  if ParamResolved.BaseType=btContext then
    begin
    if ParamResolved.TypeEl is TPasArrayType then
      begin
      Ranges:=TPasArrayType(ParamResolved.TypeEl).Ranges;
      if length(Ranges)>0 then
        begin
        // static array
        if length(Ranges)>1 then
          RaiseNotSupported(El,AContext,20170223131042);
        AContext.Resolver.ComputeElement(Ranges[0],RangeResolved,[rcConstant]);
        if RangeResolved.BaseType=btContext then
          begin
          if RangeResolved.IdentEl is TPasEnumType then
            begin
            Result:=CreateLiteralNumber(El,TPasEnumType(RangeResolved.IdentEl).Values.Count);
            exit;
            end;
          end
        else if RangeResolved.BaseType=btBoolean then
          begin
          Result:=CreateLiteralNumber(El,2);
          exit;
          end;
        end;
      end;
    end;

  // default: Param.length
  Arg:=ConvertElement(Param,AContext);
  Result:=CreateDotExpression(El,Arg,CreateBuiltInIdentifierExpr('length'));
end;

function TPasToJSConverter.ConvertBuiltInSetLength(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// convert "SetLength(a,Len)" to "a = rtl.arraySetLength(a,Len)"
var
  Param0: TPasExpr;
  ResolvedParam0: TPasResolverResult;
  ArrayType: TPasArrayType;
  Call: TJSCallExpression;
  ValInit, Arg, LHS: TJSElement;
  AssignSt: TJSSimpleAssignStatement;
  AssignContext: TAssignContext;
  ElType: TPasType;
begin
  Result:=nil;
  Param0:=El.Params[0];
  if AContext.Access<>caRead then
    RaiseInconsistency(20170213213621);
  AContext.Resolver.ComputeElement(Param0,ResolvedParam0,[rcNoImplicitProc]);
  {$IFDEF VerbosePasResolver}
  writeln('TPasToJSConverter.ConvertBuiltInSetLength ',GetResolverResultDesc(ResolvedParam0));
  {$ENDIF}
  if ResolvedParam0.TypeEl is TPasArrayType then
    begin
    // SetLength(array,newlength)
    // ->  array = rtl.setArrayLength(array,newlength,initvalue)
    ArrayType:=TPasArrayType(ResolvedParam0.TypeEl);
    {$IFDEF VerbosePasResolver}
    writeln('TPasToJSConverter.ConvertBuiltInSetLength array');
    {$ENDIF}
    LHS:=nil;
    AssignContext:=TAssignContext.Create(El,nil,AContext);
    try
      AContext.Resolver.ComputeElement(El.Value,AssignContext.LeftResolved,[rcNoImplicitProc]);
      AssignContext.RightResolved:=ResolvedParam0;

      // create right side
      // rtl.setArrayLength()
      Call:=CreateCallExpression(Param0);
      AssignContext.RightSide:=Call;
      Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameArray_SetLength]);
      // 1st param: array
      Call.Args.Elements.AddElement.Expr:=ConvertElement(Param0,AContext);
      // 2nd param: newlength
      Call.Args.Elements.AddElement.Expr:=ConvertElement(El.Params[1],AContext);
      // 3rd param: default value
      ElType:=AContext.Resolver.ResolveAliasType(ArrayType.ElType);
      if ElType.ClassType=TPasRecordType then
        ValInit:=CreateReferencePathExpr(ElType,AContext)
      else
        ValInit:=CreateValInit(ElType,nil,Param0,AContext);
      Call.Args.Elements.AddElement.Expr:=ValInit;

      // create left side:  array =
      LHS:=ConvertElement(Param0,AssignContext);
      if AssignContext.Call<>nil then
        begin
        // array has a setter -> right side was already added as parameter
        if AssignContext.RightSide<>nil then
          RaiseInconsistency(20170207215447);
        Result:=LHS;
        end
      else
        begin
        AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
        AssignSt.LHS:=LHS;
        AssignSt.Expr:=AssignContext.RightSide;
        AssignContext.RightSide:=nil;
        Result:=AssignSt;
        end;

    finally
      if Result=nil then
        LHS.Free;
      AssignContext.RightSide.Free;
      AssignContext.Free;
    end;
    end
  else if ResolvedParam0.BaseType=btString then
    begin
    // convert "SetLength(string,NewLen);" to "string.length == NewLen;"
    {$IFDEF VerbosePasResolver}
    writeln('TPasToJSConverter.ConvertBuiltInSetLength string');
    {$ENDIF}
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    try
      Arg:=ConvertElement(Param0,AContext);
      // left side: string.length
      AssignSt.LHS:=CreateDotExpression(El,Arg,CreateBuiltInIdentifierExpr('length'));
      // right side: newlength
      AssignSt.Expr:=ConvertElement(El.Params[1],AContext);
      Result:=AssignSt;
    finally
      if Result=nil then
        AssignSt.Free;
    end;
    end
  else
    RaiseNotSupported(El.Value,AContext,20170130141026,'setlength '+GetResolverResultDesc(ResolvedParam0));
end;

function TPasToJSConverter.ConvertBuiltInExcludeInclude(El: TParamsExpr;
  AContext: TConvertContext; IsInclude: boolean): TJSElement;
// convert "Include(aSet,Enum)" to "aSet=rtl.includeSet(aSet,Enum)"
var
  Call: TJSCallExpression;
  Param0: TPasExpr;
  AssignContext: TAssignContext;
  AssignSt: TJSSimpleAssignStatement;
  LHS: TJSElement;
  FunName: String;
begin
  Result:=nil;
  LHS:=nil;
  Param0:=El.Params[0];
  AssignContext:=TAssignContext.Create(El,nil,AContext);
  try
    AContext.Resolver.ComputeElement(Param0,AssignContext.LeftResolved,[rcNoImplicitProc]);
    AssignContext.RightResolved:=AssignContext.LeftResolved;

    // create right side  rtl.includeSet(aSet,Enum)
    Call:=CreateCallExpression(El);
    AssignContext.RightSide:=Call;
    if IsInclude then
      FunName:=FuncNameSet_Include
    else
      FunName:=FuncNameSet_Exclude;
    Call.Expr:=CreateMemberExpression([VarNameRTL,FunName]);
    Call.Args.Elements.AddElement.Expr:=ConvertElement(Param0,AContext);
    Call.Args.Elements.AddElement.Expr:=ConvertElement(El.Params[1],AContext);

    // create left side:  aSet =
    LHS:=ConvertElement(Param0,AssignContext);
    if AssignContext.Call<>nil then
      begin
      // set has a setter -> right side was already added as parameter
      if AssignContext.RightSide<>nil then
        RaiseInconsistency(20170301145100);
      Result:=LHS;
      end
    else
      begin
      AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
      AssignSt.LHS:=LHS;
      AssignSt.Expr:=AssignContext.RightSide;
      AssignContext.RightSide:=nil;
      Result:=AssignSt;
      end;
  finally
    if Result=nil then
      LHS.Free;
    AssignContext.RightSide.Free;
    AssignContext.Free;
  end;
end;

function TPasToJSConverter.ConvertBuiltInContinue(El: TPasExpr;
  AContext: TConvertContext): TJSElement;
begin
  if AContext=nil then;
  Result:=TJSContinueStatement(CreateElement(TJSContinueStatement,El));
end;

function TPasToJSConverter.ConvertBuiltInBreak(El: TPasExpr;
  AContext: TConvertContext): TJSElement;
begin
  if AContext=nil then;
  Result:=TJSBreakStatement(CreateElement(TJSBreakStatement,El));
end;

function TPasToJSConverter.ConvertBuiltInExit(El: TPasExpr;
  AContext: TConvertContext): TJSElement;
// convert "exit;" -> in a function: "return result;"  in a procedure: "return;"
// convert "exit(param);" -> "return param;"
var
  ProcEl: TPasElement;
begin
  Result:=TJSReturnStatement(CreateElement(TJSReturnStatement,El));
  if (El is TParamsExpr) and (length(TParamsExpr(El).Params)>0) then
    begin
    // with parameter. convert "exit(param);" -> "return param;"
    TJSReturnStatement(Result).Expr:=ConvertExpression(TParamsExpr(El).Params[0],AContext);
    end
  else
    begin
    // without parameter.
    ProcEl:=El.Parent;
    while not (ProcEl is TPasProcedure) do ProcEl:=ProcEl.Parent;
    if ProcEl is TPasFunction then
      // in a function, "return result;"
      TJSReturnStatement(Result).Expr:=CreateBuiltInIdentifierExpr(ResolverResultVar)
    else
      ; // in a procedure, "return;" which means "return undefined;"
    end;
end;

function TPasToJSConverter.ConvertBuiltInIncDec(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// convert inc(a,b) to a+=b
// convert dec(a,b) to a-=b
var
  AssignSt: TJSAssignStatement;
begin
  if CompareText((El.Value as TPrimitiveExpr).Value,'inc')=0 then
    AssignSt:=TJSAddEqAssignStatement(CreateElement(TJSAddEqAssignStatement,El))
  else
    AssignSt:=TJSSubEqAssignStatement(CreateElement(TJSSubEqAssignStatement,El));
  Result:=AssignSt;
  AssignSt.LHS:=ConvertExpression(El.Params[0],AContext);
  if length(El.Params)=1 then
    AssignSt.Expr:=CreateLiteralNumber(El,1)
  else
    AssignSt.Expr:=ConvertExpression(El.Params[1],AContext);
end;

function TPasToJSConverter.ConvertBuiltInAssigned(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// convert Assigned(value)  ->  value!=null
var
  NE: TJSEqualityExpressionNE;
  Param: TPasExpr;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210105235);
  Param:=El.Params[0];
  NE:=TJSEqualityExpressionNE(CreateElement(TJSEqualityExpressionNE,El));
  try
    NE.A:=ConvertElement(Param,AContext);
    NE.B:=CreateLiteralNull(El);
    Result:=NE;
  finally
    if Result=nil then
      NE.Free;
  end;
end;

function TPasToJSConverter.ConvertBuiltInOrd(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// ord(enum) -> enum
var
  ResolvedEl: TPasResolverResult;
  Param: TPasExpr;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210105235);
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ResolvedEl,[]);
  if ResolvedEl.BaseType=btContext then
    begin
    if ResolvedEl.TypeEl.ClassType=TPasEnumType then
      begin
      // ord(enum) -> enum
      Result:=ConvertElement(Param,AContext);
      exit;
      end;
    end;
  DoError(20170210105339,nExpectedXButFoundY,sExpectedXButFoundY,['enum',GetResolverResultDescription(ResolvedEl)],Param);
end;

function TPasToJSConverter.ConvertBuiltInLow(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// low(enumtype) -> first enumvalue
// low(set var) -> first enumvalue
// low(settype) -> first enumvalue
// low(array var) -> first index

  procedure CreateEnumValue(TypeEl: TPasEnumType);
  var
    EnumValue: TPasEnumValue;
  begin
    EnumValue:=TPasEnumValue(TypeEl.Values[0]);
    Result:=CreateReferencePathExpr(EnumValue,AContext);
  end;

var
  ResolvedEl, RangeResolved: TPasResolverResult;
  Param: TPasExpr;
  TypeEl: TPasType;
  Ranges: TPasExprArray;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210120659);
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ResolvedEl,[]);
  case ResolvedEl.BaseType of
    btContext:
      begin
      TypeEl:=ResolvedEl.TypeEl;
      if TypeEl.ClassType=TPasEnumType then
        begin
        CreateEnumValue(TPasEnumType(TypeEl));
        exit;
        end
      else if (TypeEl.ClassType=TPasSetType) then
        begin
        if TPasSetType(TypeEl).EnumType<>nil then
          begin
          TypeEl:=TPasSetType(TypeEl).EnumType;
          CreateEnumValue(TPasEnumType(TypeEl));
          exit;
          end;
        end
      else if TypeEl.ClassType=TPasArrayType then
        begin
        Ranges:=TPasArrayType(TypeEl).Ranges;
        if length(Ranges)=0 then
          begin
          Result:=CreateLiteralNumber(El,0);
          exit;
          end
        else if length(Ranges)=1 then
          begin
          AContext.Resolver.ComputeElement(Ranges[0],RangeResolved,[rcConstant]);
          if RangeResolved.BaseType=btContext then
            begin
            if RangeResolved.IdentEl is TPasEnumType then
              begin
              CreateEnumValue(TPasEnumType(RangeResolved.IdentEl));
              exit;
              end;
            end
          else if RangeResolved.BaseType=btBoolean then
            begin
            Result:=CreateLiteralBoolean(El,LowJSBoolean);
            exit;
            end;
          end;
        RaiseNotSupported(El,AContext,20170222231008);
        end;
      end;
    btChar,
    btWideChar:
      begin
      Result:=CreateLiteralJSString(El,#0);
      exit;
      end;
    btBoolean:
      begin
      Result:=CreateLiteralBoolean(El,LowJSBoolean);
      exit;
      end;
    btSet:
      begin
      TypeEl:=ResolvedEl.TypeEl;
      if TypeEl.ClassType=TPasEnumType then
        begin
        CreateEnumValue(TPasEnumType(TypeEl));
        exit;
        end;
      end;
  end;
  DoError(20170210110717,nExpectedXButFoundY,sExpectedXButFoundY,['enum or array',GetResolverResultDescription(ResolvedEl)],Param);
end;

function TPasToJSConverter.ConvertBuiltInHigh(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// high(enumtype) -> last enumvalue
// high(set var) -> last enumvalue
// high(settype) -> last enumvalue
// high(dynamic array) -> array.length-1
// high(static array) -> last index

  procedure CreateEnumValue(TypeEl: TPasEnumType);
  var
    EnumValue: TPasEnumValue;
  begin
    EnumValue:=TPasEnumValue(TypeEl.Values[TypeEl.Values.Count-1]);
    Result:=CreateReferencePathExpr(EnumValue,AContext);
  end;

var
  ResolvedEl, RangeResolved: TPasResolverResult;
  Param, Range: TPasExpr;
  TypeEl: TPasType;
  Arg: TJSElement;
  MinusExpr: TJSAdditiveExpressionMinus;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210120653);
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ResolvedEl,[]);
  case ResolvedEl.BaseType of
    btContext:
      begin
      TypeEl:=ResolvedEl.TypeEl;
      if TypeEl.ClassType=TPasEnumType then
        begin
        CreateEnumValue(TPasEnumType(TypeEl));
        exit;
        end
      else if (TypeEl.ClassType=TPasSetType) then
        begin
        if TPasSetType(TypeEl).EnumType<>nil then
          begin
          TypeEl:=TPasSetType(TypeEl).EnumType;
          CreateEnumValue(TPasEnumType(TypeEl));
          exit;
          end;
        end
      else if TypeEl.ClassType=TPasArrayType then
        begin
        if length(TPasArrayType(TypeEl).Ranges)=0 then
          begin
          // dynamic array -> Param.length-1
          Arg:=ConvertElement(Param,AContext);
          MinusExpr:=TJSAdditiveExpressionMinus(CreateElement(TJSAdditiveExpressionMinus,El));
          MinusExpr.A:=CreateDotExpression(Param,Arg,CreateBuiltInIdentifierExpr('length'));
          MinusExpr.B:=CreateLiteralNumber(El,1);
          Result:=MinusExpr;
          exit;
          end
        else if length(TPasArrayType(TypeEl).Ranges)=1 then
          begin
          // static array
          Range:=TPasArrayType(TypeEl).Ranges[0];
          AContext.Resolver.ComputeElement(Range,RangeResolved,[rcConstant]);
          if RangeResolved.BaseType=btContext then
            begin
            if RangeResolved.IdentEl is TPasEnumType then
              begin
              CreateEnumValue(TPasEnumType(RangeResolved.IdentEl));
              exit;
              end;
            end
          else if RangeResolved.BaseType=btBoolean then
            begin
            Result:=CreateLiteralBoolean(Param,HighJSBoolean);
            exit;
            end;
          end;
        RaiseNotSupported(El,AContext,20170222231101);
        end;
      end;
    btBoolean:
      begin
      Result:=CreateLiteralBoolean(Param,HighJSBoolean);
      exit;
      end;
    btSet:
      begin
      TypeEl:=ResolvedEl.TypeEl;
      if TypeEl.ClassType=TPasEnumType then
        begin
        CreateEnumValue(TPasEnumType(TypeEl));
        exit;
        end;
      end;
  end;
  DoError(20170210114139,nExpectedXButFoundY,sExpectedXButFoundY,['enum or array',GetResolverResultDescription(ResolvedEl)],Param);
end;

function TPasToJSConverter.ConvertBuiltInPred(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// pred(enumvalue) -> enumvalue-1
var
  ResolvedEl: TPasResolverResult;
  Param: TPasExpr;
  V: TJSElement;
  Expr: TJSAdditiveExpressionMinus;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210120648);
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ResolvedEl,[]);
  if (ResolvedEl.BaseType=btContext)
      and (ResolvedEl.TypeEl.ClassType=TPasEnumType) then
    begin
    V:=ConvertElement(Param,AContext);
    Expr:=TJSAdditiveExpressionMinus(CreateElement(TJSAdditiveExpressionMinus,El));
    Expr.A:=V;
    Expr.B:=CreateLiteralNumber(El,1);
    Result:=Expr;
    exit;
    end;
  DoError(20170210120039,nExpectedXButFoundY,sExpectedXButFoundY,['enum',GetResolverResultDescription(ResolvedEl)],Param);
end;

function TPasToJSConverter.ConvertBuiltInSucc(El: TParamsExpr;
  AContext: TConvertContext): TJSElement;
// pred(enumvalue) -> enumvalue-1
var
  ResolvedEl: TPasResolverResult;
  Param: TPasExpr;
  V: TJSElement;
  Expr: TJSAdditiveExpressionPlus;
begin
  Result:=nil;
  if AContext.Resolver=nil then
    RaiseInconsistency(20170210120645);
  Param:=El.Params[0];
  AContext.Resolver.ComputeElement(Param,ResolvedEl,[]);
  if (ResolvedEl.BaseType=btContext)
      and (ResolvedEl.TypeEl.ClassType=TPasEnumType) then
    begin
    V:=ConvertElement(Param,AContext);
    Expr:=TJSAdditiveExpressionPlus(CreateElement(TJSAdditiveExpressionPlus,El));
    Expr.A:=V;
    Expr.B:=CreateLiteralNumber(El,1);
    Result:=Expr;
    exit;
    end;
  DoError(20170210120626,nExpectedXButFoundY,sExpectedXButFoundY,['enum',GetResolverResultDescription(ResolvedEl)],Param);
end;

function TPasToJSConverter.ConvertRecordValues(El: TRecordValues;
  AContext: TConvertContext): TJSElement;

Var
  R :  TJSObjectLiteral;
  I : Integer;
  It : TRecordValuesItem;
  rel : TJSObjectLiteralElement;

begin
  R:=TJSObjectLiteral(CreateElement(TJSObjectLiteral,El));
  For I:=0 to Length(El.Fields)-1 do
    begin
    it:=El.Fields[i];
    Rel:=R.Elements.AddElement;
    Rel.Name:=TJSString(it.Name);
    Rel.Expr:=ConvertElement(it.ValueExp,AContext);
    end;
  Result:=R;
end;

function TPasToJSConverter.ConvertArrayValues(El: TArrayValues;
  AContext: TConvertContext): TJSElement;

Var
  R :  TJSArrayLiteral;
  I : Integer;
  rel : TJSArrayLiteralElement;

begin
  R:=TJSArrayLiteral(CreateElement(TJSObjectLiteral,El));
  For I:=0 to Length(El.Values)-1 do
    begin
    Rel:=R.Elements.AddElement;
    Rel.ElementIndex:=i;
    Rel.Expr:=ConvertElement(El.Values[i],AContext);
    end;
  Result:=R;
end;

function TPasToJSConverter.ConvertExpression(El: TPasExpr;
  AContext: TConvertContext): TJSElement;

begin
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertExpression El=',GetObjName(El),' Context=',GetObjName(AContext));
  {$ENDIF}
  Result:=Nil;
  if (El.ClassType=TUnaryExpr) then
    Result:=ConvertUnaryExpression(TUnaryExpr(El),AContext)
  else if (El.ClassType=TBinaryExpr) then
    Result:=ConvertBinaryExpression(TBinaryExpr(El),AContext)
  else if (El.ClassType=TPrimitiveExpr) then
    Result:=ConvertPrimitiveExpression(TPrimitiveExpr(El),AContext)
  else if (El.ClassType=TBoolConstExpr) then
    Result:=ConvertBoolConstExpression(TBoolConstExpr(El),AContext)
  else if (El.ClassType=TNilExpr) then
    Result:=ConvertNilExpr(TNilExpr(El),AContext)
  else if (El.ClassType=TInheritedExpr) then
    Result:=ConvertInheritedExpression(TInheritedExpr(El),AContext)
  else if (El.ClassType=TSelfExpr) then
    Result:=ConvertSelfExpression(TSelfExpr(El),AContext)
  else if (El.ClassType=TParamsExpr) then
    Result:=ConvertParamsExpression(TParamsExpr(El),AContext)
  else if (El.ClassType=TRecordValues) then
    Result:=ConvertRecordValues(TRecordValues(El),AContext)
  else
    RaiseNotSupported(El,AContext,20161024191314);
end;

function TPasToJSConverter.CreateBuiltInIdentifierExpr(AName: string
  ): TJSPrimaryExpressionIdent;
var
  Ident: TJSPrimaryExpressionIdent;
begin
  Ident:=TJSPrimaryExpressionIdent.Create(0,0);
  if UseLowerCase then
    AName:=LowerCase(AName);
  Ident.Name:=TJSString(AName);
  Result:=Ident;
end;

function TPasToJSConverter.CreateTypeDecl(El: TPasType;
  AContext: TConvertContext): TJSElement;

var
  ElClass: TClass;
begin
  Result:=Nil;
  ElClass:=El.ClassType;
  if ElClass=TPasClassType then
    Result := ConvertClassType(TPasClassType(El), AContext)
  else if ElClass=TPasRecordType then
    Result := ConvertRecordType(TPasRecordType(El), AContext)
  else if ElClass=TPasEnumType then
    Result := ConvertEnumType(TPasEnumType(El), AContext)
  else if (ElClass=TPasSetType) then
    begin
    if TPasSetType(El).IsPacked then
      DoError(20170222231613,nPasElementNotSupported,sPasElementNotSupported,
        ['packed'],El);
    end
  else if (ElClass=TPasAliasType)
      or (ElClass=TPasClassOfType) then
  else if (ElClass=TPasProcedureType)
       or (ElClass=TPasFunctionType) then
    begin
    if TPasProcedureType(El).IsNested then
      DoError(20170222231636,nPasElementNotSupported,sPasElementNotSupported,
        ['is nested'],El);
    if TPasProcedureType(El).CallingConvention<>ccDefault then
      DoError(20170222231532,nPasElementNotSupported,sPasElementNotSupported,
          [cCallingConventions[TPasProcedureType(El).CallingConvention]],El);
    end
  else if (ElClass=TPasArrayType) then
    begin
    if TPasArrayType(El).PackMode<>pmNone then
      DoError(20170222231648,nPasElementNotSupported,sPasElementNotSupported,
         ['packed'],El);
    end
  else
    begin
    {$IFDEF VerbosePas2JS}
    writeln('TPasToJSConverter.CreateTypeDecl El=',GetObjName(El));
    {$ENDIF}
    RaiseNotSupported(El,AContext,20170208144053);
    end;
end;

function TPasToJSConverter.CreateVarDecl(El: TPasVariable;
  AContext: TConvertContext): TJSElement;

Var
  C : TJSElement;
  V : TJSVariableStatement;
  AssignSt: TJSSimpleAssignStatement;
  Obj: TJSObjectLiteral;
  ObjLit: TJSObjectLiteralElement;
  LibSymbol: TJSValue;
  ConstData: TP2JConstExprData;

begin
  Result:=nil;
  if vmExternal in El.VarModifiers then
    begin
    // external: compute constant and do not add a declaration
    if El.LibraryName<>nil then
      DoError(20170227094227,nPasElementNotSupported,sPasElementNotSupported,
        ['library'],El.ExportName);
    if El.ExportName=nil then
      DoError(20170227100750,nMissingExternalName,sMissingExternalName,[],El);
    LibSymbol:=ComputeConst(El.ExportName,AContext);
    try
      if (LibSymbol.ValueType<>jstString) or (LibSymbol.AsString='') then
        DoError(20170227094343,nExpectedXButFoundY,sExpectedXButFoundY,['string literal',El.Name],El);
      ConstData:=TP2JConstExprData(CreateElementData(TP2JConstExprData,El.ExportName));
      ConstData.Value:=LibSymbol;
      LibSymbol:=nil;
    finally
      LibSymbol.Free;
    end;
    exit;
    end;
  if AContext is TObjectContext then
    begin
    // create 'A: initvalue'
    Obj:=TObjectContext(AContext).JSElement as TJSObjectLiteral;
    ObjLit:=Obj.Elements.AddElement;
    ObjLit.Name:=TJSString(TransformVariableName(El,AContext));
    ObjLit.Expr:=CreateVarInit(El,AContext);
    end
  else if AContext.IsSingleton then
    begin
    // create 'this.A=initvalue'
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    Result:=AssignSt;
    AssignSt.LHS:=CreateDeclNameExpression(El,El.Name,AContext);
    AssignSt.Expr:=CreateVarInit(El,AContext);
    end
  else
    begin
    // create 'var A=initvalue'
    C:=ConvertVariable(El,AContext);
    V:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
    V.A:=C;
    Result:=V;
    end;
end;

function TPasToJSConverter.CreateConstDecl(El: TPasConst;
  AContext: TConvertContext): TJSElement;
// Important: returns nil if const was added to higher context

Var
  AssignSt: TJSSimpleAssignStatement;
  Obj: TJSObjectLiteral;
  ObjLit: TJSObjectLiteralElement;
  ConstContext: TFunctionContext;
  C: TJSElement;
  V: TJSVariableStatement;
  Src: TJSSourceElements;
begin
  Result:=nil;
  if not AContext.IsSingleton then
    begin
    // local const are stored in interface/implementation
    ConstContext:=AContext.GetSingletonFunc;
    if not (ConstContext.JSElement is TJSSourceElements) then
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.CreateConstDecl ConstContext=',GetObjName(ConstContext),' JSElement=',GetObjName(ConstContext.JSElement));
      {$ENDIF}
      RaiseNotSupported(El,AContext,20170220153216);
      end;
    Src:=TJSSourceElements(ConstContext.JSElement);
    C:=ConvertVariable(El,AContext);
    V:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
    V.A:=C;
    AddToSourceElements(Src,V);
    end
  else if AContext is TObjectContext then
    begin
    // create 'A: initvalue'
    Obj:=TObjectContext(AContext).JSElement as TJSObjectLiteral;
    ObjLit:=Obj.Elements.AddElement;
    ObjLit.Name:=TJSString(TransformVariableName(El,AContext));
    ObjLit.Expr:=CreateVarInit(El,AContext);
    end
  else
    begin
    // create 'this.A=initvalue'
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    Result:=AssignSt;
    AssignSt.LHS:=CreateDeclNameExpression(El,El.Name,AContext);
    AssignSt.Expr:=CreateVarInit(El,AContext);
    end;
end;

function TPasToJSConverter.CreateSwitchStatement(El: TPasImplCaseOf;
  AContext: TConvertContext): TJSElement;
var
  SwitchEl: TJSSwitchStatement;
  JSCaseEl: TJSCaseElement;
  SubEl: TPasImplElement;
  St: TPasImplCaseStatement;
  ok: Boolean;
  i, j: Integer;
  BreakSt: TJSBreakStatement;
  BodySt: TJSElement;
  StList: TJSStatementList;
  Expr: TPasExpr;
begin
  Result:=nil;
  SwitchEl:=TJSSwitchStatement(CreateElement(TJSSwitchStatement,El));
  ok:=false;
  try
    SwitchEl.Cond:=ConvertExpression(El.CaseExpr,AContext);
    for i:=0 to El.Elements.Count-1 do
      begin
      SubEl:=TPasImplElement(El.Elements[i]);
      if not (SubEl is TPasImplCaseStatement) then
        continue;
      St:=TPasImplCaseStatement(SubEl);
      JSCaseEl:=nil;
      for j:=0 to St.Expressions.Count-1 do
        begin
        Expr:=TPasExpr(St.Expressions[j]);
        JSCaseEl:=SwitchEl.Cases.AddCase;
        JSCaseEl.Expr:=ConvertExpression(Expr,AContext);
        end;
      BodySt:=nil;
      if St.Body<>nil then
        BodySt:=ConvertElement(St.Body,AContext);
      // add break
      BreakSt:=TJSBreakStatement(CreateElement(TJSBreakStatement,St));
      if BodySt=nil then
        // no Pascal statement -> add only one 'break;'
        BodySt:=BreakSt
      else
        begin
        if (BodySt is TJSStatementList) then
          begin
          // list of statements -> append 'break;' to end
          StList:=TJSStatementList(BodySt);
          AddToStatementList(TJSStatementList(BodySt),StList,BreakSt,St);
          end
        else
          begin
          // single statement -> create list of old and 'break;'
          StList:=TJSStatementList(CreateElement(TJSStatementList,St));
          StList.A:=BodySt;
          StList.B:=BreakSt;
          BodySt:=StList;
          end;
        end;
      JSCaseEl.Body:=BodySt;
      end;
    if El.ElseBranch<>nil then
      begin
      JSCaseEl:=SwitchEl.Cases.AddCase;
      JSCaseEl.Body:=ConvertImplBlockElements(El.ElseBranch,AContext);
      SwitchEl.TheDefault:=JSCaseEl;
      end;
    ok:=true;
  finally
    if not ok then
      SwitchEl.Free;
  end;
  Result:=SwitchEl;
end;

function TPasToJSConverter.ConvertDeclarations(El: TPasDeclarations;
  AContext: TConvertContext): TJSElement;

Var
  E : TJSElement;
  SLFirst, SLLast: TJSStatementList;
  P: TPasElement;
  IsProcBody, IsFunction, IsAssembler: boolean;
  I : Integer;
  PasProc: TPasProcedure;
  ProcScope: TPasProcedureScope;
  ProcBody: TPasImplBlock;

  Procedure Add(NewEl: TJSElement);
  begin
    if AContext is TObjectContext then
      begin
      // NewEl is already added
      end
    else
      begin
      AddToStatementList(SLFirst,SLLast,NewEl,El);
      ConvertDeclarations:=SLFirst;
      end;
  end;

  Procedure AddFunctionResultInit;
  var
    VarSt: TJSVariableStatement;
    AssignSt: TJSSimpleAssignStatement;
    PasFun: TPasFunction;
    FunType: TPasFunctionType;
    ResultEl: TPasResultElement;
  begin
    PasFun:=El.Parent as TPasFunction;
    FunType:=PasFun.FuncType;
    ResultEl:=FunType.ResultEl;

    // add 'var result=initvalue'
    VarSt:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
    Add(VarSt);
    Result:=SLFirst;
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    VarSt.A:=AssignSt;
    AssignSt.LHS:=CreateBuiltInIdentifierExpr(ResolverResultVar);
    AssignSt.Expr:=CreateValInit(ResultEl.ResultType,nil,El,aContext);
  end;

  Procedure AddFunctionResultReturn;
  var
    RetSt: TJSReturnStatement;
  begin
    RetSt:=TJSReturnStatement(CreateElement(TJSReturnStatement,El));
    RetSt.Expr:=CreateBuiltInIdentifierExpr(ResolverResultVar);
    Add(RetSt);
  end;

begin
  Result:=nil;
  {
    TPasDeclarations = class(TPasElement)
    TPasSection = class(TPasDeclarations)
    TInterfaceSection = class(TPasSection)
    TImplementationSection = class(TPasSection)
    TProgramSection = class(TImplementationSection)
    TLibrarySection = class(TImplementationSection)
    TProcedureBody = class(TPasDeclarations)
  }

  SLFirst:=nil;
  SLLast:=nil;
  IsProcBody:=(El is TProcedureBody) and (TProcedureBody(El).Body<>nil);
  IsFunction:=IsProcBody and (El.Parent is TPasFunction);
  IsAssembler:=IsProcBody and (TProcedureBody(El).Body is TPasImplAsmStatement);

  if IsFunction and not IsAssembler then
    AddFunctionResultInit;

  For I:=0 to El.Declarations.Count-1 do
    begin
    E:=Nil;
    P:=TPasElement(El.Declarations[i]);
    //writeln('TPasToJSConverter.ConvertDeclarations El[',i,']=',GetObjName(P));
    if P.ClassType=TPasConst then
      E:=CreateConstDecl(TPasConst(P),aContext) // can be nil
    else if P.ClassType=TPasVariable then
      E:=CreateVarDecl(TPasVariable(P),aContext) // can be nil
    else if P is TPasType then
      E:=CreateTypeDecl(TPasType(P),aContext) // can be nil
    else if P is TPasProcedure then
      begin
      PasProc:=TPasProcedure(P);
      if PasProc.IsForward then continue; // JavaScript does not need the forward
      ProcScope:=TPasProcedureScope(PasProc.CustomData);
      if (ProcScope.DeclarationProc<>nil)
          and (not ProcScope.DeclarationProc.IsForward) then
        continue; // this proc was already converted in interface or class
      if ProcScope.DeclarationProc<>nil then
        PasProc:=ProcScope.DeclarationProc;
      E:=ConvertProcedure(PasProc,aContext);
      end
    else
      RaiseNotSupported(P as TPasElement,AContext,20161024191434);
    Add(E);
    end;

  if IsProcBody then
    begin
    ProcBody:=TProcedureBody(El).Body;
    if (ProcBody.Elements.Count>0) or IsAssembler then
      begin
      E:=ConvertElement(TProcedureBody(El).Body,aContext);
      Add(E);
      end;
    end;

  if IsFunction and not IsAssembler then
    AddFunctionResultReturn;
end;

{$IFDEF EnableOldClass}
function TPasToJSConverter.ConvertClassType(El: TPasClassType;
  AContext: TConvertContext): TJSElement;
var
  call: TJSCallExpression;
  asi: TJSSimpleAssignStatement;
  unary2: TJSUnary;
  unary: TJSUnary;
  je: TJSElement;
  FD: TJSFuncDef;
  cons: TJSFunctionDeclarationStatement;
  FS: TJSFunctionDeclarationStatement;
  aMember: TPasElement;
  j: integer;
  ret: TJSReturnStatement;
  jsName: String;
  FuncContext: TFunctionContext;
  Src: TJSSourceElements;
begin
  //ctname := El.FullName;
  jsName:=TransformVariableName(El,AContext);
  unary := TJSUnary(CreateElement(TJSUnary,El));
  asi := TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
  unary.A := asi;
  asi.LHS := CreateIdentifierExpr(El.Name,El);
  FS := TJSFunctionDeclarationStatement(
    CreateElement(TJSFunctionDeclarationStatement, El));
  call := CreateCallStatement(FS, []);
  asi.Expr := call;
  Result := unary;
  FD := TJSFuncDef.Create;
  FS.AFunction := FD;
  FD.Body := TJSFunctionBody(CreateElement(TJSFunctionBody, El));
  Src:=TJSSourceElements(CreateElement(TJSSourceElements, El));
  FD.Body.A := Src;

  FuncContext:=TFunctionContext.Create(El,Src,AContext);
  try
    if Assigned(El.AncestorType) then
    begin
      call.Args := TJSArguments(CreateElement(TJSArguments, El));
      call.Args.Elements.AddElement.Expr := CreateIdentifierExpr(El.AncestorType.Name,El);
      FD.Params.Add('_super');
      unary2 := TJSUnary(CreateElement(TJSUnary, El));
      call := CreateCallStatement('__extends', [jsName, '_super']);
      unary2.A := call;
      TJSSourceElements(FD.Body.A).Statements.AddNode.Node := unary2;
    end;
    //create default constructor
    cons := CreateProcedureDeclaration(El);
    TJSSourceElements(FD.Body.A).Statements.AddNode.Node := cons;
    cons.AFunction.Name := TJSString(jsName);

    //convert class members
    for j := 0 to El.Members.Count - 1 do
    begin
      aMember := TPasElement(El.Members[j]);
      //memname := aMember.FullName;
      je := ConvertClassMember(aMember, FuncContext);
      if Assigned(je) then
        TJSSourceElements(FD.Body.A).Statements.AddNode.Node := je;
    end;
  finally
    FuncContext.Free;
  end;

  //add return statement
  ret := TJSReturnStatement(CreateElement(TJSReturnStatement, El));
  TJSSourceElements(FD.Body.A).Statements.AddNode.Node := ret;
  ret.Expr := CreateIdentifierExpr(El.Name,El);
  Result := unary;
end;
{$ENDIF}

function TPasToJSConverter.ConvertClassType(El: TPasClassType;
  AContext: TConvertContext): TJSElement;
(*
  type
    TMyClass = class(Ancestor)
      i: longint;
    end;

    rtl.createClass(this,"TMyClass",Ancestor,function(){
      this.i = 0;
    });
*)
type
  TMemberFunc = (mfInit, mfFinalize);
const
  VarModifiersAllowed = [vmClass,vmStatic];
  MemberFuncName: array[TMemberFunc] of string = (
    '$init',
    '$final'
    );

  procedure RaiseVarModifierNotSupported(V: TPasVariable);
  var
    s: String;
    m: TVariableModifier;
  begin
    s:='';
    for m in TVariableModifiers do
      if not (m in VarModifiersAllowed) then
        begin
        str(m,s);
        RaiseNotSupported(V,AContext,20170204224818,'modifier '+s);
        end;
  end;

  procedure AddCallAncestorMemberFunction(ClassContext: TConvertContext;
    Ancestor: TPasType; Src: TJSSourceElements; Kind: TMemberFunc);
  var
    Call: TJSCallExpression;
    AncestorPath: String;
  begin
    Call:=CreateCallExpression(El);
    AncestorPath:=CreateReferencePath(Ancestor,ClassContext,rpkPathAndName);
    Call.Expr:=CreateBuiltInIdentifierExpr(AncestorPath+'.'+MemberFuncName[Kind]+'.call');
    Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr('this');
    AddToSourceElements(Src,Call);
  end;

  procedure AddInstanceMemberFunction(Src: TJSSourceElements;
    ClassContext: TConvertContext; Ancestor: TPasType; Kind: TMemberFunc);
  // add instance initialization function:
  //   this.$init = function(){
  //     ancestor.$init();
  //     ... init variables ...
  //   }
  // or add instance finalization function:
  //   this.$final = function(){
  //     ... clear references ...
  //     ancestor.$final();
  //   }
  var
    FuncVD: TJSVarDeclaration;
    New_Src: TJSSourceElements;
    New_FuncContext: TFunctionContext;
    I: Integer;
    P: TPasElement;
    NewEl: TJSElement;
    Func: TJSFunctionDeclarationStatement;
    VarType: TPasType;
    AssignSt: TJSSimpleAssignStatement;
  begin
    // add instance members
    New_Src:=TJSSourceElements(CreateElement(TJSSourceElements, El));
    New_FuncContext:=TFunctionContext.Create(El,New_Src,ClassContext);
    try
      New_FuncContext.This:=El;
      New_FuncContext.IsSingleton:=true;

      // add class members
      For I:=0 to El.Members.Count-1 do
        begin
        P:=TPasElement(El.Members[i]);
        NewEl:=nil;
        if (P.ClassType=TPasVariable)
            and (ClassVarModifiersType*TPasVariable(P).VarModifiers=[]) then
          begin
          if Kind=mfInit then
            // mfInit: init var
            NewEl:=CreateVarDecl(TPasVariable(P),New_FuncContext) // can be nil
          else
            begin
            // mfFinalize: clear reference
            if vmExternal in TPasVariable(P).VarModifiers then continue;
            VarType:=ClassContext.Resolver.ResolveAliasType(TPasVariable(P).VarType);
            if (VarType.ClassType=TPasRecordType)
                or (VarType.ClassType=TPasClassType)
                or (VarType.ClassType=TPasClassOfType)
                or (VarType.ClassType=TPasSetType)
                or (VarType.ClassType=TPasProcedureType)
                or (VarType.ClassType=TPasFunctionType)
                or (VarType.ClassType=TPasArrayType) then
              begin
              AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
              NewEl:=AssignSt;
              AssignSt.LHS:=CreateDeclNameExpression(P,P.Name,New_FuncContext);
              AssignSt.Expr:=CreateLiteralUndefined(El);
              end;
            end;
          end;
        if NewEl=nil then continue;
        if (Kind=mfInit) and (New_Src.Statements.Count=0) and (Ancestor<>nil) then
          // add call ancestor.$init.call(this)
          AddCallAncestorMemberFunction(ClassContext,Ancestor,New_Src,Kind);
        AddToSourceElements(New_Src,NewEl);
        end;
      if (Kind=mfFinalize) and (New_Src.Statements.Count>0) and (Ancestor<>nil) then
        // call ancestor.$final.call(this)
        AddCallAncestorMemberFunction(ClassContext,Ancestor,New_Src,Kind);
      if (Ancestor<>nil) and (New_Src.Statements.Count=0) then
        exit; // descendent does not need $init/$final

      FuncVD:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El));
      AddToSourceElements(Src,FuncVD);
      FuncVD.Name:='this.'+MemberFuncName[Kind];
      Func:=CreateFunction(El);
      FuncVD.Init:=Func;
      Func.AFunction.Body.A:=New_Src;
      New_Src:=nil;
    finally
      New_Src.Free;
      New_FuncContext.Free;
    end;
  end;

var
  Call: TJSCallExpression;
  FunDecl: TJSFunctionDeclarationStatement;
  FunDef: TJSFuncDef;
  Src: TJSSourceElements;
  ArgEx: TJSLiteral;
  FuncContext: TFunctionContext;
  I: Integer;
  NewEl: TJSElement;
  P: TPasElement;
  Scope: TPasClassScope;
  Ancestor: TPasType;
  AncestorPath: String;
begin
  Result:=nil;
  if El.IsForward then
    exit(nil);

  if El.CustomData is TPasClassScope then
    Scope:=TPasClassScope(El.CustomData)
  else
    Scope:=nil;

  // create call 'rtl.createClass('
  Call:=CreateCallExpression(El);
  try
    Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameCreateClass]);

    // add parameter: owner. 'this' for top level class.
    Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr('this');

    // add parameter: string constant '"classname"'
    ArgEx := CreateLiteralString(El,TransformVariableName(El,AContext));
    Call.Args.Elements.AddElement.Expr:=ArgEx;

    // add parameter: ancestor
    if (Scope<>nil) and (Scope.AncestorScope<>nil) then
      Ancestor:=Scope.AncestorScope.Element as TPasType
    else
      Ancestor:=El.AncestorType;
    if Ancestor<>nil then
      AncestorPath:=CreateReferencePath(Ancestor,AContext,rpkPathAndName)
    else
      AncestorPath:='null';
    Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr(AncestorPath);

    // add parameter: class initialize function 'function(){...}'
    FunDecl:=TJSFunctionDeclarationStatement.Create(0,0);
    Call.Args.Elements.AddElement.Expr:=FunDecl;
    FunDef:=TJSFuncDef.Create;
    FunDecl.AFunction:=FunDef;
    FunDef.Name:='';
    FunDef.Body:=TJSFunctionBody.Create(0,0);
    Src:=TJSSourceElements(CreateElement(TJSSourceElements, El));
    FunDef.Body.A:=Src;

    // add members
    FuncContext:=TFunctionContext.Create(El,Src,AContext);
    try
      FuncContext.IsSingleton:=true;
      FuncContext.This:=El;
      // add class members: types and class vars
      For I:=0 to El.Members.Count-1 do
        begin
        P:=TPasElement(El.Members[i]);
        //writeln('TPasToJSConverter.ConvertClassType class El[',i,']=',GetObjName(P));
        if P.ClassType=TPasVariable then
          begin
          if TPasVariable(P).VarModifiers-VarModifiersAllowed<>[] then
            RaiseVarModifierNotSupported(TPasVariable(P));
          if ClassVarModifiersType*TPasVariable(P).VarModifiers<>[] then
            begin
            NewEl:=CreateVarDecl(TPasVariable(P),FuncContext); // can be nil
            if NewEl=nil then continue;
            end
          else
            continue;
          end
        else if P.ClassType=TPasConst then
          NewEl:=CreateConstDecl(TPasConst(P),aContext)
        else if P.ClassType=TPasProperty then
          begin
          NewEl:=ConvertProperty(TPasProperty(P),AContext);
          if NewEl=nil then continue;
          end
        else if P is TPasType then
          NewEl:=CreateTypeDecl(TPasType(P),aContext)
        else if P is TPasProcedure then
          continue
        else
          RaiseNotSupported(P,FuncContext,20161221233338);
        if NewEl=nil then
          RaiseNotSupported(P,FuncContext,20170204223922);
        AddToSourceElements(Src,NewEl);
        end;

      // instance initialization function
      AddInstanceMemberFunction(Src,FuncContext,Ancestor,mfInit);
      // instance finalization function
      AddInstanceMemberFunction(Src,FuncContext,Ancestor,mfFinalize);

      // add methods
      For I:=0 to El.Members.Count-1 do
        begin
        P:=TPasElement(El.Members[i]);
        //writeln('TPasToJSConverter.ConvertClassType class El[',i,']=',GetObjName(P));
        if P is TPasProcedure then
          NewEl:=ConvertProcedure(TPasProcedure(P),aContext)
        else
          continue;
        if NewEl=nil then
          continue; // e.g. abstract proc
        AddToSourceElements(Src,NewEl);
        end;

    finally
      FuncContext.Free;
    end;

    Result:=Call;
  finally
    if Result<>Call then
      Call.Free;
  end;
end;

function TPasToJSConverter.ConvertEnumType(El: TPasEnumType;
  AContext: TConvertContext): TJSElement;
// TMyEnum = (red, green)
// convert to
// this.TMyEnum = {
//   "0":"red",
//   "red":0,
//   "0":"green",
//   "green":0,
// }
var
  ObjectContect: TObjectContext;
  i: Integer;
  EnumValue: TPasEnumValue;
  ParentObj, Obj: TJSObjectLiteral;
  ObjLit: TJSObjectLiteralElement;
  AssignSt: TJSSimpleAssignStatement;
  JSName: TJSString;
begin
  Result:=nil;
  for i:=0 to El.Values.Count-1 do
    begin
    EnumValue:=TPasEnumValue(El.Values[i]);
    if EnumValue.Value<>nil then
      RaiseNotSupported(EnumValue.Value,AContext,20170208145221,'enum constant');
    end;

  ObjectContect:=nil;
  try
    Obj:=TJSObjectLiteral(CreateElement(TJSObjectLiteral,El));
    if AContext is TObjectContext then
      begin
      // add 'TypeName: function(){}'
      ParentObj:=TObjectContext(AContext).JSElement as TJSObjectLiteral;
      ObjLit:=ParentObj.Elements.AddElement;
      ObjLit.Name:=TJSString(TransformVariableName(El,AContext));
      ObjLit.Expr:=Obj;
      Result:=Obj;
      end
    else
      begin
      // add 'this.TypeName = function(){}'
      AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
      AssignSt.LHS:=CreateDeclNameExpression(El,El.Name,AContext);
      AssignSt.Expr:=Obj;
      Result:=AssignSt;
      end;

    ObjectContect:=TObjectContext.Create(El,Obj,AContext);
    for i:=0 to El.Values.Count-1 do
      begin
      EnumValue:=TPasEnumValue(El.Values[i]);
      JSName:=TJSString(TransformVariableName(EnumValue,AContext));
      // add "0":"value"
      ObjLit:=Obj.Elements.AddElement;
      ObjLit.Name:=TJSString(IntToStr(i));
      ObjLit.Expr:=CreateLiteralJSString(El,JSName);
      // add value:0
      ObjLit:=Obj.Elements.AddElement;
      ObjLit.Name:=JSName;
      ObjLit.Expr:=CreateLiteralNumber(El,i);
      end;

  finally
    ObjectContect.Free;
  end;
end;

{$IFDEF EnableOldClass}
function TPasToJSConverter.ConvertClassConstructor(El: TPasConstructor;
  AContext: TConvertContext): TJSElement;
var
  FS: TJSFunctionDeclarationStatement;
  n: integer;
  Fun1SourceEl: TJSSourceElements;
  ret: TJSReturnStatement;
  nmem: TJSNewMemberExpression;
  Arg: TPasArgument;
begin
  if AContext=nil then ;
  FS := CreateProcedureDeclaration(El);
  FS.AFunction.Name := TJSString(El.Name);
  Fs.AFunction.Body := TJSFunctionBody(CreateElement(TJSFunctionBody, El.Body));
  Fun1SourceEl := TJSSourceElements.Create(0, 0, '');
  fs.AFunction.Body.A := Fun1SourceEl;
  ret := TJSReturnStatement.Create(0, 0, '');
  Fun1SourceEl.Statements.AddNode.Node := ret;
  nmem := TJSNewMemberExpression.Create(0, 0, '');
  ret.Expr := nmem;
  nmem.MExpr := CreateIdentifierExpr(El.Parent.FullName,El.Parent,AContext);
  for n := 0 to El.ProcType.Args.Count - 1 do
    begin
    if n = 0 then
      nmem.Args := TJSArguments.Create(0, 0, '');
    fs.AFunction.Params.Add(TPasArgument(El.ProcType.Args[n]).Name);
    Arg := TPasArgument(El.ProcType.Args[n]);
    nmem.Args.Elements.AddElement.Expr := CreateIdentifierExpr(Arg.Name,Arg,AContext);
    end;
  Result := CreateUnary([El.Parent.FullName, TPasProcedure(El).Name], FS);
end;
{$ENDIF}

procedure TPasToJSConverter.ForLoop_OnProcBodyElement(El: TPasElement;
  arg: pointer);
// Called by ConvertForStatement on each element of the current proc body
// Check each element that lies behind the loop if it is reads the LoopVar
var
  Data: PForLoopFindData absolute arg;
begin
  if El.HasParent(Data^.ForLoop) then
    Data^.FoundLoop:=true
  else if Data^.FoundLoop and (not Data^.LoopVarWrite) and (not Data^.LoopVarRead) then
    begin
    // El comes after loop and LoopVar was not yet accessed
    if (El.CustomData is TResolvedReference)
        and (TResolvedReference(El.CustomData).Declaration=Data^.LoopVar) then
      begin
        // El refers the LoopVar
        // ToDo: check write only access
        Data^.LoopVarRead:=true;
      end;
    end;
end;

procedure TPasToJSConverter.TryExcept_OnElement(El: TPasElement; arg: pointer);
var
  Data: PTryExceptFindData absolute arg;
begin
  if (El is TPasImplRaise) and (TPasImplRaise(El).ExceptObject=nil) then
    Data^.HasRaiseWithoutObject:=true;
end;

procedure TPasToJSConverter.SetUseEnumNumbers(const AValue: boolean);
begin
  if AValue then
    Include(FOptions,coEnumNumbers)
  else
    Exclude(FOptions,coEnumNumbers);
end;

procedure TPasToJSConverter.SetUseLowerCase(const AValue: boolean);
begin
  if AValue then
    Include(FOptions,coLowerCase)
  else
    Exclude(FOptions,coLowerCase);
end;

procedure TPasToJSConverter.SetUseSwitchStatement(const AValue: boolean);
begin
  if AValue then
    Include(FOptions,coSwitchStatement)
  else
    Exclude(FOptions,coSwitchStatement);
end;

procedure TPasToJSConverter.AddElementData(Data: TPas2JsElementData);
begin
  Data.Owner:=Self;
  if FFirstElementData<>nil then
    begin
    FLastElementData.Next:=Data;
    FLastElementData:=Data;
    end
  else
    begin
    FFirstElementData:=Data;
    FLastElementData:=Data;
    end;
end;

function TPasToJSConverter.CreateElementData(DataClass: TPas2JsElementDataClass;
  El: TPasElementBase): TPas2JsElementData;
begin
  while El.CustomData is TPasElementBase do
    El:=TPasElementBase(El.CustomData);
  if El.CustomData<>nil then
    begin
    {$IFDEF VerbosePas2JS}
    writeln('TPasToJSConverter.CreateElementData El=',El.ClassName,' El.CustomData=',El.CustomData.ClassName);
    {$ENDIF}
    RaiseInconsistency(20170212012945);
    end;
  Result:=DataClass.Create;
  Result.Element:=El;
  AddElementData(Result);
end;

function TPasToJSConverter.GetElementData(El: TPasElementBase;
  DataClass: TPas2JsElementDataClass): TPas2JsElementData;
begin
  Result:=nil;
  repeat
    if El.InheritsFrom(DataClass) then
      exit(TPas2JsElementData(El));
    if El.CustomData=nil then exit;
    El:=El.CustomData as TPasElementBase;
  until false;
end;

procedure TPasToJSConverter.SetTargetProcessor(const AValue: TPasToJsProcessor);
begin
  if FTargetProcessor=AValue then Exit;
  FTargetProcessor:=AValue;
end;

constructor TPasToJSConverter.Create;
begin
  FOptions:=[coLowerCase];
  FFuncNameArray_NewMultiDim:=DefaultFuncNameArray_NewMultiDim;
  FFuncNameArray_SetLength:=DefaultFuncNameArray_SetLength;
  FFuncNameAs:=DefaultFuncNameAs;
  FFuncNameCreateClass:=DefaultFuncNameCreateClass;
  FFuncNameFreeClassInstance:=DefaultFuncNameFreeClassInstance;
  FFuncNameNewClassInstance:=DefaultFuncNameNewClassInstance;
  FFuncNameProcType_Create:=DefaultFuncNameProcType_Create;
  FFuncNameProcType_Equal:=DefaultFuncNameProcType_Equal;
  FFuncNameRecordEqual:=DefaultFuncNameRecordEqual;
  FFuncNameSetCharAt:=DefaultFuncNameSetCharAt;
  FFuncNameSet_Clone:=DefaultFuncNameSet_Clone;
  FFuncNameSet_Create:=DefaultFuncNameSet_Create;
  FFuncNameSet_Difference:=DefaultFuncNameSet_Difference;
  FFuncNameSet_Equal:=DefaultFuncNameSet_Equal;
  FFuncNameSet_Exclude:=DefaultFuncNameSet_Exclude;
  FFuncNameSet_GreaterEqual:=DefaultFuncNameSet_GreaterEqual;
  FFuncNameSet_Include:=DefaultFuncNameSet_Include;
  FFuncNameSet_Intersect:=DefaultFuncNameSet_Intersect;
  FFuncNameSet_LowerEqual:=DefaultFuncNameSet_LowerEqual;
  FFuncNameSet_NotEqual:=DefaultFuncNameSet_NotEqual;
  FFuncNameSet_Reference:=DefaultFuncNameSet_Reference;
  FFuncNameSet_SymDiffSet:=DefaultFuncNameSet_SymDiffSet;
  FFuncNameSet_Union:=DefaultFuncNameSet_Union;
  FVarNameImplementation:=DefaultVarNameImplementation;
  FVarNameLoopEnd:=DefaultVarNameLoopEnd;
  FVarNameModules:=DefaultVarNameModules;
  FVarNameRTL:=DefaultVarNameRTL;
  FVarNameWith:=DefaultVarNameWith;
end;

destructor TPasToJSConverter.Destroy;
begin
  ClearElementData;
  inherited Destroy;
end;

procedure TPasToJSConverter.ClearElementData;
var
  Data, Next: TPas2JsElementData;
begin
  Data:=FFirstElementData;
  while Data<>nil do
    begin
    Next:=Data.Next;
    Data.Free;
    Data:=Next;
    end;
  FFirstElementData:=nil;
  FLastElementData:=nil;
end;

function TPasToJSConverter.ConvertProcedure(El: TPasProcedure;
  AContext: TConvertContext): TJSElement;

Var
  FS : TJSFunctionDeclarationStatement;
  FD : TJSFuncDef;
  n:Integer;
  AssignSt: TJSSimpleAssignStatement;
  FuncContext: TFunctionContext;
  ProcScope: TPasProcedureScope;
  Arg: TPasArgument;
  ImplProc: TPasProcedure;
  pm: TProcedureModifier;
  LibSymbol: TJSValue;
  ConstData: TP2JConstExprData;

begin
  Result:=nil;

  if El.IsAbstract then exit;

  ProcScope:=TPasProcedureScope(El.CustomData);
  if ProcScope.DeclarationProc<>nil then
    exit;

  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertProcedure "',El.Name,'" ',El.Parent.ClassName);
  {$ENDIF}

  // calling convention
  if El.CallingConvention<>ccDefault then
    DoError(20170211214731,nPasElementNotSupported,sPasElementNotSupported,
      [cCallingConventions[El.CallingConvention]],El);

  for pm in TProcedureModifiers do
    if (pm in El.Modifiers)
        and (not (pm in [pmVirtual, pmAbstract, pmOverride,
                         pmOverload, pmReintroduce,
                         pmAssembler, pmVarargs,
                         pmExternal, pmForward])) then
      RaiseNotSupported(El,AContext,20170208142159,'modifier '+ModifierNames[pm]);

  if pmExternal in El.Modifiers then
    begin
    // external proc
    if El.LibraryExpr<>nil then
      DoError(20170211220712,nPasElementNotSupported,sPasElementNotSupported,
        ['library'],El.LibraryExpr);
    if El.LibrarySymbolName=nil then
      DoError(20170227095454,nPasElementNotSupported,sPasElementNotSupported,
        ['missing external name'],El);
    for pm in [pmAssembler,pmForward] do
      if pm in El.Modifiers then
        RaiseNotSupported(El,AContext,20170301121326,'modifier '+ModifierNames[pm]);
    LibSymbol:=ComputeConst(El.LibrarySymbolName,AContext);
    try
      if (LibSymbol.ValueType<>jstString) or (LibSymbol.AsString='') then
        DoError(20170211221121,nExpectedXButFoundY,sExpectedXButFoundY,['string literal',El.Name],El);
      ConstData:=TP2JConstExprData(CreateElementData(TP2JConstExprData,El.LibrarySymbolName));
      ConstData.Value:=LibSymbol;
      LibSymbol:=nil;
    finally
      LibSymbol.Free;
    end;
    exit;
    end;

  ImplProc:=El;
  if ProcScope.ImplProc<>nil then
    ImplProc:=ProcScope.ImplProc;

  AssignSt:=nil;
  if AContext.IsSingleton then
    begin
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    Result:=AssignSt;
    AssignSt.LHS:=CreateDeclNameExpression(El,El.Name,AContext);
    end;

  FS:=CreateFunction(El,ImplProc.Body<>nil);
  FD:=FS.AFunction;
  if AssignSt<>nil then
    AssignSt.Expr:=FS
  else
    begin
    // local/nested function
    Result:=FS;
    FD.Name:=TJSString(TransformVariableName(El,AContext));
    end;
  for n := 0 to El.ProcType.Args.Count - 1 do
    begin
    Arg:=TPasArgument(El.ProcType.Args[n]);
    FD.Params.Add(TransformVariableName(Arg,AContext));
    end;

  if ImplProc.Body<>nil then
    begin
    FuncContext:=TFunctionContext.Create(ImplProc,FD.Body,AContext);
    try
      if ProcScope.ClassScope<>nil then
        FuncContext.This:=ProcScope.ClassScope.Element
      else
        FuncContext.This:=AContext.GetThis;
      FD.Body.A:=ConvertDeclarations(ImplProc.Body,FuncContext);
    finally
      FuncContext.Free;
    end;
    end;
  {
  TPasProcedureBase = class(TPasElement)
  TPasOverloadedProc = class(TPasProcedureBase)
  TPasProcedure = class(TPasProcedureBase)
  TPasFunction = class(TPasProcedure)
  TPasOperator = class(TPasProcedure)
  TPasConstructor = class(TPasProcedure)
  TPasDestructor = class(TPasProcedure)
  TPasClassProcedure = class(TPasProcedure)
  TPasClassFunction = class(TPasProcedure)
  }
end;

function TPasToJSConverter.ConvertBeginEndStatement(El: TPasImplBeginBlock;
  AContext: TConvertContext): TJSElement;

begin
  Result:=ConvertImplBlockElements(El,AContext);
end;

function TPasToJSConverter.ConvertImplBlockElements(El: TPasImplBlock;
  AContext: TConvertContext): TJSElement;

var
  First, Last: TJSStatementList;
  I : Integer;
  PasImpl: TPasImplElement;
  JSImpl : TJSElement;

begin
  if Not (Assigned(El.Elements) and (El.Elements.Count>0)) then
    Result:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El))
  else
    begin
    First:=nil;
    Result:=First;
    Last:=First;
    //writeln('TPasToJSConverter.ConvertImplBlockElements START El.Elements.Count=',El.Elements.Count);
    For I:=0 to El.Elements.Count-1 do
      begin
      PasImpl:=TPasImplElement(El.Elements[i]);
      JSImpl:=ConvertElement(PasImpl,AContext);
      if JSImpl=nil then
        continue; // e.g. "inherited;" when there is no ancestor proc
      //writeln('TPasToJSConverter.ConvertImplBlockElements ',i,' ',JSImpl.ClassName);
      AddToStatementList(First,Last,JSImpl,PasImpl);
      Result:=First;
      end;
    end;
end;

function TPasToJSConverter.ConvertInitializationSection(
  El: TInitializationSection; AContext: TConvertContext): TJSElement;
var
  FDS: TJSFunctionDeclarationStatement;
  FunName: String;
  IsMain, ok: Boolean;
  AssignSt: TJSSimpleAssignStatement;
  FuncContext: TFunctionContext;
  Body: TJSFunctionBody;
begin
  // create: 'this.$init=function(){}'

  IsMain:=(El.Parent<>nil) and (El.Parent is TPasProgram);
  FunName:=FuncNameMain;
  if FunName='' then
    if IsMain then
      FunName:='$main'
    else
      FunName:='$init';

  AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
  Result:=AssignSt;
  FuncContext:=nil;
  ok:=false;
  try
    AssignSt.LHS:=CreateMemberExpression(['this',FunName]);
    FDS:=CreateFunction(El,El.Elements.Count>0);
    AssignSt.Expr:=FDS;
    if El.Elements.Count>0 then
      begin
      Body:=FDS.AFunction.Body;
      FuncContext:=TFunctionContext.Create(El,Body,AContext);
      FuncContext.This:=AContext.GetThis;
      Body.A:=ConvertImplBlockElements(El,FuncContext);
      end;
    ok:=true;
  finally
    FuncContext.Free;
    if not ok then FreeAndNil(Result);
  end;
end;

function TPasToJSConverter.ConvertFinalizationSection(El: TFinalizationSection;
  AContext: TConvertContext): TJSElement;
begin
  Result:=nil;
  RaiseNotSupported(El,AContext,20161024192519);
end;

function TPasToJSConverter.ConvertTryStatement(El: TPasImplTry;
  AContext: TConvertContext): TJSElement;

  function NeedExceptObject: boolean;
  var
    Data: TTryExceptFindData;
  begin
    Result:=false;
    if El.FinallyExcept.Elements.Count=0 then exit;
    if TPasElement(El.FinallyExcept.Elements[0]) is TPasImplExceptOn then
      exit(true);
    Data:=Default(TTryExceptFindData);
    El.FinallyExcept.ForEachCall(@TryExcept_OnElement,@Data);
    Result:=Data.HasRaiseWithoutObject;
  end;

Var
  T : TJSTryStatement;
  ExceptBlock: TPasImplTryHandler;
  i: Integer;
  ExceptOn: TPasImplExceptOn;
  IfSt, Last: TJSIfStatement;

begin
  Result:=nil;
  T:=nil;
  try
    if El.FinallyExcept is TPasImplTryFinally then
      begin
      T:=TJSTryFinallyStatement(CreateElement(TJSTryFinallyStatement,El));
      T.Block:=ConvertImplBlockElements(El,AContext);
      T.BFinally:=ConvertImplBlockElements(El.FinallyExcept,AContext);
      end
    else
      begin
      T:=TJSTryCatchStatement(CreateElement(TJSTryCatchStatement,El));
      T.Block:=ConvertImplBlockElements(El,AContext);
      if NeedExceptObject then
        T.Ident:=TJSString(GetExceptionObjectName(AContext));
      //T.BCatch:=ConvertElement(El.FinallyExcept,AContext);
      ExceptBlock:=El.FinallyExcept;
      if (ExceptBlock.Elements.Count>0)
          and (TPasImplElement(ExceptBlock.Elements[0]) is TPasImplExceptOn) then
        begin
        Last:=nil;
        for i:=0 to ExceptBlock.Elements.Count-1 do
          begin
          ExceptOn:=TObject(ExceptBlock.Elements[i]) as TPasImplExceptOn;
          IfSt:=ConvertExceptOn(ExceptOn,AContext) as TJSIfStatement;
          if Last=nil then
            T.BCatch:=IfSt
          else
            Last.BFalse:=IfSt;
          Last:=IfSt;
          end;
        if El.ElseBranch<>nil then
          Last.BFalse:=ConvertImplBlockElements(El.ElseBranch,AContext);
        end
      else
        begin
        if El.ElseBranch<>nil then
          RaiseNotSupported(El.ElseBranch,AContext,20170205003014);
        T.BCatch:=ConvertImplBlockElements(ExceptBlock,AContext);
        end;
      end;
    Result:=T;
  finally
    if Result=nil then
      T.Free;
  end;
end;

function TPasToJSConverter.ConvertCaseOfStatement(El: TPasImplCaseOf;
  AContext: TConvertContext): TJSElement;
var
  SubEl: TPasImplElement;
  St: TPasImplCaseStatement;
  ok: Boolean;
  i, j: Integer;
  JSExpr: TJSElement;
  StList: TJSStatementList;
  Expr: TPasExpr;
  IfSt, LastIfSt: TJSIfStatement;
  TmpVarName: String;
  VarDecl: TJSVarDeclaration;
  VarSt: TJSVariableStatement;
  JSOrExpr: TJSLogicalOrExpression;
  JSAndExpr: TJSLogicalAndExpression;
  JSLEExpr: TJSRelationalExpressionLE;
  JSGEExpr: TJSRelationalExpressionGE;
  JSEQExpr: TJSEqualityExpressionEQ;
begin
  Result:=nil;
  if UseSwitchStatement then
    begin
    // convert to switch statement
    // switch does not support ranges -> check
    ok:=true;
    for i:=0 to El.Elements.Count-1 do
      begin
      SubEl:=TPasImplElement(El.Elements[i]);
      if not (SubEl is TPasImplCaseStatement) then
        continue;
      St:=TPasImplCaseStatement(SubEl);
      for j:=0 to St.Expressions.Count-1 do
        begin
        Expr:=TPasExpr(St.Expressions[j]);
        if (Expr is TBinaryExpr) and (TBinaryExpr(Expr).Kind=pekRange) then
          begin
          ok:=false;
          break;
          end;
        end;
      if not ok then break;
      end;
    if ok then
      begin
      Result:=CreateSwitchStatement(El,AContext);
      exit;
      end;
    end;

  // convert to if statements
  StList:=TJSStatementList(CreateElement(TJSStatementList,El));
  ok:=false;
  try
    // create var $tmp=CaseExpr;
    TmpVarName:=AContext.CreateLocalIdentifier('$tmp');
    VarSt:=TJSVariableStatement(CreateElement(TJSVariableStatement,El.CaseExpr));
    StList.A:=VarSt;
    VarDecl:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El.CaseExpr));
    VarSt.A:=VarDecl;
    VarDecl.Name:=TmpVarName;
    VarDecl.Init:=ConvertExpression(El.CaseExpr,AContext);

    LastIfSt:=nil;
    for i:=0 to El.Elements.Count-1 do
      begin
      SubEl:=TPasImplElement(El.Elements[i]);
      if SubEl is TPasImplCaseStatement then
        begin
        St:=TPasImplCaseStatement(SubEl);
        // create for example "if (tmp==expr) || ((tmp>=expr) && (tmp<=expr)){}"
        IfSt:=TJSIfStatement(CreateElement(TJSIfStatement,SubEl));
        if LastIfSt=nil then
          StList.B:=IfSt
        else
          LastIfSt.BFalse:=IfSt;
        LastIfSt:=IfSt;

        for j:=0 to St.Expressions.Count-1 do
          begin
          Expr:=TPasExpr(St.Expressions[j]);
          if (Expr is TBinaryExpr) and (TBinaryExpr(Expr).Kind=pekRange) then
            begin
            // range -> create "(tmp>=left) && (tmp<=right)"
            // create "() && ()"
            JSAndExpr:=TJSLogicalAndExpression(CreateElement(TJSLogicalAndExpression,Expr));
            JSExpr:=JSAndExpr;
            // create "tmp>=left"
            JSGEExpr:=TJSRelationalExpressionGE(CreateElement(TJSRelationalExpressionGE,Expr));
            JSAndExpr.A:=JSGEExpr;
            JSGEExpr.A:=CreateIdentifierExpr(TmpVarName,El.CaseExpr,AContext);
            JSGEExpr.B:=ConvertExpression(TBinaryExpr(Expr).left,AContext);
            // create "tmp<=right"
            JSLEExpr:=TJSRelationalExpressionLE(CreateElement(TJSRelationalExpressionLE,Expr));
            JSAndExpr.B:=JSLEExpr;
            JSLEExpr.A:=CreateIdentifierExpr(TmpVarName,El.CaseExpr,AContext);
            JSLEExpr.B:=ConvertExpression(TBinaryExpr(Expr).right,AContext);
            end
          else
            begin
            // value -> create (tmp==Expr)
            JSEQExpr:=TJSEqualityExpressionEQ(CreateElement(TJSEqualityExpressionEQ,Expr));
            JSExpr:=JSEQExpr;
            JSEQExpr.A:=CreateIdentifierExpr(TmpVarName,El.CaseExpr,AContext);
            JSEQExpr.B:=ConvertExpression(Expr,AContext);
            end;
          if IfSt.Cond=nil then
            // first expression
            IfSt.Cond:=JSExpr
          else
            begin
            // multi expression -> append with OR
            JSOrExpr:=TJSLogicalOrExpression(CreateElement(TJSLogicalOrExpression,St));
            JSOrExpr.A:=IfSt.Cond;
            JSOrExpr.B:=JSExpr;
            IfSt.Cond:=JSOrExpr;
            end;
          end;
        // convert statement
        if St.Body<>nil then
          IfSt.BTrue:=ConvertElement(St.Body,AContext)
        else
          IfSt.BTrue:=TJSEmptyStatement(CreateElement(TJSEmptyStatement,St));
        end
      else if SubEl is TPasImplCaseElse then
        begin
        // Pascal 'else' or 'otherwise' -> create JS "else{}"
        if LastIfSt=nil then
          RaiseNotSupported(SubEl,AContext,20161128120802,'case-of needs at least one case');
        LastIfSt.BFalse:=ConvertImplBlockElements(El.ElseBranch,AContext);
        end
      else
        RaiseNotSupported(SubEl,AContext,20161128113055);
      end;

    ok:=true;
  finally
    if not ok then
      StList.Free;
  end;
  Result:=StList;
end;

function TPasToJSConverter.ConvertAsmStatement(El: TPasImplAsmStatement;
  AContext: TConvertContext): TJSElement;
var
  s: String;
  L: TJSLiteral;
begin
  if AContext=nil then ;
  s:=Trim(El.Tokens.Text);
  if (s<>'') and (s[length(s)]=';') then
    Delete(s,length(s),1);
  if s='' then
    Result:=TJSEmptyStatement(CreateElement(TJSEmptyStatement,El))
  else begin
    L:=TJSLiteral(CreateElement(TJSLiteral,El));
    L.Value.CustomValue:=TJSString(s);
    Result:=L;
  end;
end;

procedure TPasToJSConverter.CreateImplementationSection(El: TPasModule;
  Src: TJSSourceElements; AContext: TConvertContext);
var
  Section: TImplementationSection;
begin
  if not Assigned(El.ImplementationSection) then
    exit;
  Section:=El.ImplementationSection;
  // add implementation section
  // merge interface and implementation
  AddToSourceElements(Src,ConvertDeclarations(Section,AContext));
end;

procedure TPasToJSConverter.CreateInitSection(El: TPasModule;
  Src: TJSSourceElements; AContext: TConvertContext);
begin
  // add initialization section
  if Assigned(El.InitializationSection) then
    AddToSourceElements(Src,ConvertInitializationSection(El.InitializationSection,AContext));
  // finalization: not supported
  if Assigned(El.FinalizationSection) then
    raise Exception.Create('TPasToJSConverter.ConvertInitializationSection: finalization section is not supported');
end;

function TPasToJSConverter.CreateDotExpression(aParent: TPasElement; Left,
  Right: TJSElement): TJSElement;
var
  Dot: TJSDotMemberExpression;
  RightParent: TJSElement;
  ok: Boolean;
begin
  Result:=nil;
  if Left=nil then
    RaiseInconsistency(20170201140827);
  if Right=nil then
    RaiseInconsistency(20170211192018);
  ok:=false;
  try
    // create a TJSDotMemberExpression of Left and the left-most identifier of Right
    // Left becomes the new left-most element of Right.
    Result:=Right;
    RightParent:=nil;
    repeat
      if (Right.ClassType=TJSCallExpression) then
        begin
        RightParent:=Right;
        Right:=TJSCallExpression(Right).Expr;
        end
      else if (Right.ClassType=TJSBracketMemberExpression) then
        begin
        RightParent:=Right;
        Right:=TJSBracketMemberExpression(Right).MExpr;
        end
      else if (Right.ClassType=TJSDotMemberExpression) then
        begin
        RightParent:=Right;
        Right:=TJSDotMemberExpression(Right).MExpr;
        end
      else if (Right.ClassType=TJSPrimaryExpressionIdent) then
        begin
        // left-most identifier found
        // -> replace it
        Dot := TJSDotMemberExpression(CreateElement(TJSDotMemberExpression, aParent));
        if Result=Right then
          Result:=Dot
        else if RightParent is TJSBracketMemberExpression then
          TJSBracketMemberExpression(RightParent).MExpr:=Dot
        else if RightParent is TJSCallExpression then
          TJSCallExpression(RightParent).Expr:=Dot
        else if RightParent is TJSDotMemberExpression then
          TJSDotMemberExpression(RightParent).MExpr:=Dot
        else
          begin
          Dot.Free;
          {$IFDEF VerbosePas2JS}
          writeln('TPasToJSConverter.CreateDotExpression Right=',GetObjName(Right),' RightParent=',GetObjName(RightParent),' Result=',GetObjName(Result));
          {$ENDIF}
          RaiseInconsistency(20170129141307);
          end;
        Dot.MExpr := Left;
        Dot.Name := TJSPrimaryExpressionIdent(Right).Name;
        FreeAndNil(Right);
        break;
        end
      else
        begin
        {$IFDEF VerbosePas2JS}
        writeln('CreateDotExpression Right=',Right.ClassName);
        {$ENDIF}
        DoError(20161024191240,nMemberExprMustBeIdentifier,sMemberExprMustBeIdentifier,[],aParent);
        end;
    until false;

    ok:=true;
  finally
    if not ok then
      begin
      Left.Free;
      FreeAndNil(Result);
      end;
  end;
end;

function TPasToJSConverter.CreateReferencedSet(El: TPasElement; SetExpr: TJSElement
  ): TJSElement;
var
  Call: TJSCallExpression;
begin
  Call:=CreateCallExpression(El);
  Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameSet_Reference]);
  Call.Args.Elements.AddElement.Expr:=SetExpr;
  Result:=Call;
end;

function TPasToJSConverter.CreateCloneRecord(El: TPasElement;
  ResolvedEl: TPasResolverResult; RecordExpr: TJSElement;
  AContext: TConvertContext): TJSElement;
// create  "new RecordType(RecordExpr)
var
  NewExpr: TJSNewMemberExpression;
begin
  if not (ResolvedEl.TypeEl is TPasRecordType) then
    RaiseInconsistency(20170212155956);
  NewExpr:=TJSNewMemberExpression(CreateElement(TJSNewMemberExpression,El));
  NewExpr.MExpr:=CreateReferencePathExpr(ResolvedEl.TypeEl,AContext);
  NewExpr.Args:=TJSArguments(CreateElement(TJSArguments,El));
  NewExpr.Args.Elements.AddElement.Expr:=RecordExpr;
  Result:=NewExpr;
end;

function TPasToJSConverter.CreateCallback(El: TPasElement;
  ResolvedEl: TPasResolverResult; AContext: TConvertContext): TJSElement;
var
  Call: TJSCallExpression;
  Scope: TJSElement;
  DotExpr: TJSDotMemberExpression;
  Prim: TJSPrimaryExpressionIdent;
  aName: String;
  DotPos: SizeInt;
  FunName: String;
begin
  // create  "rtl.createCallback(scope,func)"
  Result:=nil;
  if not (ResolvedEl.IdentEl is TPasProcedure) then
    RaiseInconsistency(20170215140756);
  Call:=nil;
  Scope:=nil;
  try
    Call:=CreateCallExpression(El);
    // "rtl.createCallback"
    Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameProcType_Create]);
    // add scope as parameter
    Scope:=ConvertElement(El,AContext);
    {$IFDEF VerbosePas2JS}
    writeln('TPasToJSConverter.CreateCallback ',GetObjName(Scope));
    {$ENDIF}
    FunName:='';
    // the last element of Scope is the proc, chomp that off
    if Scope.ClassType=TJSDotMemberExpression then
      begin
      // chomp dot member
      DotExpr:=TJSDotMemberExpression(Scope);
      Scope:=DotExpr.MExpr;
      DotExpr.MExpr:=nil;
      FunName:=String(DotExpr.Name);
      if not IsValidJSIdentifier(DotExpr.Name) then
        begin
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.CreateCallback ',GetObjName(Scope),' Name="',FunName,'"');
        {$ENDIF}
        DoError(20170215161802,nInvalidFunctionReference,sInvalidFunctionReference,[],El);
        end;
      FreeAndNil(DotExpr);
      end
    else if Scope.ClassType=TJSPrimaryExpressionIdent then
      begin
      // chomp dotted identifier
      Prim:=TJSPrimaryExpressionIdent(Scope);
      aName:=String(Prim.Name);
      DotPos:=PosLast('.',aName);
      if DotPos<1 then
        begin
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.CreateCallback Scope=',GetObjName(Scope),' Name="',String(aName),'"');
        {$ENDIF}
        DoError(20170215161410,nInvalidFunctionReference,sInvalidFunctionReference,[],El);
        end;
      FunName:=copy(aName,DotPos+1);
      Prim.Name:=TJSString(LeftStr(aName,DotPos-1));
      end
    else
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.CreateCallback invalid Scope=',GetObjName(Scope));
      {$ENDIF}
      RaiseNotSupported(El,AContext,20170215161210);
      end;
    Call.Args.Elements.AddElement.Expr:=Scope;

    // add function name as parameter
    Call.Args.Elements.AddElement.Expr:=CreateLiteralString(El,FunName);

    Result:=Call;
  finally
    if Result=nil then
      begin
      Scope.Free;
      Call.Free;
      end;
  end;
end;

function TPasToJSConverter.ConvertImplBlock(El: TPasImplBlock;
  AContext: TConvertContext): TJSElement;

begin
  Result:=Nil;
  if (El is TPasImplStatement) then
    Result:=ConvertStatement(TPasImplStatement(El),AContext)
  else if (El.ClassType=TPasImplIfElse) then
    Result:=ConvertIfStatement(TPasImplIfElse(El),AContext)
  else if (El.ClassType=TPasImplRepeatUntil) then
    Result:=ConvertRepeatStatement(TPasImplRepeatUntil(El),AContext)
  else if (El.ClassType=TPasImplBeginBlock) then
    Result:=ConvertBeginEndStatement(TPasImplBeginBlock(El),AContext)
  else if (El.ClassType=TInitializationSection) then
    Result:=ConvertInitializationSection(TInitializationSection(El),AContext)
  else if (El.ClassType=TFinalizationSection) then
    Result:=ConvertFinalizationSection(TFinalizationSection(El),AContext)
  else if (El.ClassType=TPasImplTry) then
    Result:=ConvertTryStatement(TPasImplTry(El),AContext)
  else if (El.ClassType=TPasImplCaseOf) then
    Result:=ConvertCaseOfStatement(TPasImplCaseOf(El),AContext)
  else
    RaiseNotSupported(El,AContext,20161024192156);
(*
  TPasImplBlock = class(TPasImplElement)
  TPasImplCaseOf = class(TPasImplBlock)
  TPasImplStatement = class(TPasImplBlock)
  TPasImplCaseElse = class(TPasImplBlock)
  TPasImplTry = class(TPasImplBlock)
  TPasImplTryHandler = class(TPasImplBlock)
  TPasImplTryFinally = class(TPasImplTryHandler)
  TPasImplTryExcept = class(TPasImplTryHandler)
  TPasImplTryExceptElse = class(TPasImplTryHandler)

*)
end;

function TPasToJSConverter.ConvertPackage(El: TPasPackage;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192555);
  Result:=Nil;
  // ToDo TPasPackage = class(TPasElement)
end;

function TPasToJSConverter.ConvertResString(El: TPasResString;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192604);
  Result:=Nil;
  // ToDo: TPasResString
end;

function TPasToJSConverter.ConvertVariable(El: TPasVariable;
  AContext: TConvertContext): TJSElement;

Var
  V : TJSVarDeclaration;
  vm: TVariableModifier;
begin
  for vm in TVariableModifier do
    if (vm in El.VarModifiers) and (not (vm in [vmClass,vmExternal])) then
      RaiseNotSupported(El,AContext,20170208141622,'modifier '+VariableModifierNames[vm]);
  if El.LibraryName<>nil then
    RaiseNotSupported(El,AContext,20170208141844,'library name');
  if El.AbsoluteLocation<>'' then
    RaiseNotSupported(El,AContext,20170208141926,'absolute');

  V:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El));
  V.Name:=TransformVariableName(El,AContext);
  V.Init:=CreateVarInit(El,AContext);
  Result:=V;
end;

function TPasToJSConverter.ConvertProperty(El: TPasProperty;
  AContext: TConvertContext): TJSElement;

begin
  Result:=Nil;
  if El.IndexExpr<>nil then
    RaiseNotSupported(El.IndexExpr,AContext,20170215103010,'property index expression');
  if El.ImplementsFunc<>nil then
    RaiseNotSupported(El.ImplementsFunc,AContext,20170215102923,'property implements function');
  if El.DispIDExpr<>nil then
    RaiseNotSupported(El.DispIDExpr,AContext,20170215103029,'property dispid expression');
  if El.DefaultExpr<>nil then
    RaiseNotSupported(El.DefaultExpr,AContext,20170215103129,'property default modifier');
  if El.StoredAccessor<>nil then
    RaiseNotSupported(El.StoredAccessor,AContext,20170215121145,'property stored accessor');
  if El.StoredAccessorName<>'' then
    RaiseNotSupported(El,AContext,20170215121248,'property stored accessor');
  // does not need any declaration. Access is redirected to getter/setter.
end;

function TPasToJSConverter.ConvertExportSymbol(El: TPasExportSymbol;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192650);
  Result:=Nil;
  // ToDo: TPasExportSymbol
end;

function TPasToJSConverter.ConvertLabels(El: TPasLabels;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192701);
  Result:=Nil;
  // ToDo: TPasLabels = class(TPasImplElement)
end;

function TPasToJSConverter.ConvertRaiseStatement(El: TPasImplRaise;
  AContext: TConvertContext): TJSElement;

Var
  E : TJSElement;
  T : TJSThrowStatement;

begin
  if El.ExceptObject<>Nil then
    E:=ConvertElement(El.ExceptObject,AContext)
  else
    E:=CreateBuiltInIdentifierExpr(GetExceptionObjectName(AContext));
  T:=TJSThrowStatement(CreateElement(TJSThrowStatement,El));
  T.A:=E;
  Result:=T;
end;

function TPasToJSConverter.ConvertAssignStatement(El: TPasImplAssign;
  AContext: TConvertContext): TJSElement;

Var
  LHS: TJSElement;
  T: TJSAssignStatement;
  AssignContext: TAssignContext;
  Flags: TPasResolverComputeFlags;
  LeftIsProcType: Boolean;

begin
  Result:=nil;
  LHS:=nil;
  AssignContext:=TAssignContext.Create(El,nil,AContext);
  try
    if AContext.Resolver<>nil then
      begin
      AContext.Resolver.ComputeElement(El.left,AssignContext.LeftResolved,[rcNoImplicitProc]);
      Flags:=[];
      LeftIsProcType:=AContext.Resolver.IsProcedureType(AssignContext.LeftResolved);
      if LeftIsProcType then
        begin
        if msDelphi in AContext.CurrentModeswitches then
          Include(Flags,rcNoImplicitProc)
        else
          Include(Flags,rcNoImplicitProcType);
        end;
      AContext.Resolver.ComputeElement(El.right,AssignContext.RightResolved,Flags);
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.ConvertAssignStatement Left={',GetResolverResultDesc(AssignContext.LeftResolved),'} Right={',GetResolverResultDesc(AssignContext.RightResolved),'}');
      {$ENDIF}
      if LeftIsProcType and (msDelphi in AContext.CurrentModeswitches)
          and (AssignContext.RightResolved.BaseType=btProc) then
        begin
          // Delphi allows assigning a proc without @: proctype:=proc
          AssignContext.RightSide:=CreateCallback(El.right,AssignContext.RightResolved,AContext);
        end
      else if AssignContext.RightResolved.BaseType=btNil then
        begin
        if AContext.Resolver.IsArrayType(AssignContext.LeftResolved) then
          begin
          // array:=nil -> array:=[]
          AssignContext.RightSide:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El.right));
          end;
        end;
      end;
    if AssignContext.RightSide=nil then
      AssignContext.RightSide:=ConvertElement(El.right,AContext);
    if (AssignContext.RightResolved.BaseType=btSet)
        and (AssignContext.RightResolved.IdentEl<>nil) then
      begin
      // right side is a set variable -> create reference
      {$IFDEF VerbosePas2JS}
      //writeln('TPasToJSConverter.ConvertAssignStatement SET variable Right={',GetResolverResultDesc(AssignContext.RightResolved),'} AssignContext.RightResolved.IdentEl=',GetObjName(AssignContext.RightResolved.IdentEl));
      {$ENDIF}
      // create  rtl.refSet(right)
      AssignContext.RightSide:=CreateReferencedSet(El.right,AssignContext.RightSide);
      end
    else if AssignContext.RightResolved.BaseType=btContext then
      begin
      if AssignContext.RightResolved.TypeEl.ClassType=TPasRecordType then
        begin
        // right side is a record -> clone
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.ConvertAssignStatement RECORD variable Right={',GetResolverResultDesc(AssignContext.RightResolved),'} AssignContext.RightResolved.IdentEl=',GetObjName(AssignContext.RightResolved.IdentEl));
        {$ENDIF}
        // create  "new RightRecordType(RightRecord)"
        AssignContext.RightSide:=CreateCloneRecord(El.right,
                  AssignContext.RightResolved,AssignContext.RightSide,AContext);
        end;
      end;
    LHS:=ConvertElement(El.left,AssignContext);
    if AssignContext.Call<>nil then
      begin
      // left side is a Setter -> RightSide was already inserted as parameter
      if AssignContext.RightSide<>nil then
        RaiseInconsistency(20170207215544);
      Result:=LHS;
      end
    else
      begin
      // left side is a variable -> create normal assign statement
      case El.Kind of
        akDefault: T:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
        akAdd: T:=TJSAddEqAssignStatement(CreateElement(TJSAddEqAssignStatement,El));
        akMinus: T:=TJSSubEqAssignStatement(CreateElement(TJSSubEqAssignStatement,El));
        akMul: T:=TJSMulEqAssignStatement(CreateElement(TJSMulEqAssignStatement,El));
        akDivision: T:=TJSDivEqAssignStatement(CreateElement(TJSDivEqAssignStatement,El));
        else RaiseNotSupported(El,AContext,20161107221807);
      end;
      T.Expr:=AssignContext.RightSide;
      AssignContext.RightSide:=nil;
      T.LHS:=LHS;
      Result:=T;
      end;
  finally
    if Result=nil then
      LHS.Free;
    AssignContext.RightSide.Free;
    AssignContext.Free;
  end;
end;

function TPasToJSConverter.ConvertCommand(El: TPasImplCommand;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192705);
  Result:=Nil;
  // ToDo: TPasImplCommand = class(TPasImplElement)
end;

function TPasToJSConverter.ConvertIfStatement(El: TPasImplIfElse;
  AContext: TConvertContext): TJSElement;

Var
  C,BThen,BElse : TJSElement;
  T : TJSIfStatement;
  ok: Boolean;

begin
  if AContext=nil then ;
  C:=Nil;
  BThen:=Nil;
  BElse:=Nil;
  ok:=false;
  try
    C:=ConvertElement(El.ConditionExpr,AContext);
    if Assigned(El.IfBranch) then
      BThen:=ConvertElement(El.IfBranch,AContext)
    else
      BThen:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El));
    if Assigned(El.ElseBranch) then
      BElse:=ConvertElement(El.ElseBranch,AContext);
    ok:=true;
  finally
    if not ok then
      begin
      FreeAndNil(C);
      FreeAndNil(BThen);
      FreeAndNil(BElse);
      end;
  end;
  T:=TJSIfStatement(CreateElement(TJSIfStatement,El));
  T.Cond:=C;
  T.BTrue:=BThen;
  T.BFalse:=BElse;
  Result:=T;
end;

function TPasToJSConverter.ConvertWhileStatement(El: TPasImplWhileDo;
  AContext: TConvertContext): TJSElement;

Var
  C : TJSElement;
  B : TJSElement;
  W : TJSWhileStatement;
  ok: Boolean;
begin
  Result:=Nil;
  C:=Nil;
  B:=Nil;
  ok:=false;
  try
    C:=ConvertElement(EL.ConditionExpr,AContext);
    if Assigned(EL.Body) then
      B:=ConvertElement(EL.Body,AContext)
    else
      B:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El));
    ok:=true;
  finally
    if not ok then
      begin
      FreeAndNil(B);
      FreeAndNil(C);
      end;
  end;
  W:=TJSWhileStatement(CreateElement(TJSWhileStatement,El));
  W.Cond:=C;
  W.Body:=B;
  Result:=W;
end;

function TPasToJSConverter.ConvertRepeatStatement(El: TPasImplRepeatUntil;
  AContext: TConvertContext): TJSElement;
Var
  C : TJSElement;
  N : TJSUnaryNotExpression;
  W : TJSDoWhileStatement;
  B : TJSElement;
  ok: Boolean;

begin
  Result:=Nil;
  C:=Nil;
  B:=Nil;
  ok:=false;
  try
    C:=ConvertElement(EL.ConditionExpr,AContext);
    N:=TJSUnaryNotExpression(CreateElement(TJSUnaryNotExpression,EL.ConditionExpr));
    N.A:=C;
    B:=ConvertImplBlockElements(El,AContext);
    ok:=true;
  finally
    if not ok then
      begin
      FreeAndNil(B);
      FreeAndNil(C);
      end;
  end;
  W:=TJSDoWhileStatement(CreateElement(TJSDoWhileStatement,El));
  W.Cond:=N;
  W.Body:=B;
  Result:=W;
end;

function TPasToJSConverter.ConvertForStatement(El: TPasImplForLoop;
  AContext: TConvertContext): TJSElement;
// Creates the following code:
//   var $loopend=<EndExpr>;
//   for(LoopVar=<StartExpr>; LoopVar<=$loopend; LoopVar++){}
//   if(LoopVar>$loopend)LoopVar--; // this line is only added if LoopVar is read later
//
// The StartExpr must be executed exactly once at beginning.
// The EndExpr must be executed exactly once at beginning.
// LoopVar can be a varname or programname.varname

Var
  ForSt : TJSForStatement;
  List, ListEnd: TJSStatementList;
  SimpleAss : TJSSimpleAssignStatement;
  VarDecl : TJSVarDeclaration;
  Incr, Decr : TJSUNaryExpression;
  BinExp : TJSBinaryExpression;
  VarStat: TJSVariableStatement;
  IfSt: TJSIfStatement;
  GTExpr: TJSRelationalExpression;
  CurLoopEndVarName: String;
  FuncContext: TConvertContext;
  ResolvedVar: TPasResolverResult;

  function NeedDecrAfterLoop: boolean;
  var
    ResolvedVar: TPasResolverResult;
    aParent: TPasElement;
    ProcBody: TProcedureBody;
    FindData: TForLoopFindData;
  begin
    Result:=true;
    if AContext.Resolver=nil then exit(false);
    AContext.Resolver.ComputeElement(El.VariableName,ResolvedVar,[rcNoImplicitProc]);
    if ResolvedVar.IdentEl=nil then
      exit;
    if ResolvedVar.IdentEl.Parent is TProcedureBody then
      begin
      // loopvar is a local var
      ProcBody:=TProcedureBody(ResolvedVar.IdentEl.Parent);
      aParent:=El;
      while true do
        begin
        aParent:=aParent.Parent;
        if aParent=nil then exit;
        if aParent is TProcedureBody then
          begin
          if aParent<>ProcBody then exit;
          break;
          end;
        end;
      // loopvar is a local var of the same function as where the loop is
      // -> check if it is read after the loop
      FindData:=Default(TForLoopFindData);
      FindData.ForLoop:=El;
      FindData.LoopVar:=ResolvedVar.IdentEl;
      ProcBody.Body.ForEachCall(@ForLoop_OnProcBodyElement,@FindData);
      if not FindData.LoopVarRead then
        exit(false);
      end;
  end;

begin
  Result:=Nil;
  BinExp:=Nil;
  if AContext.Access<>caRead then
    RaiseInconsistency(20170213213740);
  // get function context
  FuncContext:=AContext;
  while (FuncContext.Parent<>nil) and (not (FuncContext is TFunctionContext)) do
    FuncContext:=FuncContext.Parent;
  // create unique loopend var name
  CurLoopEndVarName:=FuncContext.CreateLocalIdentifier(VarNameLoopEnd);

  // loopvar:=
  // for (statementlist...
  List:=TJSStatementList(CreateElement(TJSStatementList,El));
  ListEnd:=List;
  try
    // add "var $loopend=<EndExpr>"
    VarStat:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
    List.A:=VarStat;
    VarDecl:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El));
    VarStat.A:=VarDecl;
    VarDecl.Name:=CurLoopEndVarName;
    VarDecl.Init:=ConvertElement(El.EndExpr,AContext);
    // add "for()"
    ForSt:=TJSForStatement(CreateElement(TJSForStatement,El));
    List.B:=ForSt;
    // add "LoopVar=<StartExpr>;"
    SimpleAss:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El.StartExpr));
    ForSt.Init:=SimpleAss;
    if AContext.Resolver<>nil then
      begin
      AContext.Resolver.ComputeElement(El.VariableName,ResolvedVar,[rcNoImplicitProc]);
      if not (ResolvedVar.IdentEl is TPasVariable) then
        DoError(20170213214404,nExpectedXButFoundY,sExpectedXButFoundY,['var',GetResolverResultDescription(ResolvedVar)],El);
      end;
    SimpleAss.LHS:=ConvertElement(El.VariableName,AContext);
    SimpleAss.Expr:=ConvertElement(El.StartExpr,AContext);
    // add "LoopVar<=$loopend"
    if El.Down then
      BinExp:=TJSRelationalExpressionGE(CreateElement(TJSRelationalExpressionGE,El.EndExpr))
    else
      BinExp:=TJSRelationalExpressionLE(CreateElement(TJSRelationalExpressionLE,El.EndExpr));
    ForSt.Cond:=BinExp;
    BinExp.A:=ConvertElement(El.VariableName,AContext);
    BinExp.B:=CreateIdentifierExpr(CurLoopEndVarName,El.EndExpr,AContext);
    // add "LoopVar++"
    if El.Down then
      Incr:=TJSUnaryPostMinusMinusExpression(CreateElement(TJSUnaryPostMinusMinusExpression,El))
    else
      Incr:=TJSUnaryPostPlusPlusExpression(CreateElement(TJSUnaryPostPlusPlusExpression,El));
    ForSt.Incr:=Incr;
    Incr.A:=ConvertElement(El.VariableName,AContext);
    // add body
    if El.Body<>nil then
      ForSt.Body:=ConvertElement(El.Body,AContext);

    if NeedDecrAfterLoop then
      begin
      // add "if(LoopVar>$loopend)LoopVar--;"
      // add "if()"
      IfSt:=TJSIfStatement(CreateElement(TJSIfStatement,El));
      AddToStatementList(List,ListEnd,IfSt,El);
      // add "LoopVar>$loopend"
      if El.Down then
        GTExpr:=TJSRelationalExpressionLT(CreateElement(TJSRelationalExpressionLT,El))
      else
        GTExpr:=TJSRelationalExpressionGT(CreateElement(TJSRelationalExpressionGT,El));
      IfSt.Cond:=GTExpr;
      GTExpr.A:=ConvertElement(El.VariableName,AContext);
      GTExpr.B:=CreateIdentifierExpr(CurLoopEndVarName,El.EndExpr,AContext);
      // add "LoopVar--"
      if El.Down then
        Decr:=TJSUnaryPostPlusPlusExpression(CreateElement(TJSUnaryPostPlusPlusExpression,El))
      else
        Decr:=TJSUnaryPostMinusMinusExpression(CreateElement(TJSUnaryPostMinusMinusExpression,El));
      IfSt.BTrue:=Decr;
      Decr.A:=ConvertElement(El.VariableName,AContext);
      end;
    Result:=List;
  finally
    if Result=nil then
      List.Free;
  end;
end;

function TPasToJSConverter.ConvertSimpleStatement(El: TPasImplSimple;
  AContext: TConvertContext): TJSElement;

Var
  E : TJSElement;

begin
  E:=ConvertElement(EL.Expr,AContext);
  if E=nil then
    exit(nil); // e.g. "inherited;" without ancestor proc
  Result:=TJSExpressionStatement(CreateElement(TJSExpressionStatement,El));
  TJSExpressionStatement(Result).A:=E;
end;

function TPasToJSConverter.ConvertWithStatement(El: TPasImplWithDo;
  AContext: TConvertContext): TJSElement;
Var
  B,E , Expr: TJSElement;
  W,W2 : TJSWithStatement;
  I : Integer;
  ok: Boolean;
  PasExpr: TPasElement;
  V: TJSVariableStatement;
  VarDecl: TJSVarDeclaration;
  FuncContext: TFunctionContext;
  FirstSt, LastSt: TJSStatementList;
  WithScope: TPasWithScope;
  WithExprScope: TPasWithExprScope;
  WithData: TP2JWithData;

begin
  Result:=nil;
  if AContext.Resolver<>nil then
    begin
    // with Resolver:
    // Insert for each expression a local var. Example:
    //   with aPoint do X:=3;
    // convert to
    //   var $with1 = aPoint;
    //   $with1.X = 3;
    FuncContext:=TFunctionContext(AContext.GetContextOfType(TFunctionContext));
    if FuncContext=nil then
      RaiseInconsistency(20170212003759);
    FirstSt:=nil;
    LastSt:=nil;
    try
      WithScope:=El.CustomData as TPasWithScope;
      for i:=0 to El.Expressions.Count-1 do
        begin
        PasExpr:=TPasElement(El.Expressions[i]);
        Expr:=ConvertElement(PasExpr,AContext);

        // create unique local var name
        WithExprScope:=TPasWithExprScope(WithScope.ExpressionScopes[i]);
        WithData:=TP2JWithData(CreateElementData(TP2JWithData,WithExprScope));
        WithData.WithVarName:=FuncContext.CreateLocalIdentifier(VarNameWith);
        // create local "var $with1 = expr;"
        V:=TJSVariableStatement(CreateElement(TJSVariableStatement,PasExpr));
        VarDecl:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,PasExpr));
        V.A:=VarDecl;
        VarDecl.Name:=WithData.WithVarName;
        VarDecl.Init:=Expr;
        AddToStatementList(FirstSt,LastSt,V,PasExpr);
        end;
      if Assigned(El.Body) then
        begin
        B:=ConvertElement(El.Body,AContext);
        AddToStatementList(FirstSt,LastSt,B,El.Body);
        end
      else
        begin
        B:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El));
        AddToStatementList(FirstSt,LastSt,B,El);
        end;
      Result:=FirstSt;
    finally
      if Result=nil then
        FreeAndNil(FirstSt);
    end;
    end
  else
    begin
    // without Resolver use as fallback the JavaScript with(){}
    W:=Nil;
    if Assigned(El.Body) then
      B:=ConvertElement(El.Body,AContext)
    else
      B:=TJSEmptyBlockStatement(CreateElement(TJSEmptyBlockStatement,El));
    ok:=false;
    try
      For I:=0 to El.Expressions.Count-1 do
        begin
        E:=ConvertElement(TPasElement(El.Expressions[i]),AContext);
        W2:=TJSWithStatement(CreateElement(TJSWithStatement,TPasElement(El.Expressions[i])));
        if Not Assigned(Result) then // result is the first
          Result:=W2;
        if Assigned(W) then // Chain
          W.B:=W2;
        W:=W2; // W is the last
        W.A:=E;
        end;
      ok:=true;
    finally
      if not ok then
        begin
        FreeAndNil(E);
        FreeAndNil(Result);
        end;
    end;
    W.B:=B;
    end;
end;

function TPasToJSConverter.GetExceptionObjectName(AContext: TConvertContext
  ): string;
begin
  if AContext=nil then ;
  Result:=DefaultJSExceptionObject; // use the same as the FPC RTL
  if UseLowerCase then
    Result:=lowercase(Result);
end;

procedure TPasToJSConverter.RaiseInconsistency(Id: int64);
begin
  raise Exception.Create('TPasToJSConverter.RaiseInconsistency['+IntToStr(Id)+']: you found a bug');
end;

{$IFDEF EnableOldClass}
function TPasToJSConverter.CreateCallStatement(const JSCallName: string;
  JSArgs: array of string): TJSCallExpression;
var
  Call: TJSCallExpression;
  Ident: TJSPrimaryExpressionIdent;
begin
  Ident := TJSPrimaryExpressionIdent.Create(0, 0, '');
  Ident.Name := TJSString(JSCallName);
  Call := CreateCallStatement(Ident, JSArgs);
  Result := Call;
end;

function TPasToJSConverter.CreateCallStatement(const FunNameEx: TJSElement;
  JSArgs: array of string): TJSCallExpression;
var
  p: string;
  ArgEx: TJSPrimaryExpressionIdent;
  Call: TJSCallExpression;
  ArgArray: TJSArguments;
begin
  Call := TJSCallExpression.Create(0, 0, '');
  Call.Expr := FunNameEx;
  ArgArray := TJSArguments.Create(0, 0, '');
  Call.Args := ArgArray;
  for p in JSArgs do
  begin
    ArgEx := TJSPrimaryExpressionIdent.Create(0, 0, '');
    ArgEx.Name := TJSString(p);
    ArgArray.Elements.AddElement.Expr := ArgEx;
  end;
  Result := Call;
end;
{$ENDIF}

function TPasToJSConverter.CreateUnary(Members: array of string; E: TJSElement): TJSUnary;
var
  unary: TJSUnary;
  asi: TJSSimpleAssignStatement;
begin
  unary := TJSUnary.Create(0, 0, '');
  asi := TJSSimpleAssignStatement.Create(0, 0, '');
  unary.A := asi;
  asi.Expr := E;
  asi.LHS := CreateMemberExpression(Members);
  Result := unary;
end;

function TPasToJSConverter.CreateMemberExpression(Members: array of string): TJSDotMemberExpression;
var
  pex: TJSPrimaryExpressionIdent;
  MExpr: TJSDotMemberExpression;
  LastMExpr: TJSDotMemberExpression;
  k: integer;
begin
  if Length(Members) < 2 then
    DoError(20161024192715,'internal error: member expression with less than two members');
  LastMExpr := nil;
  for k:=High(Members) downto Low(Members)+1 do
  begin
    MExpr := TJSDotMemberExpression.Create(0, 0, '');
    MExpr.Name := TJSString(Members[k]);
    if LastMExpr=nil then
      Result := MExpr
    else
      LastMExpr.MExpr := MExpr;
    LastMExpr := MExpr;
  end;
  pex := TJSPrimaryExpressionIdent.Create(0, 0, '');
  pex.Name := TJSString(Members[Low(Members)]);
  LastMExpr.MExpr := pex;
end;

function TPasToJSConverter.CreateCallExpression(El: TPasElement
  ): TJSCallExpression;
begin
  Result:=TJSCallExpression(CreateElement(TJSCallExpression,El));
  Result.Args:=TJSArguments(CreateElement(TJSArguments,El));
end;

{$IFDEF EnableOldClass}
procedure TPasToJSConverter.AddProcedureToClass(sl: TJSStatementList;
  E: TJSElement; const P: TPasProcedure);
var
  clname, funname: string;
  classfound: boolean;
  fundec, fd, main_const: TJSFunctionDeclarationStatement;
  SL2: TJSStatementList;
  un1: TJSUnary;
  asi: TJSAssignStatement;
  varname: TJSString;
begin
  SL2 := TJSStatementList(sl);
  clname := Copy(p.Name, 1, Pos('.', P.Name) - 1);
  funname := Copy(p.Name, Pos('.', P.Name) + 1, Length(p.Name) - Pos('.', P.Name));
  classfound := False;
  while Assigned(SL2) and (not classfound) do
  begin
    if SL2.A is TJSUnary then
    begin
      un1 := TJSUnary(SL2.A);
      asi := TJSAssignStatement(un1.A);
      varname := TJSPrimaryExpressionIdent(asi.LHS).Name;
      if varname = TJSString(clname) then
      begin
        classfound := True;
        fd := TJSFunctionDeclarationStatement(TJSCallExpression(asi.Expr).Expr);
      end;
    end;
    SL2 := TJSStatementList(SL2.B);
  end;

  if not (classfound) then
    Exit;

  fundec := GetFunctionDefinitionInUnary(fd, TJSString(funname), True);
  if Assigned(fundec) then
  begin
    if (p is TPasConstructor) then
    begin
      main_const := GetFunctionDefinitionInUnary(fd, TJSString(clname), False);
      main_const.AFunction := TJSFunctionDeclarationStatement(E).AFunction;
      main_const.AFunction.Name := TJSString(clname);
    end
    else
    begin
      fundec.AFunction := TJSFunctionDeclarationStatement(E).AFunction;
      fundec.AFunction.Name := '';
    end;
  end;
end;

function TPasToJSConverter.GetFunctionDefinitionInUnary(
  const fd: TJSFunctionDeclarationStatement; const funname: TJSString;
  inunary: boolean): TJSFunctionDeclarationStatement;
var
  k: integer;
  fundec: TJSFunctionDeclarationStatement;
  je: TJSElement;
  cname: TJSString;
begin
  Result := nil;
  for k := 0 to TJSSourceElements(FD.AFunction.Body.A).Statements.Count - 1 do
  begin
    je := TJSSourceElements(FD.AFunction.Body.A).Statements.Nodes[k].Node;
    if inunary then
      cname := GetFunctionUnaryName(je, fundec)
    else
    begin
      if je is TJSFunctionDeclarationStatement then
      begin
        cname := TJSFunctionDeclarationStatement(je).AFunction.Name;
        fundec := TJSFunctionDeclarationStatement(je);
      end;
    end;
    if funname = cname then
      Result := fundec;
  end;
end;

function TPasToJSConverter.GetFunctionUnaryName(var je: TJSElement;
  out fundec: TJSFunctionDeclarationStatement): TJSString;
var
  cname: TJSString;
  asi: TJSAssignStatement;
  un1: TJSUnary;
begin
  fundec:=nil;
  if not (je is TJSUnary) then
    Exit;
  un1 := TJSUnary(je);
  asi := TJSAssignStatement(un1.A);
  if not (asi.Expr is TJSFunctionDeclarationStatement) then
    Exit;
  fundec := TJSFunctionDeclarationStatement(asi.Expr);
  cname := TJSDotMemberExpression(asi.LHS).Name;
  Result := cname;
end;
{$ENDIF}

function TPasToJSConverter.CreateUsesList(UsesSection: TPasSection;
  AContext: TConvertContext): TJSArrayLiteral;
var
  ArgArray: TJSArrayLiteral;
  k: Integer;
  El: TPasElement;
  anUnitName: String;
  ArgEx: TJSLiteral;
  UsesList: TFPList;
begin
  UsesList:=UsesSection.UsesList;
  ArgArray:=TJSArrayLiteral.Create(0,0);
  if UsesList<>nil then
    for k:=0 to UsesList.Count-1 do
      begin
      El:=TPasElement(UsesList[k]);
      if not (El is TPasModule) then continue;
      anUnitName := TransformVariableName(TPasModule(El),AContext);
      ArgEx := CreateLiteralString(UsesSection,anUnitName);
      ArgArray.Elements.AddElement.Expr := ArgEx;
      end;
  Result:=ArgArray;
end;

procedure TPasToJSConverter.AddToStatementList(var First,
  Last: TJSStatementList; Add: TJSElement; Src: TPasElement);
var
  SL2: TJSStatementList;
begin
  if not Assigned(Add) then exit;
  if Add is TJSStatementList then
    begin
    // add list
    if TJSStatementList(Add).A=nil then
      begin
      // empty list -> skip
      if TJSStatementList(Add).B<>nil then
        raise Exception.Create('internal error: AddToStatementList add list A=nil, B<>nil, B='+TJSStatementList(Add).B.ClassName);
      FreeAndNil(Add);
      end
    else if Last=nil then
      begin
      // our list is not yet started -> simply take the extra list
      Last:=TJSStatementList(Add);
      First:=Last;
      end
    else
      begin
      // merge lists (append)
      if Last.B<>nil then
        begin
        // add a nil to the end of chain
        SL2:=TJSStatementList(CreateElement(TJSStatementList,Src));
        SL2.A:=Last.B;
        Last.B:=SL2;
        Last:=SL2;
        // Last.B is now nil
        end;
      Last.B:=Add;
      while Last.B is TJSStatementList do
        Last:=TJSStatementList(Last.B);
      end;
    end
  else
    begin
    if Last=nil then
      begin
      // start list
      Last:=TJSStatementList(CreateElement(TJSStatementList,Src));
      First:=Last;
      Last.A:=Add;
      end
    else if Last.B=nil then
      // second element
      Last.B:=Add
    else
      begin
      // add to chain
      while Last.B is TJSStatementList do
        Last:=TJSStatementList(Last.B);
      SL2:=TJSStatementList(CreateElement(TJSStatementList,Src));
      SL2.A:=Last.B;
      Last.B:=SL2;
      Last:=SL2;
      Last.B:=Add;
      end;
    end;
end;

function TPasToJSConverter.CreateValInit(PasType: TPasType; Expr: TPasElement;
  El: TPasElement; AContext: TConvertContext): TJSElement;
var
  T: TPasType;
  Lit: TJSLiteral;
  bt: TResolverBaseType;
begin
  T:=PasType;
  if AContext.Resolver<>nil then
    T:=AContext.Resolver.ResolveAliasType(T);
  if (T is TPasArrayType) then
    Result:=CreateArrayInit(TPasArrayType(T),Expr,El,AContext)
  else if T is TPasRecordType then
    Result:=CreateRecordInit(TPasRecordType(T),Expr,El,AContext)
  else if Assigned(Expr) then
    Result:=ConvertElement(Expr,AContext)
  else if T is TPasSetType then
    Result:=TJSObjectLiteral(CreateElement(TJSObjectLiteral,El))
  else
    begin
    // always init with a default value to create a typed variable (faster and more readable)
    Lit:=TJSLiteral(CreateElement(TJSLiteral,El));
    Result:=Lit;
    if T=nil then
      Lit.Value.IsUndefined:=true
    else if (T.ClassType=TPasPointerType)
        or (T.ClassType=TPasClassType)
        or (T.ClassType=TPasClassOfType)
        or (T.ClassType=TPasProcedureType)
        or (T.ClassType=TPasFunctionType) then
      Lit.Value.IsNull:=true
    else if T.ClassType=TPasStringType then
      Lit.Value.AsString:=''
    else if T.ClassType=TPasEnumType then
      Lit.Value.AsNumber:=0
    else if T.ClassType=TPasUnresolvedSymbolRef then
      begin
      if T.CustomData is TResElDataBaseType then
        begin
        bt:=TResElDataBaseType(T.CustomData).BaseType;
        if bt in btAllInteger then
          Lit.Value.AsNumber:=0
        else if bt in btAllFloats then
          Lit.Value.CustomValue:='0.0'
        else if bt in btAllStringAndChars then
          Lit.Value.AsString:=''
        else if bt in btAllBooleans then
          Lit.Value.AsBoolean:=false
        else if bt in [btNil,btPointer,btProc] then
          Lit.Value.IsNull:=true
        else
          begin
          {$IFDEF VerbosePas2JS}
          writeln('TPasToJSConverter.CreateVarInit unknown PasType T=',GetObjName(T),' basetype=',BaseTypeNames[bt]);
          {$ENDIF}
          RaiseNotSupported(PasType,AContext,20170208162121);
          end;
        end
      else if (CompareText(T.Name,'longint')=0)
           or (CompareText(T.Name,'int64')=0)
           or (CompareText(T.Name,'real')=0)
           or (CompareText(T.Name,'double')=0)
           or (CompareText(T.Name,'single')=0) then
        Lit.Value.AsNumber:=0.0
      else if (CompareText(T.Name,'boolean')=0) then
        Lit.Value.AsBoolean:=false
      else if (CompareText(T.Name,'string')=0)
           or (CompareText(T.Name,'char')=0)
      then
        Lit.Value.AsString:=''
      else
        begin
        Lit.Value.IsUndefined:=true;
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.CreateVarInit unknown PasType class=',T.ClassName,' name=',T.Name);
        {$ENDIF}
        end;
      end
    else
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.CreateValInit unknown PasType ',GetObjName(T));
      {$ENDIF}
      RaiseNotSupported(PasType,AContext,20170208161506);
      end;
    end;
end;

function TPasToJSConverter.CreateVarInit(El: TPasVariable;
  AContext: TConvertContext): TJSElement;
begin
  Result:=CreateValInit(El.VarType,El.Expr,El,AContext);
end;

function TPasToJSConverter.CreateLiteralNumber(El: TPasElement;
  const n: TJSNumber): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.AsNumber:=n;
end;

function TPasToJSConverter.CreateLiteralString(El: TPasElement; const s: string
  ): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.AsString:=TJSString(s);
end;

function TPasToJSConverter.CreateLiteralJSString(El: TPasElement;
  const s: TJSString): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.AsString:=s;
end;

function TPasToJSConverter.CreateLiteralBoolean(El: TPasElement; b: boolean
  ): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.AsBoolean:=b;
end;

function TPasToJSConverter.CreateLiteralNull(El: TPasElement): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.IsNull:=true;
end;

function TPasToJSConverter.CreateLiteralUndefined(El: TPasElement): TJSLiteral;
begin
  Result:=TJSLiteral(CreateElement(TJSLiteral,El));
  Result.Value.IsUndefined:=true;
end;

function TPasToJSConverter.CreateRecordInit(aRecord: TPasRecordType;
  Expr: TPasElement; El: TPasElement; AContext: TConvertContext): TJSElement;
// new recordtype()
var
  NewMemE: TJSNewMemberExpression;
begin
  if Expr<>nil then
    RaiseNotSupported(Expr,AContext,20161024192747);
  NewMemE:=TJSNewMemberExpression(CreateElement(TJSNewMemberExpression,El));
  Result:=NewMemE;
  NewMemE.MExpr:=CreateReferencePathExpr(aRecord,AContext);
end;

function TPasToJSConverter.CreateArrayInit(ArrayType: TPasArrayType;
  Expr: TPasElement; El: TPasElement; AContext: TConvertContext): TJSElement;
var
  Call: TJSCallExpression;
  DimArray, ArrLit: TJSArrayLiteral;
  i, DimSize: Integer;
  RangeResolved, ElTypeResolved, ExprResolved: TPasResolverResult;
  Range: TPasExpr;
  Lit: TJSLiteral;
  CurArrayType: TPasArrayType;
  DefaultValue: TJSElement;
  ArrayValues: TPasExprArray;
begin
  if Assigned(Expr) then
    begin
    // init array with constant(s)
    if AContext.Resolver=nil then
      DoError(20161024192739,nInitializedArraysNotSupported,sInitializedArraysNotSupported,[],ArrayType);
    ArrLit:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El));
    try
      AContext.Resolver.ComputeElement(Expr,ExprResolved,[rcConstant]);
      if (ExprResolved.BaseType=btArray)
          and (ExprResolved.ExprEl is TArrayValues) then
        begin
        ArrayValues:=TArrayValues(ExprResolved.ExprEl).Values;
        for i:=0 to length(ArrayValues)-1 do
          ArrLit.Elements.AddElement.Expr:=ConvertElement(ArrayValues[i],AContext);
        end
      else
        RaiseNotSupported(Expr,AContext,20170223133034);
      Result:=ArrLit;
    finally
      if Result=nil then
        ArrLit.Free;
    end;
    end
  else if length(ArrayType.Ranges)=0 then
    begin
    // empty dynamic array: []
    Result:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El));
    end
  else
    begin
    // static array
    // create "rtl.arrayNewMultiDim([dim1,dim2,...],defaultvalue)"
    if AContext.Resolver=nil then
      RaiseNotSupported(El,AContext,20170223113050,'');
    Result:=nil;
    try
      Call:=CreateCallExpression(El);
      Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameArray_NewMultiDim]);
      // add parameter [dim1,dim2,...]
      DimArray:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El));
      Call.Args.Elements.AddElement.Expr:=DimArray;
      CurArrayType:=ArrayType;
      while true do
        begin
        for i:=0 to length(CurArrayType.Ranges)-1 do
          begin
          Range:=CurArrayType.Ranges[i];
          // compute size of this dimension
          AContext.Resolver.ComputeElement(Range,RangeResolved,[rcConstant]);
          DimSize:=AContext.Resolver.GetRangeLength(RangeResolved);
          if DimSize=0 then
            RaiseNotSupported(Range,AContext,20170223113318);
          Lit:=CreateLiteralNumber(El,DimSize);
          DimArray.Elements.AddElement.Expr:=Lit;
          end;
        AContext.Resolver.ComputeElement(CurArrayType.ElType,ElTypeResolved,[rcType]);
        if (ElTypeResolved.TypeEl is TPasArrayType) then
          begin
          CurArrayType:=TPasArrayType(ElTypeResolved.TypeEl);
          if length(CurArrayType.Ranges)>0 then
            begin
            // nested static array
            continue;
            end;
          end;
        break;
        end;

      // add parameter defaultvalue
      DefaultValue:=CreateValInit(ElTypeResolved.TypeEl,nil,El,AContext);
      Call.Args.Elements.AddElement.Expr:=DefaultValue;

      Result:=Call;
    finally
      if Result=nil then
        Call.Free;
    end;
    end;
end;

function TPasToJSConverter.CreateReferencePath(El: TPasElement;
  AContext: TConvertContext; Kind: TRefPathKind; Full: boolean;
  Ref: TResolvedReference): string;
{ Notes:
 - local var, argument or result variable, even higher lvl does not need a reference path
   local vars are also argument, result var, result variable
 - 'this':
   - in interface function (even nested) 'this' is the interface,
   - in implementation function (even nested) 'this' is the implementation,
   - in initialization 'this' is interface
   - in method body 'this' is the instance
   - in class method body 'this' is the class
 otherwise use absolute path
}

  function IsLocalVar: boolean;
  begin
    Result:=false;
    if El.ClassType=TPasArgument then
      exit(true);
    if El.ClassType=TPasResultElement then
      exit(true);
    if AContext.Resolver=nil then
      exit(true);
    if El.Parent=nil then
      RaiseNotSupported(El,AContext,20170203121306,GetObjName(El));
    if El.Parent.ClassType=TPasImplExceptOn then
      exit(true);
    if not (El.Parent is TProcedureBody) then exit;
    Result:=true;
  end;

  procedure Prepend(var aPath: string; Prefix: string);
  begin
    if aPath<>'' then
      aPath:='.'+aPath;
    aPath:=Prefix+aPath;
  end;

  function IsClassFunction(Proc: TPasElement): boolean;
  begin
    if Proc=nil then exit(false);
    Result:=(Proc.ClassType=TPasClassFunction) or (Proc.ClassType=TPasClassProcedure)
      or (Proc.ClassType=TPasClassConstructor) or (Proc.ClassType=TPasClassDestructor);
  end;

var
  FoundModule: TPasModule;
  This, ParentEl: TPasElement;
  Dot: TDotContext;
  ThisContext: TFunctionContext;
  WithData: TP2JWithData;
  ProcScope: TPasProcedureScope;
begin
  Result:='';
  //writeln('TPasToJSConverter.CreateReferencePath START El=',GetObjName(El),' Parent=',GetObjName(El.Parent),' Context=',GetObjName(AContext));

  if AContext is TDotContext then
    begin
    Dot:=TDotContext(AContext);
    if Dot.Resolver<>nil then
      begin
      if El is TPasVariable then
        begin
        //writeln('TPasToJSConverter.CreateReferencePath Left=',GetResolverResultDesc(Dot.LeftResolved),' Right=class var ',GetObjName(El));
        if (ClassVarModifiersType*TPasVariable(El).VarModifiers<>[])
            and (Dot.Access=caAssign)
            and Dot.Resolver.ResolvedElIsClassInstance(Dot.LeftResolved) then
          begin
          // writing a class var
          Result:='$class';
          end;
        end
      else if IsClassFunction(El) then
        begin
        if Dot.Resolver.ResolvedElIsClassInstance(Dot.LeftResolved) then
          // accessing a class method from an object, 'this' must be the class
          Result:='$class';
        end;
      end;
    end
  else if (Ref<>nil) and (Ref.WithExprScope<>nil) then
    begin
    // using local WITH var
    WithData:=Ref.WithExprScope.CustomData as TP2JWithData;
    Prepend(Result,WithData.WithVarName);
    end
  else if IsLocalVar then
    begin
    // El is local var -> does not need path
    end
  else
    begin
    // need full path
    if El.Parent=nil then
      RaiseNotSupported(El,AContext,20170201172141,GetObjName(El));
    if (El.CustomData is TPasProcedureScope) then
      begin
      ProcScope:=TPasProcedureScope(El.CustomData);
      if ProcScope.DeclarationProc<>nil then
        El:=ProcScope.DeclarationProc;
      end;
    ThisContext:=AContext.GetThisContext;
    if ThisContext<>nil then
      This:=ThisContext.GetThis
    else
      This:=nil;
    ParentEl:=El.Parent;
    while ParentEl<>nil do
      begin
      if (ParentEl.CustomData is TPasProcedureScope) then
        begin
        ProcScope:=TPasProcedureScope(ParentEl.CustomData);
        if ProcScope.DeclarationProc<>nil then
          ParentEl:=ProcScope.DeclarationProc;
        end;
      if ParentEl.ClassType=TImplementationSection then
        begin
        // element is in an implementation section
        if ParentEl=This then
          Prepend(Result,'this')
        else
          begin
          FoundModule:=El.GetModule;
          if FoundModule=nil then
            RaiseInconsistency(20161024192755);
          if AContext.GetRootModule=FoundModule then
            // in same unit -> use '$impl'
            Prepend(Result,VarNameImplementation)
          else
            // in other unit -> use pas.unitname.$impl
            Prepend(Result,VarNameModules
               +'.'+TransformModuleName(FoundModule,AContext)
               +'.'+VarNameImplementation);
          end;
        break;
        end
      else if ParentEl is TPasModule then
        begin
        // element is in an unit interface or program/library section
        if ParentEl=This then
          Prepend(Result,'this')
        else
          Prepend(Result,VarNameModules
            +'.'+TransformModuleName(TPasModule(ParentEl),AContext));
        break;
        end
      else if (ParentEl.ClassType=TPasClassType)
          or (ParentEl.ClassType=TPasRecordType) then
        begin
        // element is a class or record
        if Full then
          Prepend(Result,ParentEl.Name)
        else
          begin
          // Pascal and JS have similar scoping rules, so we can use 'this'.
          Result:='this';
          if (ThisContext<>nil) and (not IsClassFunction(ThisContext.PasElement)) then
            begin
            // 'this' is an class instance
            if El is TPasVariable then
              begin
              //writeln('TPasToJSConverter.CreateReferencePath class var ',GetObjName(El),' This=',GetObjName(This));
              if (ClassVarModifiersType*TPasVariable(El).VarModifiers<>[])
                  and (AContext.Access=caAssign) then
                begin
                  Result:=Result+'.$class'; // writing a class var
                end;
              end
            else if IsClassFunction(El) then
              Result:=Result+'.$class'; // accessing a class function
            end;
          break;
          end;
        end
      else if ParentEl.ClassType=TPasEnumType then
        Prepend(Result,ParentEl.Name);
      ParentEl:=ParentEl.Parent;
      end;
    end;
  if (Result<>'') and (Kind in [rpkPathWithDot,rpkPathAndName]) then
    Result:=Result+'.';
  if Kind=rpkPathAndName then
    Result:=Result+TransformVariableName(El,AContext);
end;

function TPasToJSConverter.CreateReferencePathExpr(El: TPasElement;
  AContext: TConvertContext; Full: boolean; Ref: TResolvedReference
  ): TJSPrimaryExpressionIdent;
var
  Name: String;
begin
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.CreateReferencePathExpr El="',GetObjName(El),'" El.Parent=',GetObjName(El.Parent));
  {$ENDIF}
  Name:=CreateReferencePath(El,AContext,rpkPathAndName,Full,Ref);
  Result:=CreateBuiltInIdentifierExpr(Name);
end;

{$IFDEF EnableOldClass}
function TPasToJSConverter.CreateProcedureDeclaration(const El: TPasElement
  ): TJSFunctionDeclarationStatement;
var
  FD: TJSFuncDef;
  FS: TJSFunctionDeclarationStatement;
begin
  FS := TJSFunctionDeclarationStatement(
    CreateElement(TJSFunctionDeclarationStatement, EL));
  Result := FS;
  FD := TJSFuncDef.Create;
  FS.AFunction := FD;
  Result := FS;
end;
{$ENDIF}

procedure TPasToJSConverter.CreateProcedureCall(var Call: TJSCallExpression;
  Args: TParamsExpr; TargetProc: TPasProcedureType; AContext: TConvertContext);
// create a call, adding call by reference and default values
begin
  if Call=nil then
    Call:=TJSCallExpression(CreateElement(TJSCallExpression,Args));
  if ((Args=nil) or (length(Args.Params)=0))
      and ((TargetProc=nil) or (TargetProc.Args.Count=0)) then
    exit;
  if Call.Args=nil then
    Call.Args:=TJSArguments(CreateElement(TJSArguments,Args));
  CreateProcedureCallArgs(Call.Args.Elements,Args,TargetProc,AContext);
end;

procedure TPasToJSConverter.CreateProcedureCallArgs(
  Elements: TJSArrayLiteralElements; Args: TParamsExpr;
  TargetProc: TPasProcedureType; AContext: TConvertContext);
// Add call arguments. Handle call by reference and default values
var
  ArgContext: TConvertContext;
  i: Integer;
  Arg: TJSElement;
  TargetArgs: TFPList;
  TargetArg: TPasArgument;
  OldAccess: TCtxAccess;
begin
  // get context
  ArgContext:=AContext;
  while ArgContext is TDotContext do
    ArgContext:=ArgContext.Parent;
  i:=0;
  OldAccess:=ArgContext.Access;
  if TargetProc<>nil then
    TargetArgs:=TargetProc.Args
  else
    TargetArgs:=nil;
  // add params
  if Args<>nil then
    while i<length(Args.Params) do
      begin
      if (TargetArgs<>nil) and (i<TargetArgs.Count) then
        TargetArg:=TPasArgument(TargetArgs[i])
      else
        TargetArg:=nil;
      Arg:=CreateProcCallArg(Args.Params[i],TargetArg,ArgContext);
      Elements.AddElement.Expr:=Arg;
      inc(i);
      end;
  // fill up default values
  if TargetProc<>nil then
    begin
    while i<TargetArgs.Count do
      begin
      TargetArg:=TPasArgument(TargetArgs[i]);
      if TargetArg.ValueExpr=nil then
        begin
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.CreateProcedureCallArgs missing default value: TargetProc=',TargetProc.Name,' i=',i);
        {$ENDIF}
        RaiseNotSupported(Args,AContext,20170201193601);
        end;
      AContext.Access:=caRead;
      Arg:=ConvertElement(TargetArg.ValueExpr,ArgContext);
      Elements.AddElement.Expr:=Arg;
      inc(i);
      end;
    end;
  ArgContext.Access:=OldAccess;
end;

function TPasToJSConverter.CreateProcCallArg(El: TPasExpr;
  TargetArg: TPasArgument; AContext: TConvertContext): TJSElement;
var
  ExprResolved, ArgResolved: TPasResolverResult;
  ExprFlags: TPasResolverComputeFlags;
begin
  Result:=nil;
  if TargetArg=nil then
    begin
    // simple conversion
    AContext.Access:=caRead;
    Result:=ConvertElement(El,AContext);
    exit;
    end;

  if not (TargetArg.Access in [argDefault,argVar,argOut,argConst]) then
    DoError(20170213220927,nPasElementNotSupported,sPasElementNotSupported,
            [AccessNames[TargetArg.Access]],El);

  AContext.Resolver.ComputeElement(TargetArg,ArgResolved,[]);
  ExprFlags:=[];
  if TargetArg.Access in [argVar,argOut] then
    Include(ExprFlags,rcNoImplicitProc)
  else if AContext.Resolver.IsProcedureType(ArgResolved) then
    Include(ExprFlags,rcNoImplicitProcType);
  AContext.Resolver.ComputeElement(El,ExprResolved,ExprFlags);

  // consider TargetArg access
  if TargetArg.Access in [argVar,argOut] then
    Result:=CreateProcCallArgRef(El,ExprResolved,TargetArg,AContext)
  else
    begin
    // pass as default, const or constref
    AContext.Access:=caRead;

    if (ExprResolved.BaseType=btNil) and (ArgResolved.TypeEl is TPasArrayType) then
      begin
      // arrays must never be null -> pass []
      Result:=TJSArrayLiteral(CreateElement(TJSArrayLiteral,El));
      exit;
      end;

    Result:=ConvertElement(El,AContext);

    if TargetArg.Access=argDefault then
      begin
      if (ExprResolved.BaseType=btSet) and (ExprResolved.IdentEl<>nil) then
        begin
        // right side is a set variable -> create reference
        {$IFDEF VerbosePas2JS}
        writeln('TPasToJSConverter.CreateProcedureCallArg create reference of SET variable Right={',GetResolverResultDesc(ExprResolved),'} AssignContext.RightResolved.IdentEl=',GetObjName(ExprResolved.IdentEl));
        {$ENDIF}
        // create  rtl.refSet(right)
        Result:=CreateReferencedSet(El,Result);
        exit;
        end
      else if ExprResolved.BaseType=btContext then
        begin
        if ExprResolved.TypeEl.ClassType=TPasRecordType then
          begin
          // right side is a record -> clone
          {$IFDEF VerbosePas2JS}
          writeln('TPasToJSConverter.CreateProcedureCallArg clone RECORD variable Right={',GetResolverResultDesc(ExprResolved),'} AssignContext.RightResolved.IdentEl=',GetObjName(ExprResolved.IdentEl));
          {$ENDIF}
          // create  "new RightRecordType(RightRecord)"
          Result:=CreateCloneRecord(El,ExprResolved,Result,AContext);
          exit;
          end;
        end;
      end;
    end;
end;

function TPasToJSConverter.CreateProcCallArgRef(El: TPasExpr;
  ResolvedEl: TPasResolverResult; TargetArg: TPasArgument;
  AContext: TConvertContext): TJSElement;
const
  GetPathName = 'p';
  SetPathName = 's';
  ParamName = 'a';
var
  Obj: TJSObjectLiteral;

  procedure AddVar(const aName: string; var Expr: TJSElement);
  var
    ObjLit: TJSObjectLiteralElement;
  begin
    if Expr=nil then exit;
    ObjLit:=Obj.Elements.AddElement;
    ObjLit.Name:=TJSString(aName);
    ObjLit.Expr:=Expr;
    Expr:=nil;
  end;

var
  ParamContext: TParamContext;
  FullGetter, GetPathExpr, SetPathExpr, GetExpr, SetExpr, ParamExpr: TJSElement;
  AssignSt: TJSSimpleAssignStatement;
  ObjLit: TJSObjectLiteralElement;
  FuncSt: TJSFunctionDeclarationStatement;
  RetSt: TJSReturnStatement;
  GetDotPos, SetDotPos: Integer;
  GetPath, SetPath: String;
  BracketExpr: TJSBracketMemberExpression;
  DotExpr: TJSDotMemberExpression;
begin
  // pass reference -> create a temporary JS object with a FullGetter and setter
  Obj:=nil;
  FullGetter:=nil;
  ParamContext:=TParamContext.Create(El,nil,AContext);
  GetPathExpr:=nil;
  SetPathExpr:=nil;
  GetExpr:=nil;
  SetExpr:=nil;
  try
    // create FullGetter and setter
    ParamContext.Access:=caByReference;
    ParamContext.Arg:=TargetArg;
    ParamContext.Expr:=El;
    ParamContext.ResolvedExpr:=ResolvedEl;
    FullGetter:=ConvertElement(El,ParamContext);
    // FullGetter is now a full JS expression to retrieve the value.
    if ParamContext.ReusingReference then
      begin
      // result is already a reference
      Result:=FullGetter;
      exit;
      end;

    // if ParamContext.Getter is set then
    // ParamContext.Getter is the last part of the FullGetter, that needs to
    // be replaced by ParamContext.Setter to create a FullSetter
    {$IFDEF VerbosePas2JS}
    writeln('TPasToJSConverter.CreateProcedureCallArg VAR FullGetter=',GetObjName(FullGetter),' Getter=',GetObjName(ParamContext.Getter),' Setter=',GetObjName(ParamContext.Setter));
    {$ENDIF}
    if (ParamContext.Getter=nil)<>(ParamContext.Setter=nil) then
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.CreateProcedureCallArg FullGetter=',GetObjName(FullGetter),' Getter=',GetObjName(ParamContext.Getter),' Setter=',GetObjName(ParamContext.Setter));
      {$ENDIF}
      RaiseInconsistency(20170213222941);
      end;

    // create "{p:Result,get:function(){return this.p.Getter},set:function(v){this.p.Setter(v);}}"
    Obj:=TJSObjectLiteral(CreateElement(TJSObjectLiteral,El));

    if FullGetter.ClassType=TJSPrimaryExpressionIdent then
      begin
      // create "{get:function(){return FullGetter;},set:function(v){FullGetter=v;}}"
      if (ParamContext.Getter<>nil) and (ParamContext.Getter<>FullGetter) then
        RaiseInconsistency(20170213224339);
      GetPath:=String(TJSPrimaryExpressionIdent(FullGetter).Name);
      GetDotPos:=PosLast('.',GetPath);
      if GetDotPos>0 then
        begin
        // e.g. this.readvar
        // create
        //    GetPathExpr: this
        //    GetExpr:     p.readvar
        // Will create "{p:GetPathExpr, get:function(){return GetExpr;},set:...}"
        GetPathExpr:=CreateBuiltInIdentifierExpr(LeftStr(GetPath,GetDotPos-1));
        GetExpr:=CreateDotExpression(El,CreateBuiltInIdentifierExpr('this.'+GetPathName),
            CreateBuiltInIdentifierExpr(copy(GetPath,GetDotPos+1)));
        if ParamContext.Setter=nil then
          SetExpr:=CreateDotExpression(El,CreateBuiltInIdentifierExpr('this.'+GetPathName),
            CreateBuiltInIdentifierExpr(copy(GetPath,GetDotPos+1)));
        end
      else
        begin
        // local var
        GetExpr:=FullGetter;
        FullGetter:=nil;
        if ParamContext.Setter=nil then
          SetExpr:=CreateBuiltInIdentifierExpr(GetPath);
        end;

      if ParamContext.Setter<>nil then
        begin
        // custom Setter
        SetExpr:=ParamContext.Setter;
        ParamContext.Setter:=nil;
        if SetExpr.ClassType=TJSPrimaryExpressionIdent then
          begin
          SetPath:=String(TJSPrimaryExpressionIdent(SetExpr).Name);
          SetDotPos:=PosLast('.',SetPath);
          FreeAndNil(SetExpr);
          if LeftStr(GetPath,GetDotPos)=LeftStr(SetPath,SetDotPos) then
            begin
            // use GetPathExpr for setter
            SetExpr:=CreateDotExpression(El,CreateBuiltInIdentifierExpr('this.'+GetPathName),
                CreateBuiltInIdentifierExpr(copy(SetPath,GetDotPos+1)));
            end
          else
            begin
            // setter needs its own SetPathExpr
            SetPathExpr:=CreateBuiltInIdentifierExpr(LeftStr(SetPath,SetDotPos-1));
            SetExpr:=CreateDotExpression(El,CreateBuiltInIdentifierExpr('this.'+SetPathName),
                CreateBuiltInIdentifierExpr(copy(SetPath,GetDotPos+1)));
            end;
          end;
        end;
      end
    else if FullGetter.ClassType=TJSDotMemberExpression then
      begin
      if ParamContext.Setter<>nil then
        RaiseNotSupported(El,AContext,20170214231900);
      // convert  this.r.i  to
      // {p:this.r,
      //  get:function{return this.p.i;},
      //  set:function(v){this.p.i=v;}
      // }
      // GetPathExpr:  this.r
      // GetExpr:  this.p.i
      // SetExpr:  this.p.i
      DotExpr:=TJSDotMemberExpression(FullGetter);
      GetPathExpr:=DotExpr.MExpr;
      DotExpr.MExpr:=CreateBuiltInIdentifierExpr('this.'+GetPathName);
      GetExpr:=DotExpr;
      FullGetter:=nil;
      SetExpr:=CreateDotExpression(El,
        CreateBuiltInIdentifierExpr('this.'+GetPathName),
        CreateBuiltInIdentifierExpr(String(DotExpr.Name)));
      end
    else if FullGetter.ClassType=TJSBracketMemberExpression then
      begin
      if ParamContext.Setter<>nil then
        RaiseNotSupported(El,AContext,20170214215150);
      // convert  this.arr[value]  to
      // {a:value,
      //  p:this.arr,
      //  get:function{return this.p[this.a];},
      //  set:function(v){this.p[this.a]=v;}
      // }

      // create "a:value"
      BracketExpr:=TJSBracketMemberExpression(FullGetter);
      ParamExpr:=BracketExpr.Name;
      BracketExpr.Name:=CreateBuiltInIdentifierExpr('this.'+ParamName);
      AddVar(ParamName,ParamExpr);

      // create GetPathExpr "this.arr"
      GetPathExpr:=BracketExpr.MExpr;
      BracketExpr.MExpr:=CreateBuiltInIdentifierExpr('this.'+GetPathName);

      // GetExpr  "this.p[this.a]"
      GetExpr:=BracketExpr;
      FullGetter:=nil;

      // SetExpr  "this.p[this.a]"
      BracketExpr:=TJSBracketMemberExpression(CreateElement(TJSBracketMemberExpression,El));
      SetExpr:=BracketExpr;
      BracketExpr.MExpr:=CreateBuiltInIdentifierExpr('this.'+GetPathName);
      BracketExpr.Name:=CreateBuiltInIdentifierExpr('this.'+ParamName);

      end
    else
      begin
      {$IFDEF VerbosePas2JS}
      writeln('TPasToJSConverter.CreateProcedureCallArg FullGetter=',GetObjName(FullGetter),' Getter=',GetObjName(ParamContext.Getter),' Setter=',GetObjName(ParamContext.Setter));
      {$ENDIF}
      RaiseNotSupported(El,AContext,20170213230336);
      end;

    if (SetExpr.ClassType=TJSPrimaryExpressionIdent)
        or (SetExpr.ClassType=TJSDotMemberExpression)
        or (SetExpr.ClassType=TJSBracketMemberExpression) then
      begin
      // create   SetExpr = v;
      AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
      AssignSt.LHS:=SetExpr;
      AssignSt.Expr:=CreateBuiltInIdentifierExpr(TempRefObjSetterArgName);
      SetExpr:=AssignSt;
      end
    else if (SetExpr.ClassType=TJSCallExpression) then
      // has already the form  Func(v)
    else
      RaiseInconsistency(20170213225940);

    // add   p:GetPathExpr
    AddVar(GetPathName,GetPathExpr);

    // add   get:function(){ return GetExpr; }
    ObjLit:=Obj.Elements.AddElement;
    ObjLit.Name:=TempRefObjGetterName;
    FuncSt:=CreateFunction(El);
    ObjLit.Expr:=FuncSt;
    RetSt:=TJSReturnStatement(CreateElement(TJSReturnStatement,El));
    FuncSt.AFunction.Body.A:=RetSt;
    RetSt.Expr:=GetExpr;
    GetExpr:=nil;

    // add   s:GetPathExpr
    AddVar(SetPathName,SetPathExpr);

    // add   set:function(v){ SetExpr }
    ObjLit:=Obj.Elements.AddElement;
    ObjLit.Name:=TempRefObjSetterName;
    FuncSt:=CreateFunction(El);
    ObjLit.Expr:=FuncSt;
    FuncSt.AFunction.Params.Add(TempRefObjSetterArgName);
    FuncSt.AFunction.Body.A:=SetExpr;
    SetExpr:=nil;

    Result:=Obj;
  finally
    if Result=nil then
      begin
      GetPathExpr.Free;
      SetPathExpr.Free;
      GetExpr.Free;
      SetExpr.Free;
      Obj.Free;
      ParamContext.Setter.Free;
      FullGetter.Free;
      end;
    ParamContext.Free;
  end;
end;

function TPasToJSConverter.ConvertExceptOn(El: TPasImplExceptOn;
  AContext: TConvertContext): TJSElement;
// convert "on T do ;" to "if(T.isPrototypeOf(exceptObject)){}"
// convert "on E:T do ;" to "if(T.isPrototypeOf(exceptObject)){ var E=exceptObject; }"
Var
  IfSt : TJSIfStatement;
  ListFirst , ListLast: TJSStatementList;
  DotExpr: TJSDotMemberExpression;
  Call: TJSCallExpression;
  V: TJSVariableStatement;
  VarDecl: TJSVarDeclaration;

begin
  Result:=nil;
  // create "if()"
  IfSt:=TJSIfStatement(CreateElement(TJSIfStatement,El));
  try
    // create "T.isPrototypeOf"
    DotExpr:=TJSDotMemberExpression(CreateElement(TJSDotMemberExpression,El));
    DotExpr.MExpr:=CreateReferencePathExpr(El.TypeEl,AContext);
    DotExpr.Name:='isPrototypeOf';
    // create "T.isPrototypeOf(exceptObject)"
    Call:=CreateCallExpression(El);
    Call.Expr:=DotExpr;
    Call.Args.Elements.AddElement.Expr:=CreateBuiltInIdentifierExpr(GetExceptionObjectName(AContext));
    IfSt.Cond:=Call;

    if El.VarEl<>nil then
      begin
      // add "var E=exceptObject;"
      ListFirst:=TJSStatementList(CreateElement(TJSStatementList,El.Body));
      ListLast:=ListFirst;
      IfSt.BTrue:=ListFirst;
      V:=TJSVariableStatement(CreateElement(TJSVariableStatement,El));
      ListFirst.A:=V;
      VarDecl:=TJSVarDeclaration(CreateElement(TJSVarDeclaration,El));
      V.A:=VarDecl;
      VarDecl.Name:=TransformVariableName(El,El.VariableName,AContext);
      VarDecl.Init:=CreateBuiltInIdentifierExpr(GetExceptionObjectName(AContext));
      // add statements
      AddToStatementList(ListFirst,ListLast,ConvertElement(El.Body,AContext),El);
      end
    else
      // add statements
      IfSt.BTrue:=ConvertElement(El.Body,AContext);

    Result:=IfSt;
  finally
    if Result=nil then
      IfSt.Free;
  end;
end;

function TPasToJSConverter.ConvertStatement(El: TPasImplStatement;
  AContext: TConvertContext): TJSElement;

begin
  Result:=Nil;
  if (El is TPasImplRaise) then
    Result:=ConvertRaiseStatement(TPasImplRaise(El),AContext)
  else if (El is TPasImplAssign) then
    Result:=ConvertAssignStatement(TPasImplAssign(El),AContext)
  else if (El is TPasImplWhileDo) then
    Result:=ConvertWhileStatement(TPasImplWhileDo(El),AContext)
  else if (El is TPasImplSimple) then
    Result:=ConvertSimpleStatement(TPasImplSimple(El),AContext)
  else if (El is TPasImplWithDo) then
    Result:=ConvertWithStatement(TPasImplWithDo(El),AContext)
  else if (El is TPasImplExceptOn) then
    Result:=ConvertExceptOn(TPasImplExceptOn(El),AContext)
  else if (El is TPasImplForLoop) then
    Result:=ConvertForStatement(TPasImplForLoop(El),AContext)
  else if (El is TPasImplAsmStatement) then
    Result:=ConvertAsmStatement(TPasImplAsmStatement(El),AContext)
  else
    RaiseNotSupported(El,AContext,20161024192759);
{
  TPasImplCaseStatement = class(TPasImplStatement)
}
end;

function TPasToJSConverter.ConvertCommands(El: TPasImplCommands;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192806);
  Result:=Nil;
  // ToDo: TPasImplCommands = class(TPasImplElement)
end;

function TPasToJSConverter.ConvertConst(El: TPasConst; AContext: TConvertContext
  ): TJSElement;
begin
  Result:=nil;
  RaiseNotSupported(El,AContext,20161024193129);
end;

function TPasToJSConverter.ConvertLabelMark(El: TPasImplLabelMark;
  AContext: TConvertContext): TJSElement;

begin
  RaiseNotSupported(El,AContext,20161024192857);
  Result:=Nil;
  // ToDo:   TPasImplLabelMark = class(TPasImplLabelMark) then
end;

function TPasToJSConverter.ConvertElement(El: TPasElement;
  AContext: TConvertContext): TJSElement;
var
  C: TClass;
begin
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertElement El=',GetObjName(El),' Context=',GetObjName(AContext));
  {$ENDIF}
  if El=nil then
    begin
    Result:=nil;
    RaiseInconsistency(20161024190203);
    end;
  C:=El.ClassType;
  If (C=TPasPackage)  then
    Result:=ConvertPackage(TPasPackage(El),AContext)
  else if (C=TPasResString) then
    Result:=ConvertResString(TPasResString(El),AContext)
  else if (C=TPasConst) then
    Result:=ConvertConst(TPasConst(El),AContext)
  else if (C=TPasProperty) then
    Result:=ConvertProperty(TPasProperty(El),AContext)
  else if (C=TPasVariable) then
    Result:=ConvertVariable(TPasVariable(El),AContext)
  else if (C=TPasExportSymbol) then
    Result:=ConvertExportSymbol(TPasExportSymbol(El),AContext)
  else if (C=TPasLabels) then
    Result:=ConvertLabels(TPasLabels(El),AContext)
  else if (C=TPasImplCommand) then
    Result:=ConvertCommand(TPasImplCommand(El),AContext)
  else if (C=TPasImplCommands) then
    Result:=ConvertCommands(TPasImplCommands(El),AContext)
  else if (C=TPasImplLabelMark) then
    Result:=ConvertLabelMark(TPasImplLabelMark(El),AContext)
  else if C.InheritsFrom(TPasExpr) then
    Result:=ConvertExpression(TPasExpr(El),AContext)
  else if C.InheritsFrom(TPasDeclarations) then
    Result:=ConvertDeclarations(TPasDeclarations(El),AContext)
  else if C.InheritsFrom(TPasProcedure) then
    Result:=ConvertProcedure(TPasProcedure(El),AContext)
  else if C.InheritsFrom(TPasImplBlock) then
    Result:=ConvertImplBlock(TPasImplBlock(El),AContext)
  else if C.InheritsFrom(TPasModule)  then
    Result:=ConvertModule(TPasModule(El),AContext)
  else
    begin
    Result:=nil;
    RaiseNotSupported(El, AContext, 20161024190449);
    end;
  {$IFDEF VerbosePas2JS}
  writeln('TPasToJSConverter.ConvertElement END ',GetObjName(El));
  {$ENDIF}
end;

function TPasToJSConverter.ConvertRecordType(El: TPasRecordType;
  AContext: TConvertContext): TJSElement;
(*
  type
    TMyRecord = record
      i: longint;
      s: string;
      d: double;
      r: TOtherRecord;
    end;

    this.TMyRecord=function(s) {
      if (s){
        this.i = s.i;
        this.s = s.s;
        this.d = s.d;
        this.r = new this.TOtherRecord(s.r);
      } else {
        this.i = 0;
        this.s = "";
        this.d = 0.0;
        this.r = new this.TOtherRecord();
      };
      this.$equal = function(b){
        return (this.i == b.i) && (this.s == b.s) && (this.d == b.d)
          && (this.r.$equal(b.r))
      };
    };
*)
const
  SrcParamName = 's';
  EqualParamName = 'b';

  procedure AddCloneStatements(IfSt: TJSIfStatement;
    FuncContext: TFunctionContext);
  var
    i: Integer;
    PasVar: TPasVariable;
    VarAssignSt: TJSSimpleAssignStatement;
    First, Last: TJSStatementList;
    VarDotExpr: TJSDotMemberExpression;
    PasVarType: TPasType;
    ResolvedPasVar: TPasResolverResult;
  begin
    // init members with s
    First:=nil;
    Last:=nil;
    for i:=0 to El.Members.Count-1 do
      begin
      PasVar:=TPasVariable(El.Members[i]);
      // create 'this.A = s.A;'
      VarAssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,PasVar));
      AddToStatementList(First,Last,VarAssignSt,PasVar);
      if i=0 then IfSt.BTrue:=First;
      VarAssignSt.LHS:=CreateDeclNameExpression(PasVar,PasVar.Name,FuncContext);
      VarDotExpr:=TJSDotMemberExpression(CreateElement(TJSDotMemberExpression,PasVar));
      VarAssignSt.Expr:=VarDotExpr;
      VarDotExpr.MExpr:=CreateBuiltInIdentifierExpr(SrcParamName);
      VarDotExpr.Name:=TJSString(TransformVariableName(PasVar,FuncContext));
      if (AContext.Resolver<>nil) then
        begin
        PasVarType:=AContext.Resolver.ResolveAliasType(PasVar.VarType);
        if PasVarType.ClassType=TPasRecordType then
          begin
          SetResolverIdentifier(ResolvedPasVar,btContext,PasVar,PasVarType,[rrfReadable,rrfWritable]);
          VarAssignSt.Expr:=CreateCloneRecord(PasVar,ResolvedPasVar,VarDotExpr,FuncContext);
          continue;
          end
        else if PasVarType.ClassType=TPasSetType then
          begin
          VarAssignSt.Expr:=CreateReferencedSet(PasVar,VarDotExpr);
          continue;
          end
        end;
      end;
  end;

  procedure AddInitDefaultStatements(IfSt: TJSIfStatement;
    FuncContext: TFunctionContext);
  var
    i: Integer;
    PasVar: TPasVariable;
    JSVar: TJSElement;
    First, Last: TJSStatementList;
  begin
    // the "else" part:
    // when there is no s parameter, init members with default value
    First:=nil;
    Last:=nil;
    for i:=0 to El.Members.Count-1 do
      begin
      PasVar:=TPasVariable(El.Members[i]);
      JSVar:=CreateVarDecl(PasVar,FuncContext);
      AddToStatementList(First,Last,JSVar,PasVar);
      if IfSt.BFalse=nil then
        IfSt.BFalse:=First;
      end;
  end;

  procedure Add_AndExpr_ToReturnSt(RetSt: TJSReturnStatement;
    PasVar: TPasVariable; var LastAndExpr: TJSLogicalAndExpression;
    Expr: TJSElement);
  var
    AndExpr: TJSLogicalAndExpression;
  begin
    if RetSt.Expr=nil then
      RetSt.Expr:=Expr
    else
      begin
      AndExpr:=TJSLogicalAndExpression(CreateElement(TJSLogicalAndExpression,PasVar));
      if LastAndExpr=nil then
        begin
        AndExpr.A:=RetSt.Expr;
        RetSt.Expr:=AndExpr;
        end
      else
        begin
        AndExpr.A:=LastAndExpr.B;
        LastAndExpr.B:=AndExpr;
        end;
      AndExpr.B:=Expr;
      LastAndExpr:=AndExpr;
      end;
  end;

  procedure AddEqualFunction(var BodyFirst, BodyLast: TJSStatementList;
    FuncContext: TFunctionContext);
  // add equal function:
  // this.$equal = function(b){
  //   return (this.member1 == b.member1);
  // };
  var
    AssignSt: TJSSimpleAssignStatement;
    FD: TJSFuncDef;
    RetSt: TJSReturnStatement;
    i: Integer;
    PasVar: TPasVariable;
    FDS: TJSFunctionDeclarationStatement;
    EqExpr: TJSEqualityExpressionEQ;
    LastAndExpr: TJSLogicalAndExpression;
    VarType: TPasType;
    Call: TJSCallExpression;
    VarName: String;
  begin
    // add "this.$equal ="
    AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
    AssignSt.LHS:=CreateMemberExpression(['this',FuncNameRecordEqual]);
    AddToStatementList(BodyFirst,BodyLast,AssignSt,El);
    // add "function(b){"
    FDS:=CreateFunction(El);
    AssignSt.Expr:=FDS;
    FD:=FDS.AFunction;
    FD.Params.Add(EqualParamName);
    FD.Body:=TJSFunctionBody(CreateElement(TJSFunctionBody,El));
    // add "return "
    RetSt:=TJSReturnStatement(CreateElement(TJSReturnStatement,El));
    FD.Body.A:=RetSt;
    LastAndExpr:=nil;
    for i:=0 to El.Members.Count-1 do
      begin
      PasVar:=TPasVariable(El.Members[i]);
      // "this.member = b.member;"
      VarType:=PasVar.VarType;
      if FuncContext.Resolver<>nil then
        VarType:=FuncContext.Resolver.ResolveAliasType(VarType);
      VarName:=TransformVariableName(PasVar,FuncContext);
      if VarType.ClassType=TPasRecordType then
        begin
        // record
        // add "this.member.$equal(b.member)"
        Call:=CreateCallExpression(PasVar);
        Add_AndExpr_ToReturnSt(RetSt,PasVar,LastAndExpr,Call);
        Call.Expr:=CreateMemberExpression(['this',VarName,FuncNameRecordEqual]);
        Call.Args.Elements.AddElement.Expr:=CreateMemberExpression([EqualParamName,VarName]);
        end
      else if VarType.ClassType=TPasSetType then
        begin
        // set
        // add "rtl.eqSet(this.member,b.member)"
        Call:=CreateCallExpression(PasVar);
        Add_AndExpr_ToReturnSt(RetSt,PasVar,LastAndExpr,Call);
        Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameSet_Equal]);
        Call.Args.Elements.AddElement.Expr:=CreateMemberExpression(['this',VarName]);
        Call.Args.Elements.AddElement.Expr:=CreateMemberExpression([EqualParamName,VarName]);
        end
      else if VarType is TPasProcedureType then
        begin
        // proc type
        // add "rtl.eqCallback(this.member,b.member)"
        Call:=CreateCallExpression(PasVar);
        Add_AndExpr_ToReturnSt(RetSt,PasVar,LastAndExpr,Call);
        Call.Expr:=CreateMemberExpression([VarNameRTL,FuncNameProcType_Equal]);
        Call.Args.Elements.AddElement.Expr:=CreateMemberExpression(['this',VarName]);
        Call.Args.Elements.AddElement.Expr:=CreateMemberExpression([EqualParamName,VarName]);
        end
      else
        begin
        // default: use simple equal "=="
        EqExpr:=TJSEqualityExpressionEQ(CreateElement(TJSEqualityExpressionEQ,PasVar));
        Add_AndExpr_ToReturnSt(RetSt,PasVar,LastAndExpr,EqExpr);
        EqExpr.A:=CreateMemberExpression(['this',VarName]);
        EqExpr.B:=CreateMemberExpression([EqualParamName,VarName]);
        end;
      end;
  end;

var
  AssignSt: TJSSimpleAssignStatement;
  FDS: TJSFunctionDeclarationStatement;
  FD: TJSFuncDef;
  BodyFirst, BodyLast: TJSStatementList;
  FuncContext: TFunctionContext;
  Obj: TJSObjectLiteral;
  ObjLit: TJSObjectLiteralElement;
  IfSt: TJSIfStatement;
begin
  Result:=nil;
  FuncContext:=nil;
  AssignSt:=nil;
  try
    FDS:=CreateFunction(El);
    if AContext is TObjectContext then
      begin
      // add 'TypeName: function(){}'
      Obj:=TObjectContext(AContext).JSElement as TJSObjectLiteral;
      ObjLit:=Obj.Elements.AddElement;
      ObjLit.Name:=TJSString(TransformVariableName(El,AContext));
      ObjLit.Expr:=FDS;
      end
    else
      begin
      // add 'this.TypeName = function(){}'
      AssignSt:=TJSSimpleAssignStatement(CreateElement(TJSSimpleAssignStatement,El));
      AssignSt.LHS:=CreateDeclNameExpression(El,El.Name,AContext);
      AssignSt.Expr:=FDS;
      end;
    FD:=FDS.AFunction;
    // add param s
    FD.Params.Add(SrcParamName);
    // create function body
    FuncContext:=TFunctionContext.Create(El,FD.Body,AContext);
    FuncContext.This:=El;
    FuncContext.IsSingleton:=true;
    if El.Members.Count>0 then
      begin
      BodyFirst:=nil;
      BodyLast:=nil;

      // add if(s)
      IfSt:=TJSIfStatement(CreateElement(TJSIfStatement,El));
      AddToStatementList(BodyFirst,BodyLast,IfSt,El);
      FD.Body.A:=BodyFirst;
      IfSt.Cond:=CreateBuiltInIdentifierExpr(SrcParamName);
      // add clone statements
      AddCloneStatements(IfSt,FuncContext);
      // add init default statements
      AddInitDefaultStatements(IfSt,FuncContext);

      // add equal function
      AddEqualFunction(BodyFirst,BodyLast,FuncContext);

      end;
    Result:=AssignSt;
  finally
    FuncContext.Free;
    if Result=nil then AssignSt.Free;
  end;
end;

procedure TPasToJSConverter.DoError(Id: int64; const Msg: String);
var
  E: EPas2JS;
begin
  E:=EPas2JS.Create(Msg);
  E.Id:=Id;
  E.MsgType:=mtError;
  Raise E;
end;

procedure TPasToJSConverter.DoError(Id: int64; const Msg: String;
  const Args: array of const);
var
  E: EPas2JS;
begin
  E:=EPas2JS.CreateFmt(Msg,Args);
  E.Id:=Id;
  E.MsgType:=mtError;
  Raise E;
end;

procedure TPasToJSConverter.DoError(Id: int64; MsgNumber: integer;
  const MsgPattern: string; const Args: array of const; El: TPasElement);
var
  E: EPas2JS;
begin
  E:=EPas2JS.CreateFmt(MsgPattern,Args);
  E.PasElement:=El;
  E.MsgNumber:=MsgNumber;
  E.Id:=Id;
  E.MsgType:=mtError;
  CreateMsgArgs(E.Args,Args);
  raise E;
end;

procedure TPasToJSConverter.RaiseNotSupported(El: TPasElement;
  AContext: TConvertContext; Id: int64; const Msg: string);
var
  E: EPas2JS;
begin
  if AContext=nil then ;
  E:=EPas2JS.CreateFmt(sPasElementNotSupported,[GetObjName(El)]);
  if Msg<>'' then
    E.Message:=E.Message+': '+Msg;
  E.PasElement:=El;
  E.MsgNumber:=nPasElementNotSupported;
  SetLength(E.Args,1);
  E.Args[0]:=El.ClassName;
  E.Id:=Id;
  E.MsgType:=mtError;
  raise E;
end;

procedure TPasToJSConverter.RaiseIdentifierNotFound(Identifier: string;
  El: TPasElement; Id: int64);
var
  E: EPas2JS;
begin
  E:=EPas2JS.CreateFmt(sIdentifierNotFound,[Identifier]);
  E.PasElement:=El;
  E.MsgNumber:=nIdentifierNotFound;
  SetLength(E.Args,1);
  E.Args[0]:=Identifier;
  E.Id:=Id;
  E.MsgType:=mtError;
  raise E;
end;

function TPasToJSConverter.TransformVariableName(El: TPasElement;
  const AName: String; AContext: TConvertContext): String;
var
  i: Integer;
  c: Char;
begin
  if AContext=nil then ;
  if Pos('.',AName)>0 then
    RaiseInconsistency(20170203164711);
  if UseLowerCase then
    Result:=LowerCase(AName)
  else
    Result:=AName;
  if IsPreservedWord(Result) then
    begin
    for i:=1 to length(Result) do
      begin
      c:=Result[i];
      case c of
      'a'..'z','A'..'Z':
        begin
        Result[i]:=chr(ord(c) xor 32);
        break;
        end;
      end;
      end;
    if IsPreservedWord(Result) then
      RaiseNotSupported(El,AContext,20170203131832);
    end;
end;

function TPasToJSConverter.TransformVariableName(El: TPasElement;
  AContext: TConvertContext): String;
begin
  Result:=TransformVariableName(El,El.Name,AContext);
end;

function TPasToJSConverter.TransformModuleName(El: TPasModule;
  AContext: TConvertContext): String;
begin
  if El is TPasProgram then
    Result:='program'
  else
    Result:=TransformVariableName(El,AContext);
end;

function TPasToJSConverter.IsPreservedWord(aName: string): boolean;
var
  l, r, m, cmp: Integer;
begin
  Result:=true;
  if aName=VarNameModules then exit;
  if aName=VarNameRTL then exit;
  if aName=GetExceptionObjectName(nil) then exit;

  l:=low(JSReservedWords);
  r:=high(JSReservedWords);
  while l<=r do
    begin
    m:=(l+r) div 2;
    cmp:=CompareStr(aName,JSReservedWords[m]);
    //writeln('TPasToJSConverter.IsPreservedWord Name="',aName,'" l=',l,' r=',r,' m=',m,' JSReservedWords[m]=',JSReservedWords[m],' cmp=',cmp);
    if cmp>0 then
      l:=m+1
    else if cmp<0 then
      r:=m-1
    else
      exit;
    end;
  Result:=false;
end;

function TPasToJSConverter.ConvertPasElement(El: TPasElement;
  Resolver: TPasResolver): TJSElement;
var
  aContext: TRootContext;
begin
  aContext:=TRootContext.Create(El,nil,nil);
  try
    aContext.Resolver:=Resolver;
    Result:=ConvertElement(El,aContext);
  finally
    FreeAndNil(aContext);
  end;
end;

var
  i: integer;
initialization
  for i:=low(JSReservedWords) to High(JSReservedWords)-1 do
    if CompareStr(JSReservedWords[i],JSReservedWords[i+1])>=0 then
      raise Exception.Create('20170203135442 '+JSReservedWords[i]+' >= '+JSReservedWords[i+1]);

end.

