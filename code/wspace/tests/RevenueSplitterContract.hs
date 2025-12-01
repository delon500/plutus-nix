{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}

module RevenueSplitterContract
  ( RevenueDatum(..)
  , RevenueRedeemer(..)
  , mkRevenueValidator
  , mkRevenueValidatorUntyped
  , validator
  ) where

import Plutus.V2.Ledger.Api
  ( Validator
  , ScriptContext(..)
  , TxInfo(..)
  , TxOut(..)
  , TxInInfo(..)
  , BuiltinData
  , PubKeyHash
  , Value
  , mkValidatorScript          -- 👈 this was missing
  )
import Plutus.V2.Ledger.Contexts
  ( scriptContextTxInfo
  , findOwnInput
  , valuePaidTo
  )
import Plutus.V1.Ledger.Value
  ( valueOf
  , adaSymbol
  , adaToken
  )

import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)

----------------------------------------------------------------------
-- Datum & Redeemer
----------------------------------------------------------------------

-- | Datum describing how revenue for a given event should be split.
data RevenueDatum = RevenueDatum
  { rdEventId    :: BuiltinByteString          -- ^ Event identifier
  , rdRecipients :: [(PubKeyHash, Integer)]    -- ^ (recipient, share in lovelace)
  }
PlutusTx.unstableMakeIsData ''RevenueDatum

data RevenueRedeemer = Distribute
PlutusTx.unstableMakeIsData ''RevenueRedeemer

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{-# INLINABLE info #-}
info :: ScriptContext -> TxInfo
info = scriptContextTxInfo

{-# INLINABLE ownInput #-}
ownInput :: ScriptContext -> TxOut
ownInput ctx =
  case findOwnInput ctx of
    Nothing -> traceError "own input not found"
    Just i  -> txInInfoResolved i

{-# INLINABLE inputAda #-}
inputAda :: ScriptContext -> Integer
inputAda ctx =
  let v :: Value
      v = txOutValue (ownInput ctx)
  in valueOf v adaSymbol adaToken

----------------------------------------------------------------------
-- Validator
----------------------------------------------------------------------

{-# INLINABLE mkRevenueValidator #-}
mkRevenueValidator :: RevenueDatum -> RevenueRedeemer -> ScriptContext -> Bool
mkRevenueValidator dat _ ctx =
       traceIfFalse "share sum != input ADA" sharesMatchInput
    && traceIfFalse "some recipient underpaid" recipientsPaid
  where
    ti :: TxInfo
    ti = info ctx

    requiredTotal :: Integer
    requiredTotal = sum (fmap snd (rdRecipients dat))

    inputTotal :: Integer
    inputTotal = inputAda ctx

    sharesMatchInput :: Bool
    sharesMatchInput = inputTotal == requiredTotal

    recipientsPaid :: Bool
    recipientsPaid =
      all recipientsOk (rdRecipients dat)

    recipientsOk :: (PubKeyHash, Integer) -> Bool
    recipientsOk (pkh, share) =
      let vPaid = valuePaidTo ti pkh
          ada   = valueOf vPaid adaSymbol adaToken
      in ada >= share

----------------------------------------------------------------------
-- Untyped wrapper & compiled validator
----------------------------------------------------------------------

{-# INLINABLE mkRevenueValidatorUntyped #-}
mkRevenueValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkRevenueValidatorUntyped d r c =
  let dat = unsafeFromBuiltinData @RevenueDatum    d
      red = unsafeFromBuiltinData @RevenueRedeemer r
      ctx = unsafeFromBuiltinData @ScriptContext   c
  in if mkRevenueValidator dat red ctx
        then ()
        else error ()

validator :: Validator
validator =
  mkValidatorScript $$(PlutusTx.compile [|| mkRevenueValidatorUntyped ||])
