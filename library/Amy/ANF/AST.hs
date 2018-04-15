module Amy.ANF.AST
  ( ANFVal(..)
  , ANFExpr(..)
  , ANFLet(..)
  , ANFBinding(..)
  , ANFIf(..)
  , ANFApp(..)
  ) where

import Amy.Literal
import Amy.Names
import Amy.Prim
import Amy.Type

data ANFVal
  = ANFVar !(Typed PrimitiveType Name)
  | ANFLit !Literal
  | ANFPrim !PrimitiveFunctionName
  deriving (Show, Eq)

data ANFExpr
  = ANFEVal !ANFVal
  | ANFELet !ANFLet
  | ANFEIf !ANFIf
  | ANFEApp !ANFApp
  deriving (Show, Eq)

data ANFLet
  = ANFLet
  { anfLetBindings :: ![ANFBinding]
  , anfLetExpression :: !ANFExpr
  } deriving (Show, Eq)

data ANFBinding
  = ANFBinding
  { anfBindingName :: !Name
  , anfBindingType :: !(Scheme PrimitiveType)
  , anfBindingArgs :: ![Typed PrimitiveType Name]
  , anfBindingReturnType :: !(Type PrimitiveType)
  , anfBindingBody :: !ANFExpr
  } deriving (Show, Eq)

data ANFIf
  = ANFIf
  { anfIfPredicate :: !ANFVal
  , anfIfThen :: !ANFExpr
  , anfIfElse :: !ANFExpr
  } deriving (Show, Eq)

data ANFApp
  = ANFApp
  { anfAppFunction :: !ANFVal
  , anfAppArgs :: ![ANFVal]
  , anfAppReturnType :: !(Type PrimitiveType)
  } deriving (Show, Eq)