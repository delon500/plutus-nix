{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NamedFieldPuns #-}

module AtomicSwapHTLCScript where

import qualified PlutusTx
import           PlutusTx.Prelude
  ( Bool(..)
  , (&&)
  , (==)
  , elem
  , traceIfFalse
  )
import qualified PlutusTx.Builtins as Builtins
import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Interval as I

-- same datum
data HtlcDatum = HtlcDatum
  { hdMaker       :: V2.PubKeyHash
  , hdBeneficiary :: V2.PubKeyHash
  , hdHash        :: V2.BuiltinByteString
  , hdDeadline    :: V2.POSIXTime
  }
PlutusTx.unstableMakeIsData ''HtlcDatum
PlutusTx.makeLift        ''HtlcDatum

-- same redeemer
data HtlcRedeemer
  = Redeem V2.BuiltinByteString
  | Refund
PlutusTx.unstableMakeIsData ''HtlcRedeemer
PlutusTx.makeLift        ''HtlcRedeemer

{-# INLINABLE signedBy #-}
signedBy :: V2.TxInfo -> V2.PubKeyHash -> Bool
signedBy info pkh = pkh `elem` V2.txInfoSignatories info

{-# INLINABLE insideDeadline #-}
insideDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
insideDeadline d info = I.contains (I.to d) (V2.txInfoValidRange info)

{-# INLINABLE afterDeadline #-}
afterDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
afterDeadline d info = I.contains (I.from d) (V2.txInfoValidRange info)

{-# INLINABLE mkHtlc #-}
mkHtlc :: HtlcDatum -> HtlcRedeemer -> V2.ScriptContext -> Bool
mkHtlc HtlcDatum{hdMaker, hdBeneficiary, hdHash, hdDeadline} redeemer ctx =
  let info = V2.scriptContextTxInfo ctx
  in case redeemer of
      Redeem preimage ->
           traceIfFalse "bad preimage"
             (Builtins.sha2_256 preimage == hdHash)
        && traceIfFalse "too late"
             (insideDeadline hdDeadline info)
        && traceIfFalse "not beneficiary"
             (signedBy info hdBeneficiary)
      Refund ->
           traceIfFalse "too early"
             (afterDeadline hdDeadline info)
        && traceIfFalse "not maker"
             (signedBy info hdMaker)
