{-# LANGUAGE OverloadedStrings #-}

module Amy.ANF.Convert
  ( normalizeModule
  ) where

import Data.Foldable (toList)
import Data.Maybe (mapMaybe)

import Amy.ANF.AST
import Amy.ANF.Monad
import Amy.Names
import Amy.Type
import Amy.TypeCheck.AST

normalizeModule :: TModule -> [ANFBinding]
normalizeModule module' =
  let
    moduleNames = tModuleNames module'
    moduleIdentIds = identId <$> mapMaybe identName moduleNames
    maxId =
      if null moduleIdentIds
      then 0
      else maximum moduleIdentIds
  in runANFConvert (maxId + 1) $ traverse normalizeTopLevelBinding (tModuleBindings module')

normalizeTopLevelBinding :: TBinding -> ANFConvert ANFBinding
normalizeTopLevelBinding (TBinding name ty args retTy body) = do
  body' <- normalizeTerm body
  pure $ ANFBinding name ty args retTy body'

normalizeExpr :: TExpr -> (ANFExpr -> ANFConvert ANFExpr) -> ANFConvert ANFExpr
normalizeExpr (TELit lit) c = c $ ANFEVal $ ANFLit lit
normalizeExpr (TEVar var) c = c $ ANFEVal $ ANFVar var
normalizeExpr (TEIf (TIf pred' then' else')) c =
  normalizeName pred' $ \predVal -> do
    then'' <- normalizeTerm then'
    else'' <- normalizeTerm else'
    c $ ANFEIf $ ANFIf predVal then'' else''
normalizeExpr (TELet (TLet bindings expr)) c =
  normalizeList normalizeBinding bindings $ \bindings' -> do
    expr' <- normalizeExpr expr c
    pure $ ANFELet $ ANFLet bindings' expr'
normalizeExpr (TEApp (TApp func args retTy)) c =
  normalizeList normalizeName (toList args) $ \argVals ->
  let mkApp funcVal = c $ ANFEApp $ ANFApp funcVal argVals retTy
  in
    case func of
      (TEVar (Typed _ (PrimitiveName prim))) -> mkApp (ANFPrim prim)
      _ -> normalizeName func mkApp

normalizeTerm :: TExpr -> ANFConvert ANFExpr
normalizeTerm expr = normalizeExpr expr pure

normalizeName :: TExpr -> (ANFVal -> ANFConvert ANFExpr) -> ANFConvert ANFExpr
normalizeName (TELit lit) c = c $ ANFLit lit
normalizeName (TEVar var) c = c $ ANFVar var
normalizeName expr c = do
  expr' <- normalizeTerm expr
  let exprType = expressionType expr
  newName <- IdentName <$> freshIdent "t"
  body <- c $ ANFVar (Typed exprType newName)
  pure $ ANFELet $ ANFLet [ANFBinding newName (Forall [] exprType) [] exprType expr'] body

normalizeBinding :: TBinding -> (ANFBinding -> ANFConvert ANFExpr) -> ANFConvert ANFExpr
normalizeBinding (TBinding name ty args retTy body) c = do
  body' <- normalizeTerm body
  c $ ANFBinding name ty args retTy body'

-- | Helper for normalizing lists of things
normalizeList :: (Monad m) => (a -> (b -> m c) -> m c) -> [a] -> ([b] -> m c) -> m c
normalizeList _ [] c = c []
normalizeList norm (x:xs) c =
  norm x $ \v -> normalizeList norm xs $ \vs -> c (v:vs)