{-# LANGUAGE OverloadedStrings #-}

module Amy.Codegen.Pure
  ( codegenPure
  ) where

import qualified Data.ByteString.Char8 as BS8
import Data.ByteString.Short (ShortByteString)
import qualified Data.ByteString.Short as BSS
import Data.Foldable (forM_, toList)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text, unpack)
import Data.Text.Encoding (encodeUtf8)
import LLVM.AST as LLVM
import LLVM.AST.AddrSpace
import qualified LLVM.AST.CallingConvention as CC
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.Float as F
import qualified LLVM.AST.IntegerPredicate as IP
import LLVM.AST.Global as LLVM

import Amy.AST
import Amy.Codegen.Monad
import Amy.Names
import Amy.Type as T

codegenPure :: AST IdName T.Type -> Module
codegenPure (AST declarations) =
  let
    definitions = mapMaybe codegenDeclaration declarations
  in
    defaultModule
    { moduleName = "amy-module"
    , moduleDefinitions = definitions
    }

textToShortBS :: Text -> ShortByteString
textToShortBS = BSS.toShort . encodeUtf8

-- | Convert from a amy primitive type to an LLVM type
llvmPrimitiveType :: PrimitiveType -> LLVM.Type
llvmPrimitiveType IntType = IntegerType 32
llvmPrimitiveType DoubleType = FloatingPointType DoubleFP
llvmPrimitiveType BoolType = IntegerType 1

codegenDeclaration :: TopLevel IdName T.Type -> Maybe Definition
codegenDeclaration (TopLevelBindingValue binding) =
  let
    blocks = runGenBlocks (codegenExpression $ bindingValueBody binding)
    bindingType = bindingValueType binding
    paramTypes = llvmPrimitiveType <$> argTypes bindingType
    params =
      (\(idn, ty) -> Parameter ty (Name . textToShortBS $ idNameRaw idn)  [])
      <$> zip (bindingValueArgs binding) paramTypes
    returnType' = llvmPrimitiveType $ T.returnType bindingType
  in
    Just $
      GlobalDefinition
      functionDefaults
      { name = idNameToLLVM $ bindingValueName binding
      , parameters = (params, False)
      , LLVM.returnType = returnType'
      , basicBlocks = blocks
      }
codegenDeclaration (TopLevelExternType extern) =
  let
    -- TODO: It sucks that we have to interpret these types again
    bindingTypes :: NonEmpty PrimitiveType
    bindingTypes =
      (\mType -> fromMaybe (error $ "Panic! Unknown type " ++ unpack mType) $ readPrimitiveType mType)
      <$> bindingTypeTypeNames extern

    paramTypes = llvmPrimitiveType <$> NE.init bindingTypes
    params =
      (\ty -> Parameter ty (UnName 0) []) <$> paramTypes
    returnType' = llvmPrimitiveType $ NE.last bindingTypes
  in
    Just $
      GlobalDefinition
      functionDefaults
      { name = idNameToLLVM $ bindingTypeName extern
      , parameters = (params, False)
      , LLVM.returnType = returnType'
      }
codegenDeclaration (TopLevelBindingType _) = Nothing

idNameToLLVM :: IdName -> Name
idNameToLLVM (IdName name' _ _) = Name $ textToShortBS name'

codegenExpression :: Expression IdName T.Type -> FunctionGen Operand
codegenExpression (ExpressionLiteral lit) =
  pure $ ConstantOperand $
    case lit of
      LiteralInt i -> C.Int 32 (fromIntegral i)
      LiteralDouble x -> C.Float (F.Double x)
      LiteralBool x -> C.Int 1 $ if x then 1 else 0
codegenExpression (ExpressionVariable (Variable idn ty)) =
  -- We need to use the IdName's provenance to determine whether or not to use
  -- a local reference to a variable or a function call with no arguments.
  case idNameProvenance idn of
    LocalDefinition -> do
      -- First check the symbol table
      mOp <- lookupSymbol idn

      pure $
        fromMaybe
        -- Must not be in symbol table, assume the name is in scope
        (LocalReference (llvmPrimitiveType $ assertPrimitiveType ty) (idNameToLLVM idn))
        mOp
    TopLevelDefinition -> functionCallInstruction idn [] [] (T.returnType ty)
codegenExpression (ExpressionIf (If predicate thenExpression elseExpression ty)) = do
  let
    one = ConstantOperand $ C.Int 32 1
    --zero = ConstantOperand $ C.Int 32 0
    true = one
    --false = zero

  -- Generate unique block names
  uniqueId <- currentId
  let
    thenBlockName = Name $ BSS.toShort $ BS8.pack $ "if.then." ++ show uniqueId
    elseBlockName = Name $ BSS.toShort $ BS8.pack $ "if.else." ++ show uniqueId
    endBlockName = Name $ BSS.toShort $ BS8.pack $ "if.end." ++ show uniqueId

  -- Generate code for the predicate
  predicateOp <- codegenExpression predicate
  test <- instr (llvmPrimitiveType BoolType) $ ICmp IP.EQ true predicateOp []
  cbr test thenBlockName elseBlockName

  -- Generate code for the "then" block
  startNewBlock thenBlockName
  thenOp <- codegenExpression thenExpression
  br endBlockName

  -- Generate code for the "else" block
  startNewBlock elseBlockName
  elseOp <- codegenExpression elseExpression
  br endBlockName

  -- Generate the code for the ending block
  startNewBlock endBlockName
  phi (llvmPrimitiveType $ assertPrimitiveType ty) [(thenOp, thenBlockName), (elseOp, elseBlockName)]
codegenExpression (ExpressionLet (Let bindings expression _)) = do
  -- For each binding value, generate code for the expression
  let bindingValues = mapMaybe letBindingValue bindings
  forM_ bindingValues $ \bindingValue -> do
    -- Generate code for binding expression
    bodyOp <- codegenExpression $ bindingValueBody bindingValue

    -- Add operator to symbol table for binding variable name
    addNameToSymbolTable (bindingValueName bindingValue) bodyOp

  -- Codegen the let expression
  codegenExpression expression
codegenExpression (ExpressionFunctionApplication app) = do
  fnName <-
    case functionApplicationFunction app of
      ExpressionVariable var -> pure $ variableName var
      _ -> error $ "Expected function to be variable (no currying yet). Got " ++ show app
  let
    fnArgs = functionApplicationArgs app
    fnArgTypes = toList $ assertPrimitiveType . expressionType <$> fnArgs
  argOps <- mapM codegenExpression fnArgs
  functionCallInstruction fnName (toList argOps) fnArgTypes (assertPrimitiveType $ functionApplicationReturnType app)
codegenExpression (ExpressionParens expression) = codegenExpression expression

functionCallInstruction
  :: IdName
  -> [Operand]
  -> [PrimitiveType]
  -> PrimitiveType
  -> FunctionGen Operand
functionCallInstruction idName argumentOperands argumentTypes' returnType' = do
  let
    argTypes' = llvmPrimitiveType <$> argumentTypes'
    fnRef =
      ConstantOperand $
      C.GlobalReference
      (PointerType (LLVM.FunctionType (llvmPrimitiveType returnType') argTypes' False) (AddrSpace 0))
      (idNameToLLVM idName)
    toArg arg = (arg, [])
    instruction = Call Nothing CC.C [] (Right fnRef) (toArg <$> argumentOperands) [] []

  instr (llvmPrimitiveType returnType') instruction

-- TODO: This function shouldn't be necessary. The AST that feeds into Codegen
-- should have things that are primitive types statically declared.
assertPrimitiveType :: T.Type -> PrimitiveType
assertPrimitiveType t =
  fromMaybe (error $ "Panic! Expected PrimitiveType, got " ++ show t) $ primitiveType t
