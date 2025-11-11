{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}

module AtomicSwapScript
  ( Expectation(..)
  , Payout(..)
  , Flags(..)
  , SwapParams(..)
  , SwapDatum(..)
  , SwapRedeemer(..)
  , defaultSwapParams
  , mkSwapValidator
  ) where

import PlutusTx.Prelude
  ( Bool(..)
  , (==)
  , (&&)
  , not
  , traceIfFalse
  , traceError
  , elem
  , mconcat
  , Maybe(..)
  , BuiltinByteString
  )

import qualified PlutusTx
import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Interval as I
import qualified Plutus.V1.Ledger.Value    as Value

------------------------------------------------------------
-- Local types (same as your current AtomicSwap.hs)
------------------------------------------------------------

data Expectation
  = ExpectExact V2.Value
PlutusTx.unstableMakeIsData ''Expectation
PlutusTx.makeLift ''Expectation

data Payout = Payout
  { pAddress :: V2.Address
  , pValue   :: V2.Value
  }
PlutusTx.unstableMakeIsData ''Payout
PlutusTx.makeLift ''Payout

data Flags = Flags
  { fSingleFill :: Bool
  }
PlutusTx.unstableMakeIsData ''Flags
PlutusTx.makeLift ''Flags

data SwapParams = SwapParams
  { spOperator       :: Maybe V2.Credential
  , spBeaconPolicyId :: Maybe V2.CurrencySymbol
  , spVersionTag     :: BuiltinByteString
  }
PlutusTx.unstableMakeIsData ''SwapParams
PlutusTx.makeLift ''SwapParams

data SwapDatum = SwapDatum
  { sdSeller   :: V2.Credential
  , sdOffer    :: V2.Value
  , sdExpect   :: Expectation
  , sdPayouts  :: [Payout]
  , sdDeadline :: V2.POSIXTime
  , sdFlags    :: Flags
  , sdSwapId   :: Maybe (V2.CurrencySymbol, V2.TokenName)
  }
PlutusTx.unstableMakeIsData ''SwapDatum
PlutusTx.makeLift ''SwapDatum

data SwapRedeemer
  = Cancel
  | Buy
  | ClaimWithPreimage BuiltinByteString
PlutusTx.unstableMakeIsData ''SwapRedeemer
PlutusTx.makeLift ''SwapRedeemer

------------------------------------------------------------
-- Defaults
------------------------------------------------------------
{-# INLINABLE defaultSwapParams #-}
defaultSwapParams :: SwapParams
defaultSwapParams = SwapParams
  { spOperator       = Nothing
  , spBeaconPolicyId = Nothing
  , spVersionTag     = "v1"
  }

------------------------------------------------------------
-- Time checks
------------------------------------------------------------
{-# INLINABLE validAfterDeadline #-}
validAfterDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
validAfterDeadline deadline info =
  I.contains (I.from deadline) (V2.txInfoValidRange info)

{-# INLINABLE validBeforeDeadline #-}
validBeforeDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
validBeforeDeadline deadline info =
  I.contains (I.to deadline) (V2.txInfoValidRange info)

------------------------------------------------------------
-- Beacon burn
------------------------------------------------------------
{-# INLINABLE mustBurnBeacon #-}
mustBurnBeacon :: (V2.CurrencySymbol, V2.TokenName) -> V2.TxInfo -> Bool
mustBurnBeacon (cs, tn) info =
  case Value.flattenValue (V2.txInfoMint info) of
    [(cs', tn', amt)] ->
         cs' == cs
      && tn' == tn
      && amt == (-1)
    _ -> False

------------------------------------------------------------
-- Auth / value helpers
------------------------------------------------------------
{-# INLINABLE sellerSigned #-}
sellerSigned :: V2.Credential -> V2.TxInfo -> Bool
sellerSigned cred info =
  case cred of
    V2.PubKeyCredential pkh -> pkh `elem` V2.txInfoSignatories info
    _                       -> False

{-# INLINABLE valuePaidTo #-}
valuePaidTo :: V2.Address -> V2.TxInfo -> V2.Value
valuePaidTo addr info =
  let outs = V2.txInfoOutputs info
      toAddr =
        [ V2.txOutValue o
        | o <- outs
        , V2.txOutAddress o == addr
        ]
  in mconcat toAddr

{-# INLINABLE refundIsExact #-}
refundIsExact :: V2.Credential -> V2.Value -> V2.TxInfo -> Bool
refundIsExact sellerCred offer info =
  let outs = V2.txInfoOutputs info
      toSeller =
        [ V2.txOutValue o
        | o <- outs
        , let addr = V2.txOutAddress o
        , addrCredential addr == sellerCred
        ]
      paidToSeller = mconcat toSeller
  in paidToSeller == offer
  where
    {-# INLINABLE addrCredential #-}
    addrCredential (V2.Address cred _stake) = cred

------------------------------------------------------------
-- Cancel branch
------------------------------------------------------------
{-# INLINABLE validateCancel #-}
validateCancel :: SwapDatum -> V2.TxInfo -> Bool
validateCancel SwapDatum{sdSeller, sdOffer, sdDeadline, sdSwapId} info =
     traceIfFalse "Cancel: too early"  (validAfterDeadline sdDeadline info)
  && traceIfFalse "Cancel: not seller" (sellerSigned sdSeller info)
  && traceIfFalse "Cancel: bad refund" (refundIsExact sdSeller sdOffer info)
  && case sdSwapId of
       Nothing     -> True
       Just beacon -> traceIfFalse "Cancel: beacon not burned" (mustBurnBeacon beacon info)

------------------------------------------------------------
-- Buy helpers
------------------------------------------------------------
{-# INLINABLE payoutsPaid #-}
payoutsPaid :: [Payout] -> V2.TxInfo -> Bool
payoutsPaid [] _ = True
payoutsPaid (Payout{pAddress, pValue} : rest) info =
     traceIfFalse "Buy: payout missing/mismatch"
       (valuePaidTo pAddress info == pValue)
  && payoutsPaid rest info

{-# INLINABLE payoutsMatchExpectation #-}
payoutsMatchExpectation :: [Payout] -> Expectation -> Bool
payoutsMatchExpectation payouts (ExpectExact expectedVal) =
  let total = mconcat [ pValue | Payout{pValue} <- payouts ]
  in  total == expectedVal

{-# INLINABLE offerDelivered #-}
offerDelivered :: V2.Value -> V2.TxInfo -> Bool
offerDelivered offer info =
  let outs = V2.txInfoOutputs info
      matches =
        [ ()
        | o <- outs
        , V2.txOutValue o == offer
        ]
  in case matches of
       [] -> False
       _  -> True

{-# INLINABLE hasAnyScriptOutput #-}
hasAnyScriptOutput :: V2.TxInfo -> Bool
hasAnyScriptOutput info =
  let outs = V2.txInfoOutputs info
      hits =
        [ ()
        | o <- outs
        , let V2.Address cred _ = V2.txOutAddress o
        , case cred of
            V2.ScriptCredential _ -> True
            _                     -> False
        ]
  in case hits of
       [] -> False
       _  -> True

------------------------------------------------------------
-- Buy branch
------------------------------------------------------------
{-# INLINABLE validateBuy #-}
validateBuy :: SwapDatum -> V2.ScriptContext -> Bool
validateBuy SwapDatum{ sdOffer
                     , sdExpect
                     , sdPayouts
                     , sdDeadline
                     , sdFlags = Flags{ fSingleFill }
                     , sdSwapId
                     } V2.ScriptContext{V2.scriptContextTxInfo = info} =
     traceIfFalse "Buy: too late" (validBeforeDeadline sdDeadline info)
  && traceIfFalse "Buy: payouts don't match expectation"
       (payoutsMatchExpectation sdPayouts sdExpect)
  && traceIfFalse "Buy: payout not paid"
       (payoutsPaid sdPayouts info)
  && traceIfFalse "Buy: offer not delivered"
       (offerDelivered sdOffer info)
  && traceIfFalse "Buy: single-fill but script output created"
       ( if fSingleFill then not (hasAnyScriptOutput info) else True )
  && case sdSwapId of
       Nothing     -> True
       Just beacon -> traceIfFalse "Buy: beacon not burned" (mustBurnBeacon beacon info)

------------------------------------------------------------
-- Top-level validator
------------------------------------------------------------
{-# INLINABLE mkSwapValidator #-}
mkSwapValidator :: SwapParams -> SwapDatum -> SwapRedeemer -> V2.ScriptContext -> Bool
mkSwapValidator _params datum redeemer ctx@V2.ScriptContext{V2.scriptContextTxInfo=info} =
  case redeemer of
    Cancel              -> validateCancel datum info
    Buy                 -> validateBuy datum ctx
    ClaimWithPreimage _ -> traceError "HTLC path not implemented"
