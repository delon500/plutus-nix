{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

-- we want normal IO stuff
import Prelude (IO, (.))
import qualified Prelude as P

import qualified PlutusTx
import           PlutusTx.Prelude
  ( Bool(..)
  , (==)
  , (&&)
  , elem
  , traceIfFalse
  , traceError
  )
import qualified PlutusTx.Builtins as Builtins

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Interval as I

import Codec.Serialise (serialise)
import qualified Data.Aeson             as Aeson
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Lazy   as LBS
import qualified Data.ByteString.Char8  as BSC

------------------------------------------------------------
-- Datum & Redeemer (on-chain types)
------------------------------------------------------------

-- "classic" HTLC:
--   - maker locks funds
--   - beneficiary can take them with correct preimage before deadline
--   - maker can refund after deadline
data HtlcDatum = HtlcDatum
  { hdMaker       :: V2.PubKeyHash
  , hdBeneficiary :: V2.PubKeyHash
  , hdHash        :: V2.BuiltinByteString
  , hdDeadline    :: V2.POSIXTime
  }
PlutusTx.unstableMakeIsData ''HtlcDatum
PlutusTx.makeLift        ''HtlcDatum

data HtlcRedeemer
  = Redeem V2.BuiltinByteString  -- present preimage
  | Refund                        -- maker takes funds back
PlutusTx.unstableMakeIsData ''HtlcRedeemer
PlutusTx.makeLift        ''HtlcRedeemer

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------

{-# INLINABLE signedBy #-}
signedBy :: V2.TxInfo -> V2.PubKeyHash -> Bool
signedBy info pkh = pkh `elem` V2.txInfoSignatories info

{-# INLINABLE insideDeadline #-}
insideDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
insideDeadline d info = I.contains (I.to d) (V2.txInfoValidRange info)

{-# INLINABLE afterDeadline #-}
afterDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
afterDeadline d info = I.contains (I.from d) (V2.txInfoValidRange info)

------------------------------------------------------------
-- On-chain validator
------------------------------------------------------------

{-# INLINABLE mkHtlc #-}
mkHtlc :: HtlcDatum -> HtlcRedeemer -> V2.ScriptContext -> Bool
mkHtlc HtlcDatum{hdMaker, hdBeneficiary, hdHash, hdDeadline} redeemer ctx =
  let info = V2.scriptContextTxInfo ctx
  in case redeemer of
      -- beneficiary path
      Redeem preimage ->
           traceIfFalse "bad preimage"
             (Builtins.sha2_256 preimage == hdHash)
        && traceIfFalse "too late"
             (insideDeadline hdDeadline info)
        && traceIfFalse "not beneficiary"
             (signedBy info hdBeneficiary)

      -- maker path
      Refund ->
           traceIfFalse "too early"
             (afterDeadline hdDeadline info)
        && traceIfFalse "not maker"
             (signedBy info hdMaker)

------------------------------------------------------------
-- Untyped wrapper for PlutusTx.compile
------------------------------------------------------------

{-# INLINABLE mkUntyped #-}
mkUntyped :: V2.BuiltinData -> V2.BuiltinData -> V2.BuiltinData -> ()
mkUntyped d r c =
  let datum    = PlutusTx.unsafeFromBuiltinData d :: HtlcDatum
      redeemer = PlutusTx.unsafeFromBuiltinData r :: HtlcRedeemer
      ctx      = PlutusTx.unsafeFromBuiltinData c :: V2.ScriptContext
  in if mkHtlc datum redeemer ctx
        then ()
        else traceError "HTLC validation failed"

htlcValidator :: V2.Validator
htlcValidator =
  V2.mkValidatorScript
    $$(PlutusTx.compile [|| mkUntyped ||])

------------------------------------------------------------
-- Write out as JSON .plutus (like your other script)
------------------------------------------------------------

main :: IO ()
main = do
  let cbor     = serialise htlcValidator
      cborHex  = B16.encode (LBS.toStrict cbor)
      cborText = BSC.unpack cborHex
      json     = Aeson.object
        [ "type"        Aeson..= ("PlutusScriptV2" :: P.String)
        , "description" Aeson..= ("HTLC atomic swap validator" :: P.String)
        , "cborHex"     Aeson..= cborText
        ]
  LBS.writeFile "atomic-swap-htlc.plutus" (Aeson.encode json)
  P.putStrLn "wrote atomic-swap-htlc.plutus"
