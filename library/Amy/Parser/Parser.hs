module Amy.Parser.Parser
  ( parserAST

  , topLevel
  , externType
  , bindingType
  , binding
  , expression
  , expression'
  , expressionParens
  , ifExpression
  , letExpression'
  , literal
  ) where

import qualified Control.Applicative.Combinators.NonEmpty as CNE
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import Data.Void (Void)
import Text.Megaparsec
import qualified Text.Megaparsec.Char.Lexer as L

import Amy.AST
import Amy.Parser.Lexer

type Parser = Parsec Void Text

parserAST :: Parser (AST Text ())
parserAST = AST <$> do
  spaceConsumerNewlines
  noIndent (indentedBlock topLevel) <* eof

topLevel :: Parser (TopLevel Text ())
topLevel =
  (TopLevelExternType <$> externType)
  <|> try (TopLevelBindingType <$> bindingType)
  <|> (TopLevelBindingValue <$> binding)

externType :: Parser (BindingType Text)
externType = do
  extern
  bindingType

bindingType :: Parser (BindingType Text)
bindingType = do
  bindingName <- identifier
  doubleColon
  typeNames <- typeIdentifier `CNE.sepBy1` typeSeparatorArrow
  pure
    BindingType
    { bindingTypeName = bindingName
    , bindingTypeTypeNames = typeNames
    }

binding :: Parser (BindingValue Text ())
binding = do
  startingIndent <- L.indentLevel
  bindingName <- identifier
  args <- many identifier
  equals
  spaceConsumerNewlines
  _ <- L.indentGuard spaceConsumerNewlines GT startingIndent
  expr <- expression
  pure
    BindingValue
    { bindingValueName = bindingName
    , bindingValueArgs = args
    , bindingValueType = ()
    , bindingValueBody = expr
    }

expression :: Parser (Expression Text ())
expression = do
  -- Parse a NonEmpty list of expressions separated by spaces.
  expressions <- lineFold expression'

  pure $
    case expressions of
      -- Just a simple expression
      expr :| [] -> expr
      -- We must have a function application
      f :| args ->
        ExpressionFunctionApplication
        FunctionApplication
        { functionApplicationFunction = f
        , functionApplicationArgs = NE.fromList args
        , functionApplicationReturnType = ()
        }

-- | Parses any expression except function application. This is needed to avoid
-- left recursion. Without this distinction, f a b would be parsed as f (a b)
-- instead of (f a) b.
expression' :: Parser (Expression Text ())
expression' =
  expressionParens
  <|> (ExpressionLiteral <$> literal)
  <|> (ExpressionIf <$> ifExpression)
  <|> (ExpressionLet <$> letExpression')
  <|> (ExpressionVariable <$> variable)

expressionParens :: Parser (Expression Text ())
expressionParens = ExpressionParens <$> between lparen rparen expression

literal :: Parser Literal
literal =
  (either LiteralDouble LiteralInt <$> number)
  <|> (LiteralBool <$> bool)

variable :: Parser (Variable Text ())
variable = do
  name <- identifier
  pure
    Variable
    { variableName = name
    , variableType = ()
    }

ifExpression :: Parser (If Text ())
ifExpression = do
  if'
  predicate <- expression
  then'
  thenExpression <- expression
  else'
  elseExpression <- expression
  pure
    If
    { ifPredicate = predicate
    , ifThen = thenExpression
    , ifElse = elseExpression
    , ifType = ()
    }

letExpression' :: Parser (Let Text ())
letExpression' = do
  letIndentation <- L.indentLevel
  let'
  let
    parser =
      try (LetBindingValue <$> binding)
      <|> (LetBindingType <$> bindingType)
  bindings <- many $ do
    _ <- L.indentGuard spaceConsumerNewlines GT letIndentation
    parser <* spaceConsumerNewlines

  inIndentation <- L.indentLevel
  _ <- do
    -- TODO: What if the "in" and "let" are on the same line?
    _ <- L.indentGuard spaceConsumerNewlines EQ letIndentation
    in'
  expr <- do
    _ <- L.indentGuard spaceConsumerNewlines GT inIndentation
    expression
  pure
    Let
    { letBindings = bindings
    , letExpression = expr
    , letType = ()
    }
