module Eval
  ( evalMany
  , evalOne
  ) where

import Prelude

import Control.Monad.Error.Class (class MonadError, class MonadThrow, throwError)
import Control.Monad.Except.Trans (ExceptT, runExceptT, mapExceptT)
import Control.Monad.Rec.Class (class MonadRec)
import Control.Monad.State as S
import Control.Monad.State.Trans (StateT, runStateT, withStateT)
import Control.Monad.State.Class (class MonadState)
import Core
  ( Ann
  , Env
  , ErrTipe(..)
  , Expr(..)
  , ExprAnn(..)
  , ExprTipe(..)
  , Eval
  , EvalErr(..)
  , EvalState(..)
  , EvalT(..)
  , Result
  , SFrm(..)
  , SrcSpan
  , isTrue
  , getEnv
  , mkFalse
  , mkTrue
  , runEval
  , sfrmNumArgs
  , throw
  , toExprTipe
  , updateEnv
  )
import Data.Either (Either)
import Data.Foldable (all, length)
import Data.Identity (Identity)
import Data.List as L
import Data.Map as M
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Traversable (sequence, traverse)
import Data.Tuple (Tuple(..))

numArgsErr :: Int -> Int -> ErrTipe
numArgsErr expected received = NumArgs { expected, received }

throwNumArgsErr
  :: forall m e a
   . Monad m
  => Ann
  -> Int
  -> Int
  -> EvalT m e a
throwNumArgsErr ann expected received =
  throw ann $ numArgsErr expected received

throwSFrmNumArgsErr
  :: forall m e a
   . Monad m
  => Ann
  -> SFrm
  -> Args
  -> EvalT m e a
throwSFrmNumArgsErr ann sfrm args = throwNumArgsErr ann expected received
  where expected = sfrmNumArgs sfrm
        received = length args

wrongTipeErr :: ExprTipe -> ExprTipe -> ErrTipe
wrongTipeErr expected received = WrongTipe { expected, received }

throwWrongTipeErr
  :: forall m e a
   . Monad m
  => Ann
  -> ExprTipe
  -> ExprTipe
  -> EvalT m e a
throwWrongTipeErr ann expected received =
  throw ann $ wrongTipeErr expected received

lstLengthErr :: Int -> Int -> ErrTipe
lstLengthErr expected received = LstLength { expected, received }

throwLstLengthErr
  :: forall m e a
   . Monad m
  => Ann
  -> Int
  -> Int
  -> EvalT m e a
throwLstLengthErr ann expected received =
  throw ann $ lstLengthErr expected received

unknownVarErr :: String -> ErrTipe
unknownVarErr varName = UnknownVar { varName }

throwUnknownVarErr
  :: forall m e a
   . Monad m
  => Ann
  -> String
  -> EvalT m e a
throwUnknownVarErr ann varName =
  throw ann $ unknownVarErr varName

unknownErr :: ErrTipe
unknownErr = UnknownErr

throwUnknownErr
  :: forall m e a
   . Monad m
  => Ann
  -> EvalT m e a
throwUnknownErr ann = throw ann unknownErr

emptyFnApplicationErr :: ErrTipe
emptyFnApplicationErr = EmptyFnApplication

throwEmptyFnApplicationErr
  :: forall m e a
   . Monad m
  => Ann
  -> EvalT m e a
throwEmptyFnApplicationErr ann = throw ann emptyFnApplicationErr

trueCondClauseNotFound :: ErrTipe
trueCondClauseNotFound = TrueCondClauseNotFound

throwTrueCondClauseNotFound
  :: forall m e a
   . Monad m
  => Ann
  -> EvalT m e a
throwTrueCondClauseNotFound ann = throw ann trueCondClauseNotFound

evalMany :: Env -> L.List ExprAnn -> Identity (Result (L.List ExprAnn))
evalMany env = runEval env <<< sequence <<< map eval

evalOne :: Env -> ExprAnn -> Identity (Result ExprAnn)
evalOne env = runEval env <<< eval


eval :: ExprAnn -> Eval ExprAnn
eval exprAnn@(ExprAnn expr ann) =
  case expr of
    (Sym name) ->
      evalSym ann name
    (Lst (L.Cons (ExprAnn (SFrm sfrm) _) args)) ->
      evalSFrm ann sfrm args
    (Lst xs) ->
      evalLst ann xs
    (Float _) ->
      pure $ exprAnn
    (Integer _) ->
      pure $ exprAnn
    _ ->
      throwUnknownErr ann

evalSym :: Ann -> String -> Eval ExprAnn
evalSym ann name = do
  env <- getEnv
  case M.lookup name env of
    Just expr ->
      pure expr
    Nothing ->
      throwUnknownVarErr ann name

type Args = L.List ExprAnn

evalSFrm :: Ann -> SFrm -> Args -> Eval ExprAnn
evalSFrm ann sfrm L.Nil = throwSFrmNumArgsErr ann sfrm L.Nil
evalSFrm ann Conz args = evalConz ann args
evalSFrm ann Def args = evalDef ann args
evalSFrm ann Do args = evalDo ann args
evalSFrm ann Car args = evalCar ann args
evalSFrm ann If args = evalIf ann args
evalSFrm ann IsAtm args = evalIsAtm ann args
evalSFrm ann IsEq args = evalIsEq ann args
evalSFrm ann Lambda args = evalLambda ann args
evalSFrm ann Quote args = evalQuote ann args
evalSFrm ann Cdr args = evalCdr ann args
evalSFrm ann Cond args = evalCond ann args

evalConz :: Ann -> Args -> Eval ExprAnn
evalConz ann (L.Cons e1 (L.Cons e2 L.Nil)) = do
  h <- eval e1
  t <- eval e2
  case t of
    (ExprAnn (Lst t') _) ->
      pure $ ExprAnn (Lst (L.Cons h t')) ann
    _ ->
      throwWrongTipeErr ann LstTipe (toExprTipe t)
evalConz ann args = throwSFrmNumArgsErr ann Conz args

evalDef :: Ann -> Args -> Eval ExprAnn
evalDef ann (L.Cons e1 (L.Cons e2 L.Nil)) = do
  val <- eval e2
  case e1 of
    ExprAnn (Sym name) _ -> do
      _ <- updateEnv name val
      pure val
    _ ->
      throwWrongTipeErr ann SymTipe (toExprTipe e1)
evalDef ann args = throwSFrmNumArgsErr ann Def args

evalCar :: Ann -> Args -> Eval ExprAnn
evalCar ann (L.Cons e L.Nil) = do
  expr@(ExprAnn xs _) <- eval e
  case xs of
    Lst L.Nil ->
      throwLstLengthErr ann 1 0
    Lst (L.Cons h _) ->
      pure h
    _ ->
      throwWrongTipeErr ann LstTipe (toExprTipe expr)
evalCar ann args = throwSFrmNumArgsErr ann Car args

evalDo :: Ann -> Args -> Eval ExprAnn
evalDo ann args = do
  results <- traverse eval args
  case L.last results of
    Nothing ->
      throwSFrmNumArgsErr ann Do L.Nil
    Just e ->
      pure e

evalIf :: Ann -> Args -> Eval ExprAnn
evalIf ann (L.Cons p (L.Cons e1 (L.Cons e2 L.Nil))) = do
  p' <- eval p
  if isTrue p'
  then eval e1
  else eval e2
evalIf ann args = throwSFrmNumArgsErr ann If args

evalIsAtm :: Ann -> Args -> Eval ExprAnn
evalIsAtm ann (L.Cons e L.Nil) = do
  ExprAnn x _ <- eval e
  case x of
    Float _ ->
      pure t
    Integer _ ->
      pure t
    Sym _ ->
      pure t
    _ ->
      pure f
  where
    t = mkTrue ann
    f = mkFalse ann
evalIsAtm ann args = throwSFrmNumArgsErr ann IsAtm args

evalIsEq :: Ann -> Args -> Eval ExprAnn
evalIsEq ann (L.Cons e1 (L.Cons e2 L.Nil)) = do
  ExprAnn x _ <- eval e1
  ExprAnn y _ <- eval e2
  evalIsEqExpr x y
  where
    t = mkTrue ann
    f = mkFalse ann
    evalIsEqExpr :: Expr -> Expr -> Eval ExprAnn
    evalIsEqExpr x y = do
      case Tuple x y of
        Tuple (Float n1) (Float n2) ->
          if n1 == n2
          then pure t
          else pure f
        Tuple (Integer n1) (Integer n2) ->
          if n1 == n2
          then pure t
          else pure f
        Tuple (Sym name1) (Sym name2) ->
          if name1 == name2
          then pure t
          else pure f
        Tuple (Lst L.Nil) (Lst L.Nil) ->
          pure t
        Tuple (Lst xs) (Lst ys) ->
          evalIsEqLst xs ys
        _ ->
          pure f
    evalIsEqLst :: L.List ExprAnn -> L.List ExprAnn -> Eval ExprAnn
    evalIsEqLst xs ys = do
      equalities <- traverse evalIsEqExprPair (L.zip xs ys)
      let isNotEmpty = not $ L.null equalities
      let isAllEqual = all isTrue equalities
      if isNotEmpty && isAllEqual
      then pure t
      else pure f
    evalIsEqExprPair :: Tuple ExprAnn ExprAnn -> Eval ExprAnn
    evalIsEqExprPair (Tuple (ExprAnn x _) (ExprAnn y _)) = evalIsEqExpr x y
evalIsEq ann args = throwSFrmNumArgsErr ann IsEq args

evalLambda :: Ann -> Args -> Eval ExprAnn
evalLambda ann (L.Cons params (L.Cons body L.Nil)) = do
  case params of
    ExprAnn (Lst params') _ -> do
      env <- getEnv
      pure $ ExprAnn (Fn env params' body) ann
    _ ->
      throwWrongTipeErr ann LstTipe (toExprTipe params)
evalLambda ann args = throwSFrmNumArgsErr ann Lambda args

evalQuote :: Ann -> Args -> Eval ExprAnn
evalQuote ann (L.Cons expr L.Nil) = pure $ expr
evalQuote ann args = throwSFrmNumArgsErr ann Quote args

evalCdr :: Ann -> Args -> Eval ExprAnn
evalCdr ann (L.Cons e L.Nil) = do
  xs'@(ExprAnn xs _) <- eval e
  case xs of
    Lst L.Nil ->
      pure $ ExprAnn (Lst L.Nil) ann
    Lst (L.Cons _ t) ->
      pure $ ExprAnn (Lst t) ann
    _ -> throwWrongTipeErr ann LstTipe (toExprTipe xs')
evalCdr ann args = throwSFrmNumArgsErr ann Cdr args

evalCond :: Ann -> Args -> Eval ExprAnn
evalCond ann L.Nil = throwSFrmNumArgsErr ann Cond L.Nil
evalCond ann clauses = go clauses
  where
    go :: Args -> Eval ExprAnn
    go (L.Cons (ExprAnn (Lst (L.Cons predicate (L.Cons consequent L.Nil))) _) rest) = do
      p <- isTrue <$> eval predicate
      if p
      then eval consequent
      else go rest
    go (L.Cons (ExprAnn (Lst xs) clauseAnn) _) = throwLstLengthErr clauseAnn 2 (length xs)
    go (L.Cons expr _) = throwWrongTipeErr ann LstTipe (toExprTipe expr)
    go L.Nil = throwTrueCondClauseNotFound ann

evalLst :: Ann -> Args -> Eval ExprAnn
evalLst ann (L.Cons x xs) = do
  expr@(ExprAnn fn _) <- eval x
  args <- traverse eval xs
  case fn of
    Fn localEnv params body -> do
      applyLambda ann localEnv params args body
    _ ->
      throwWrongTipeErr ann FnTipe (toExprTipe expr)
evalLst ann L.Nil = throwEmptyFnApplicationErr ann

applyLambda :: Ann -> Env -> L.List ExprAnn -> L.List ExprAnn -> ExprAnn -> Eval ExprAnn
applyLambda ann localEnv params args body = do
  env <- bindArgs ann localEnv params args
  let evalState = EvalState { env: env }
  EvalT $ mapExceptT (withStateT $ const evalState) (unwrap $ eval body)

bindArgs :: Ann -> Env -> L.List ExprAnn -> L.List ExprAnn -> Eval Env
bindArgs ann localEnv params args = do
  env <- getEnv
  bindings <- sequence (L.zipWith toBinding params args)
  pure $ M.fromFoldable bindings <> localEnv <> env
  where
    toBinding :: ExprAnn -> ExprAnn -> Eval (Tuple String ExprAnn)
    toBinding param arg = do
      paramName <- toParamName param
      pure $ Tuple paramName arg

    toParamName :: ExprAnn -> Eval String
    toParamName expr@(ExprAnn param _) =
      case param of
        Sym name ->
          pure name
        _ ->
          throwWrongTipeErr ann SymTipe (toExprTipe expr)
