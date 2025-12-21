{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module PublicFundReleaseContract where

import GHC.Generics (Generic)

import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)

import Plutus.V1.Ledger.Interval (contains, from, to)
import Plutus.V1.Ledger.Value as Value (geq)

import Plutus.V2.Ledger.Api
  ( BuiltinData, Datum(..), POSIXTime, PubKeyHash, ScriptContext(..)
  , TxInfo, TxOut, Validator, OutputDatum(..)
  , mkValidatorScript, txInfoValidRange, txOutDatum, txOutValue
  )

import Plutus.V2.Ledger.Contexts
  ( findDatum, findOwnInput, getContinuingOutputs, scriptContextTxInfo
  , txInInfoResolved, txSignedBy, valuePaidTo
  )

import Ledger (Address, ValidatorHash)

import qualified Plutus.Script.Utils.V2.Scripts  as ScriptsV2
import qualified Plutus.Script.Utils.V2.Address  as AddressV2

--------------------------------------------------
-- Datum / Redeemer
--------------------------------------------------

data FundDatum = FundDatum
  { fdDepositor   :: PubKeyHash
  , fdBeneficiary :: PubKeyHash
  , fdOfficials   :: [PubKeyHash]
  , fdRequired    :: Integer
  , fdDeadline    :: POSIXTime
  , fdApprovals   :: [PubKeyHash]
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

{-# INLINABLE approvalsFromOfficials #-}
approvalsFromOfficials :: FundDatum -> Bool
approvalsFromOfficials d =
  all (\pk -> pk `elem` fdOfficials d) (fdApprovals d)

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
      traceIfFalse "depositor must sign" (txSignedBy info (fdDepositor dat)) &&
      traceIfFalse "must pay depositor" paysDepositor &&
      traceIfFalse "no continuing output allowed" (null (getContinuingOutputs ctx))

  where
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

{-# INLINABLE mkWrapped #-}
mkWrapped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkWrapped d r c =
  case (PlutusTx.fromBuiltinData d, PlutusTx.fromBuiltinData r, PlutusTx.fromBuiltinData c) of
    (Just dat, Just red, Just ctx) ->
      if mkValidator dat red ctx then () else traceError "validation failed"
    _ -> traceError "bad arguments"

validator :: Validator
validator = mkValidatorScript $$(PlutusTx.compile [|| mkWrapped ||])

--------------------------------------------------
-- Validator hash + script address (used by tests)
--------------------------------------------------

valHash :: ValidatorHash
valHash = ScriptsV2.validatorHash validator

scrAddress :: Address
scrAddress = AddressV2.mkValidatorAddress validator
