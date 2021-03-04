{-# LANGUAGE FlexibleContexts #-}

module Echidna.Mutator.Corpus where

import Control.Monad.Random.Strict (MonadRandom, getRandomR, weighted)
import Control.Monad.State.Strict (MonadState(..))
import Data.Has (Has(..))

import qualified Data.Set as DS

import Echidna.Types.Tx (Tx)
import Echidna.Types.Corpus
import Echidna.Transaction (mutateTx, shrinkTx)
import Echidna.ABI (GenDict)
import Echidna.Mutator.Array

type MutationConsts a = (a, a, a, a)
defaultMutationConsts :: Num a => MutationConsts a
defaultMutationConsts = (1, 1, 1, 1)

fromConsts :: Num a => MutationConsts Integer -> MutationConsts a
fromConsts (a, b, c, d) = let fi = fromInteger in (fi a, fi b, fi c, fi d)

data TxsMutation = Shrinking
                 | Mutation
                 | Expansion
                 | Swapping
                 | Deletion
  deriving (Eq, Ord, Show)

data CorpusMutation = Skip
                    | RandomAppend TxsMutation
                    | RandomPrepend TxsMutation
                    | RandomSplice
                    | RandomInterleave
  deriving (Eq, Ord, Show)

mutator :: MonadRandom m => TxsMutation -> [Tx] -> m [Tx]
mutator Shrinking = mapM shrinkTx
mutator Mutation = mapM mutateTx
mutator Expansion = expandRandList
mutator Swapping = swapRandList
mutator Deletion = deleteRandList

selectAndMutate :: MonadRandom m
                => ([Tx] -> m [Tx]) -> Corpus -> m [Tx]
selectAndMutate f ctxs = do
  rtxs <- weighted $ map (\(i, txs) -> (txs, fromInteger i)) $ DS.toDescList ctxs
  k <- getRandomR (0, length rtxs - 1)
  f $ take k rtxs

selectAndCombine :: MonadRandom m
                 => ([Tx] -> [Tx] -> m [Tx]) -> Int -> Corpus -> [Tx] -> m [Tx]
selectAndCombine f ql ctxs gtxs = do
  rtxs1 <- selectFromCorpus
  rtxs2 <- selectFromCorpus
  txs <- f rtxs1 rtxs2
  return . take ql $ txs ++ gtxs
    where selectFromCorpus = weighted $ map (\(i, txs) -> (txs, fromInteger i)) $ DS.toDescList ctxs

getCorpusMutation :: (MonadRandom m, Has GenDict x, MonadState x m)
                  => CorpusMutation -> (Int -> Corpus -> [Tx] -> m [Tx])
getCorpusMutation Skip = \_ _ -> return
getCorpusMutation (RandomAppend m) = mut (mutator m)
 where mut f ql ctxs gtxs = do
          rtxs' <- selectAndMutate f ctxs
          return . take ql $ rtxs' ++ gtxs
getCorpusMutation (RandomPrepend m) = mut (mutator m)
 where mut f ql ctxs gtxs = do
          rtxs' <- selectAndMutate f ctxs
          k <- getRandomR (0, ql - 1)
          return . take ql $ take k gtxs ++ rtxs'
getCorpusMutation RandomSplice = selectAndCombine spliceAtRandom
getCorpusMutation RandomInterleave = selectAndCombine interleaveAtRandom

seqMutators :: MonadRandom m => MutationConsts Rational -> m CorpusMutation
seqMutators (c1, c2, c3, c4) = weighted
  [(Skip,                    1000),

   (RandomAppend Shrinking,  c1),
   (RandomAppend Mutation,   c2),
   (RandomAppend Expansion,  c3),
   (RandomAppend Swapping,   c3),
   (RandomAppend Deletion,   c3),

   (RandomPrepend Shrinking, c1),
   (RandomPrepend Mutation,  c2),
   (RandomPrepend Expansion, c3),
   (RandomPrepend Swapping,  c3),
   (RandomPrepend Deletion,  c3),

   (RandomSplice,            c4),
   (RandomInterleave,        c4)
 ]
