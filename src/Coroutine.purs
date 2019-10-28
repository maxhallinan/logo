module Coroutine where

import Prelude

import Control.Monad (ap)
import Control.Monad.Trans.Class (class MonadTrans)
import Data.Either (Either(..), either)
import Data.Newtype (class Newtype, unwrap)

type Generator i o m = CoroutineT (Yield i o) m

data Yield i o x = Yield o (i -> x)

derive instance functorYield :: Functor (Yield i o)

newtype CoroutineT s m r = CoroutineT (m (Either (s (CoroutineT s m r)) r))

derive instance newtypeCoroutineT :: Newtype (CoroutineT s m r) _

bounce :: forall s m r. CoroutineT s m r -> m (Either (s (CoroutineT s m r)) r)
bounce = unwrap

instance functorCoroutineT :: (Functor s, Functor m) => Functor (CoroutineT s m) where
  map f (CoroutineT x) =
    CoroutineT $ map (either (Left <<< map (map f)) (Right <<< f)) x

instance applyCoroutineT :: (Functor s, Monad m) => Apply (CoroutineT s m) where
  apply = ap

instance applicativeCoroutineT :: (Functor s, Functor m, Monad m) => Applicative (CoroutineT s m) where
  pure = CoroutineT <<< pure <<< pure

instance bindCoroutineT :: (Functor s, Monad m) => Bind (CoroutineT s m) where
  bind (CoroutineT x) f = CoroutineT $ x >>= either (pure <<< Left <<< map (_ `bind` f)) (bounce <<< f)

instance monadCoroutineT :: (Functor s, Monad m) => Monad (CoroutineT s m)

instance monadTransCoroutineT :: MonadTrans (CoroutineT s) where
  lift = CoroutineT <<< liftM1 Right
