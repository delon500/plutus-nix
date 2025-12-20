{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import GHC.Generics (Generic)

import PlutusTx
import PlutusTx.Prelude
  hiding (Semigroup(..), unless) 

import Plutus.V1.Ledger.Interval (contains, from, to)
import Plutus.V1.Ledger.Value as Value (geq)

import Prelude (IO, FilePath, putStrLn)
import qualified Prelude as P
import System.Environment (getArgs)

import qualified Cardano.Api          as C
import qualified Cardano.Api.Shelley  as CS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Short as SBS
import Codec.Serialise (serialise)

import qualified Plutus.V2.Ledger.Api as Plutus (unValidatorScript)

import Plutus.V2.Ledger.Api
  ( BuiltinData
  , Datum(..)
  , POSIXTime
  , PubKeyHash
  , ScriptContext(..)
  , TxInfo(..)
  , TxOut(..)
  , Validator
  , OutputDatum(..)
  , mkValidatorScript
  , txInfoValidRange
  , txOutDatum
  , txOutValue
  )

import Plutus.V2.Ledger.Contexts
  ( findDatum
  , findOwnInput
  , getContinuingOutputs
  , scriptContextTxInfo
  , txInInfoResolved
  , txSignedBy
  , valuePaidTo
  )

--------------------------------------------------
-- Datum / Redeemer (ON-CHAIN STATE + ACTION)
--------------------------------------------------

data FundDatum = FundDatum
  { fdDepositor   :: PubKeyHash
  , fdBeneficiary :: PubKeyHash
  , fdOfficials   :: [PubKeyHash]     -- m officials
  , fdRequired    :: Integer          -- n approvals required
  , fdDeadline    :: POSIXTime
  , fdApprovals   :: [PubKeyHash]     -- unique approvals collected
  }
  deriving (Generic)

data FundRedeemer
  = Approve PubKeyHash
  | Release
  | Refund
  deriving (Generic)

PlutusTx.unstableMakeIsData ''FundDatum
PlutusTx.unstableMakeIsData ''FundRedeemer
PlutusTx.makeLift ''FundDatum
PlutusTx.makeLift ''FundRedeemer

--------------------------------------------------
-- Helpers
--------------------------------------------------

{-# INLINABLE allUnique #-}
allUnique :: [PubKeyHash] -> Bool
allUnique []     = True
allUnique (x:xs) = not (x `elem` xs) && allUnique xs

{-#INLINABLE approvalsFromOfficials #-}
approvalsFromOfficials :: FundDatum -> Bool
approvalsFromOfficials d = 
  all (\pk -> pk `elem` fdOfficials d) (fdApprovals d) -- Every approval must be one of the configured officials

{-# INLINABLE validConfig #-}
validConfig :: FundDatum -> Bool
validConfig d =
  fdRequired d > 0 &&
  fdRequired d <= length (fdOfficials d)

{-# INLINABLE beforeDeadline #-}
beforeDeadline :: POSIXTime -> TxInfo -> Bool
beforeDeadline dl info = contains (to dl) (txInfoValidRange info)

{-# INLINABLE afterDeadline #-}
afterDeadline :: POSIXTime -> TxInfo -> Bool
afterDeadline dl info = contains (from dl) (txInfoValidRange info)

{-# INLINABLE sameStaticFields #-}
sameStaticFields :: FundDatum -> FundDatum -> Bool
sameStaticFields a b =
     fdDepositor a   == fdDepositor b
  && fdBeneficiary a == fdBeneficiary b
  && fdOfficials a   == fdOfficials b
  && fdRequired a    == fdRequired b
  && fdDeadline a    == fdDeadline b

{-# INLINABLE getOutputFundDatum #-}
getOutputFundDatum :: TxInfo -> TxOut -> Maybe FundDatum
getOutputFundDatum info o =
  case txOutDatum o of
    NoOutputDatum -> Nothing
    OutputDatum (Datum bd) -> PlutusTx.fromBuiltinData bd
    OutputDatumHash dh ->
      case findDatum dh info of
        Nothing         -> Nothing
        Just (Datum bd) -> PlutusTx.fromBuiltinData bd

{-# INLINABLE mustHaveSingleContinuingOutputWith #-}
mustHaveSingleContinuingOutputWith :: (TxOut -> Bool) -> ScriptContext -> Bool
mustHaveSingleContinuingOutputWith p ctx =
  case getContinuingOutputs ctx of
    [o] -> p o
    _   -> False

--------------------------------------------------
-- Validator
--------------------------------------------------

{-# INLINABLE mkValidator #-}
mkValidator :: FundDatum -> FundRedeemer -> ScriptContext -> Bool
mkValidator dat red ctx =
  traceIfFalse "bad config" (validConfig dat) &&
  traceIfFalse "approvals not unique" (allUnique (fdApprovals dat)) &&
  traceIfFalse "approval not from officials" (approvalsFromOfficials dat) &&
  case red of

    Approve who ->
      traceIfFalse "deadline passed" (beforeDeadline (fdDeadline dat) info) &&
      traceIfFalse "not an official" (who `elem` fdOfficials dat) &&
      traceIfFalse "already approved" (not (who `elem` fdApprovals dat)) &&
      traceIfFalse "missing signature" (txSignedBy info who) &&
      traceIfFalse "bad continuation" (approveContinuation who)

    Release ->
      traceIfFalse "deadline passed" (beforeDeadline (fdDeadline dat) info) &&
      traceIfFalse "not enough approvals"
        (length (fdApprovals dat) >= fdRequired dat) &&
      traceIfFalse "must pay beneficiary" paysBeneficiary &&
      traceIfFalse "no continuing output allowed" (null (getContinuingOutputs ctx))

    Refund ->
      traceIfFalse "too early" (afterDeadline (fdDeadline dat) info) &&
      traceIfFalse "refund blocked (enough approvals)"
        (length (fdApprovals dat) < fdRequired dat) &&
      traceIfFalse "must pay depositor" paysDepositor &&
      traceIfFalse "no continuing output allowed" (null (getContinuingOutputs ctx))

  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    ownInputValue =
      case findOwnInput ctx of
        Nothing -> traceError "missing own input"
        Just i  -> txOutValue (txInInfoResolved i)

    approveContinuation :: PubKeyHash -> Bool
    approveContinuation who =
      mustHaveSingleContinuingOutputWith
        (\o ->
          traceIfFalse "value changed" (txOutValue o == ownInputValue) &&
          case getOutputFundDatum info o of
            Nothing   -> traceError "missing/invalid datum"
            Just dat' ->
              traceIfFalse "static fields changed" (sameStaticFields dat dat') &&
              traceIfFalse "approval not added"
                (fdApprovals dat' == (who : fdApprovals dat)) &&
              traceIfFalse "approvals not unique (new)"
                (allUnique (fdApprovals dat'))
        )
        ctx

    paysBeneficiary =
      valuePaidTo info (fdBeneficiary dat) `Value.geq` ownInputValue

    paysDepositor =
      valuePaidTo info (fdDepositor dat) `Value.geq` ownInputValue

--------------------------------------------------
-- Untyped wrapper + compiled Validator
--------------------------------------------------

{-# INLINABLE mkWrapped #-}
mkWrapped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkWrapped d r c =
  case ( PlutusTx.fromBuiltinData d
       , PlutusTx.fromBuiltinData r
       , PlutusTx.fromBuiltinData c
       ) of
    (Just dat, Just red, Just ctx) ->
      if mkValidator dat red ctx 
        then () 
        else traceError "validation failed"
    _ -> traceError "bad arguments"

validator :: Validator
validator = mkValidatorScript $$(PlutusTx.compile [|| mkWrapped ||])

-- Convert Validator -> .plutus (Plutus V2)
plutusScript :: CS.PlutusScript CS.PlutusScriptV2
plutusScript =
  CS.PlutusScriptSerialised
    (SBS.toShort . LBS.toStrict $ serialise (Plutus.unValidatorScript validator))

writePlutus :: FilePath -> IO ()
writePlutus outFile = do
  res <- C.writeFileTextEnvelope
         outFile
         (Just "Public Fund Release (n-of-m approvals) Validator")
         plutusScript
  case res of
    Left err -> 
      putStrLn ("Error writing .plutus file: " P.++ C.displayError err)
    Right () -> 
      putStrLn ("Wrote Plutus script to: " P.++ outFile)

main :: IO ()
main = do
  args <- getArgs
  let outFile =
        case args of
          (fp:_) -> fp
          _      -> "src/public-fund-release.plutus"
  writePlutus outFile
