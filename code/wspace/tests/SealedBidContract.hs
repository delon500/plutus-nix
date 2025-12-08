{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}

module SealedBidContract
  ( CommitDatum(..)
  , AuctionRedeemer(..)
  , bidHash
  , validator
  , mkValidatorUntyped
  ) where

import Plutus.V2.Ledger.Api
import Plutus.V2.Ledger.Contexts
import Plutus.V1.Ledger.Interval as Interval
import Plutus.V1.Ledger.Value (valueOf, adaSymbol, adaToken)
import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins

------------------------------------------------------------------------
-- Datum and Redeemer
------------------------------------------------------------------------

data CommitDatum = CommitDatum
    { cdBidder         :: PubKeyHash
    , cdSeller         :: PubKeyHash
    , cdCommitHash     :: BuiltinByteString
    , cdDeadlineReveal :: POSIXTime
    , cdCurrency       :: CurrencySymbol
    , cdToken          :: TokenName
    }
PlutusTx.unstableMakeIsData ''CommitDatum

data AuctionRedeemer
    = Reveal Integer BuiltinByteString
    | Refund
PlutusTx.unstableMakeIsData ''AuctionRedeemer

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

{-# INLINABLE bidHash #-}
bidHash :: Integer -> BuiltinByteString -> BuiltinByteString
bidHash amount salt =
    Builtins.sha2_256 $
      Builtins.serialiseData (PlutusTx.toBuiltinData (amount, salt))

{-# INLINABLE ownInput #-}
ownInput :: ScriptContext -> TxOut
ownInput ctx =
    case findOwnInput ctx of
        Nothing -> traceError "own input missing"
        Just i  -> txInInfoResolved i

{-# INLINABLE inputAda #-}
inputAda :: ScriptContext -> Integer
inputAda ctx =
    let v = txOutValue (ownInput ctx)
    in valueOf v adaSymbol adaToken

------------------------------------------------------------------------
-- Validator Logic
------------------------------------------------------------------------

{-# INLINABLE mkValidator #-}
mkValidator :: CommitDatum -> AuctionRedeemer -> ScriptContext -> Bool

-- Reveal branch
mkValidator dat (Reveal amount salt) ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "reveal too late"           beforeDeadline
    && traceIfFalse "commitment mismatch"       commitMatches
    && traceIfFalse "seller not paid"           sellerPaid
    && traceIfFalse "bidder not receive NFT"    bidderGetsNFT
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    txRange :: POSIXTimeRange
    txRange = txInfoValidRange info

    bidder :: PubKeyHash
    bidder = cdBidder dat

    seller :: PubKeyHash
    seller = cdSeller dat

    bidderSigned :: Bool
    bidderSigned = txSignedBy info bidder

    beforeDeadline :: Bool
    beforeDeadline =
      Interval.contains (Interval.to (cdDeadlineReveal dat)) txRange

    commitMatches :: Bool
    commitMatches =
      cdCommitHash dat == bidHash amount salt

    sellerPaid :: Bool
    sellerPaid =
      let v = valuePaidTo info seller
      in valueOf v adaSymbol adaToken >= amount

    bidderGetsNFT :: Bool
    bidderGetsNFT =
      let v = valuePaidTo info bidder
      in valueOf v (cdCurrency dat) (cdToken dat) >= 1


-- Refund branch
mkValidator dat Refund ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "too early for refund"       afterDeadline
    && traceIfFalse "refund not paid to bidder"  refundPaid
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    txRange :: POSIXTimeRange
    txRange = txInfoValidRange info

    bidder :: PubKeyHash
    bidder = cdBidder dat

    bidderSigned :: Bool
    bidderSigned = txSignedBy info bidder

    afterDeadline :: Bool
    afterDeadline =
      Interval.contains (Interval.from (cdDeadlineReveal dat + 1)) txRange

    refundPaid :: Bool
    refundPaid =
      let paidToBidder = valuePaidTo info bidder
      in valueOf paidToBidder adaSymbol adaToken
           >= inputAda ctx

------------------------------------------------------------------------
-- Boilerplate
------------------------------------------------------------------------

{-# INLINABLE mkValidatorUntyped #-}
mkValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkValidatorUntyped d r c =
    let dat = unsafeFromBuiltinData @CommitDatum     d
        red = unsafeFromBuiltinData @AuctionRedeemer r
        ctx = unsafeFromBuiltinData @ScriptContext   c
    in if mkValidator dat red ctx then () else error ()

validator :: Validator
validator = mkValidatorScript $$(PlutusTx.compile [|| mkValidatorUntyped ||])
