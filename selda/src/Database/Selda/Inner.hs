{-# LANGUAGE TypeOperators, TypeFamilies, FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE CPP, DataKinds, UndecidableInstances #-}
-- | Helpers for working with inner queries.
module Database.Selda.Inner where
import Database.Selda.Column
import Database.Selda.SQL (SQL)
import Database.Selda.Types
import Data.Text (Text)
import Data.Typeable
import GHC.Exts
import GHC.TypeLits as TL

-- | A single aggregate column.
--   Aggregate columns may not be used to restrict queries.
--   When returned from an 'aggregate' subquery, an aggregate column is
--   converted into a non-aggregate column.
newtype Aggr s a = Aggr {unAggr :: Exp SQL a}

-- | Denotes an inner query.
--   For aggregation, treating sequencing as the cartesian product of queries
--   does not work well.
--   Instead, we treat the sequencing of 'aggregate' with other
--   queries as the cartesian product of the aggregated result of the query,
--   a small but important difference.
--
--   However, for this to work, the aggregate query must not depend on any
--   columns in the outer product. Therefore, we let the aggregate query be
--   parameterized over @Inner s@ if the parent query is parameterized over @s@,
--   to enforce this separation.
data Inner s
  deriving Typeable

-- | Create a named aggregate function.
--   Like 'fun', this function is generally unsafe and should ONLY be used
--   to implement missing backend-specific functionality.
aggr :: Text -> Col s a -> Aggr s b
aggr f = Aggr . AggrEx f . unC

-- | Convert one or more inner column to equivalent columns in the outer query.
--   @OuterCols (Aggr (Inner s) a :*: Aggr (Inner s) b) = Col s a :*: Col s b@,
--   for instance.
type family OuterCols a where
  OuterCols (Col (Inner s) a :*: b)  = Col s a :*: OuterCols b
  OuterCols (Col (Inner s) a)        = Col s a
#if MIN_VERSION_base(4, 9, 0)
  OuterCols a = TypeError
    ( TL.Text "Only (inductive tuples of) columns can be returned from" :$$:
      TL.Text "an inner query."
    )
#endif

type family AggrCols a where
  AggrCols (Aggr (Inner s) a :*: b) = Col s a :*: AggrCols b
  AggrCols (Aggr (Inner s) a)       = Col s a
#if MIN_VERSION_base(4, 9, 0)
  AggrCols a = TypeError
    ( TL.Text "Only (inductive tuples of) aggregates can be returned from" :$$:
      TL.Text "an aggregate query."
    )
#endif


-- | The results of a left join are always nullable, as there is no guarantee
--   that all joined columns will be non-null.
--   @JoinCols a@ where @a@ is an extensible tuple is that same tuple, but in
--   the outer query and with all elements nullable.
--   For instance:
--
-- >  LeftCols (Col (Inner s) Int :*: Col (Inner s) Text)
-- >    = Col s (Maybe Int) :*: Col s (Maybe Text)
type family LeftCols a where
  LeftCols (Col (Inner s) (Maybe a) :*: b) = Col s (Maybe a) :*: LeftCols b
  LeftCols (Col (Inner s) a :*: b)         = Col s (Maybe a) :*: LeftCols b
  LeftCols (Col (Inner s) (Maybe a))       = Col s (Maybe a)
  LeftCols (Col (Inner s) a)               = Col s (Maybe a)
#if MIN_VERSION_base(4, 9, 0)
  LeftCols a = TypeError
    ( TL.Text "Only (inductive tuples of) columns can be returned" :$$:
      TL.Text "from a join."
    )
#endif

-- | One or more aggregate columns.
class Aggregates a where
  unAggrs :: a -> [SomeCol SQL]
instance Aggregates (Aggr (Inner s) a) where
  unAggrs (Aggr x) = [Some x]
instance Aggregates b => Aggregates (Aggr (Inner s) a :*: b) where
  unAggrs (Aggr a :*: b) = Some a : unAggrs b
