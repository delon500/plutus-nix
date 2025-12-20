{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module PublicFundReleaseEndpoints
  ( PFRSchema
  , DepositParams(..)
  , endpoints
  ) where

import GHC.Generics (Generic)

import Prelude (Show(..), String, (<>))
import qualified Prelude as P

import Control.Monad (forever, void, when)

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Map as Map
import Data.Text (Text)
import Data.Void (Void)

import PlutusTx (toBuiltinData, fromBuiltinData)
import PlutusTx.Prelude hiding (Semigroup(..), unless)

import Plutus.Contract as Contract

import Ledger
  ( Address
  , ChainIndexTxOut
  , Datum(..)
  , PaymentPubKeyHash(..)
  , Redeemer(..)
  , TxOutRef
  , ValidatorHash
  , getCardanoTxId
  , scriptHashAddress
  , toTxOut
  , txOutDatum
  , txOutValue
  , validatorHash
  )
import qualified Ledger.Ada as Ada
import qualified Ledger.Constraints as Constraints

import Plutus.V1.Ledger.Interval (to, from)
import Plutus.V2.Ledger.Api (POSIXTime, PubKeyHash)

import PublicFundReleaseContract
  ( FundDatum(..)
  , FundRedeemer(..)
  , validator
  )

--------------------------------------------------------------------------------
-- Script identity
--------------------------------------------------------------------------------

valHash :: ValidatorHash
valHash = validatorHash validator

scriptAddress :: Address
scriptAddress = scriptHashAddress valHash

--------------------------------------------------------------------------------
-- Params + Schema
--------------------------------------------------------------------------------

data DepositParams = DepositParams
  { dpBeneficiary :: PubKeyHash
  , dpOfficials   :: [PubKeyHash]
  , dpRequired    :: Integer
  , dpDeadline    :: POSIXTime
  , dpLovelace    :: Integer
  }
  deriving (Generic, ToJSON, FromJSON)

type PFRSchema =
        Endpoint "deposit" DepositParams
    .\/ Endpoint "approve" ()
    .\/ Endpoint "release" ()
    .\/ Endpoint "refund"  ()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

mkDatum :: FundDatum -> Datum
mkDatum d = Datum (toBuiltinData d)

mkRed :: FundRedeemer -> Redeemer
mkRed r = Redeemer (toBuiltinData r)

toPPKH :: PubKeyHash -> PaymentPubKeyHash
toPPKH = PaymentPubKeyHash

-- Decode FundDatum from a script UTxO (datum hash -> datum -> FromData)
datumFromChainIndex :: ChainIndexTxOut -> Contract w s Text FundDatum
datumFromChainIndex o = do
  dh <- case txOutDatum (toTxOut o) of
          Nothing  -> throwError "No datum hash found on script output"
          Just dh' -> pure dh'

  md <- datumFromHash dh
  Datum bd <- case md of
                Nothing -> throwError "datumFromHash: datum not found"
                Just d  -> pure d

  case fromBuiltinData bd of
    Just d  -> pure d
    Nothing -> throwError "Could not decode FundDatum from datum"

pickFundUtxo :: Contract w s Text (TxOutRef, ChainIndexTxOut, FundDatum)
pickFundUtxo = do
  utxos <- utxosAt scriptAddress
  case Map.toList utxos of
    [] -> throwError "No UTxO found at script address"
    ((oref, o):_) -> do
      d <- datumFromChainIndex o
      pure (oref, o, d)

--------------------------------------------------------------------------------
-- Endpoints
--------------------------------------------------------------------------------

deposit :: DepositParams -> Contract () PFRSchema Text ()
deposit p = do
  ppkh <- ownFirstPaymentPubKeyHash
  let depositor = unPaymentPubKeyHash ppkh

  when (dpLovelace p P.<= 0) $
    throwError "dpLovelace must be > 0"
  when (dpRequired p P.<= 0) $
    throwError "dpRequired must be > 0"
  when (P.length (dpOfficials p) P.< P.fromIntegral (dpRequired p)) $
    throwError "dpRequired cannot exceed number of officials"

  let d = FundDatum
        { fdDepositor   = depositor
        , fdBeneficiary = dpBeneficiary p
        , fdOfficials   = dpOfficials p
        , fdRequired    = dpRequired p
        , fdDeadline    = dpDeadline p
        , fdApprovals   = []
        }

      v  = Ada.lovelaceValueOf (dpLovelace p)
      tx = Constraints.mustPayToOtherScript valHash (mkDatum d) v

  ledgerTx <- submitTx tx
  void (awaitTxConfirmed (getCardanoTxId ledgerTx))
  logInfo @String "Deposit submitted."

approve :: Contract () PFRSchema Text ()
approve = do
  ppkh <- ownFirstPaymentPubKeyHash
  let who = unPaymentPubKeyHash ppkh

  (oref, o, d) <- pickFundUtxo

  -- off-chain guard rails (nice errors instead of on-chain fail)
  when (P.not (who `P.elem` fdOfficials d)) $
    throwError "You are not an official for this fund"
  when (who `P.elem` fdApprovals d) $
    throwError "You already approved"

  let newDatum    = d { fdApprovals = who : fdApprovals d }
      valueLocked = txOutValue (toTxOut o)

      lookups =
           Constraints.unspentOutputs (Map.singleton oref o)
        <> Constraints.plutusV2OtherScript validator

      tx =
           Constraints.mustSpendScriptOutput oref (mkRed (Approve who))
        <> Constraints.mustPayToOtherScript valHash (mkDatum newDatum) valueLocked
        <> Constraints.mustBeSignedBy ppkh
        <> Constraints.mustValidateIn (to (fdDeadline d))

  ledgerTx <- submitTxConstraintsWith @Void lookups tx
  void (awaitTxConfirmed (getCardanoTxId ledgerTx))
  logInfo @String "Approval submitted."

release :: Contract () PFRSchema Text ()
release = do
  (oref, o, d) <- pickFundUtxo

  -- off-chain guard rails (again: friendlier than on-chain fail)
  let approvalsN :: Integer
      approvalsN = P.fromIntegral (P.length (fdApprovals d))

  when (approvalsN P.< fdRequired d) $
    throwError "Not enough approvals to release"

  -- optional sanity check (your on-chain already enforces this)
  when (P.any (\a -> P.not (a `P.elem` fdOfficials d)) (fdApprovals d)) $
    throwError "Approvals include a non-official"

  let valueLocked = txOutValue (toTxOut o)

      lookups =
           Constraints.unspentOutputs (Map.singleton oref o)
        <> Constraints.plutusV2OtherScript validator

      tx =
           Constraints.mustSpendScriptOutput oref (mkRed Release)
        <> Constraints.mustPayToPubKey (toPPKH (fdBeneficiary d)) valueLocked
        <> Constraints.mustValidateIn (to (fdDeadline d))

  ledgerTx <- submitTxConstraintsWith @Void lookups tx
  void (awaitTxConfirmed (getCardanoTxId ledgerTx))
  logInfo @String "Release submitted."

refund :: Contract () PFRSchema Text ()
refund = do
  ppkh <- ownFirstPaymentPubKeyHash
  let who = unPaymentPubKeyHash ppkh

  (oref, o, d) <- pickFundUtxo

  -- only depositor should run refund (good for your “governance” story)
  when (who P./= fdDepositor d) $
    throwError "Only the original depositor can request a refund"

  let approvalsN :: Integer
      approvalsN = P.fromIntegral (P.length (fdApprovals d))

  when (approvalsN P.>= fdRequired d) $
    throwError "Refund not allowed: approvals already meet/exceed required"

  let valueLocked = txOutValue (toTxOut o)

      lookups =
           Constraints.unspentOutputs (Map.singleton oref o)
        <> Constraints.plutusV2OtherScript validator

      -- IMPORTANT: “after deadline” → use deadline + 1 for clarity
      tx =
           Constraints.mustSpendScriptOutput oref (mkRed Refund)
        <> Constraints.mustPayToPubKey (toPPKH (fdDepositor d)) valueLocked
        <> Constraints.mustBeSignedBy ppkh
        <> Constraints.mustValidateIn (from (fdDeadline d + 1))

  ledgerTx <- submitTxConstraintsWith @Void lookups tx
  void (awaitTxConfirmed (getCardanoTxId ledgerTx))
  logInfo @String "Refund submitted."

endpoints :: Contract () PFRSchema Text ()
endpoints = forever $
  handleError logError $
    awaitPromise $
      deposit' `select` approve' `select` release' `select` refund'
  where
    deposit' = endpoint @"deposit" deposit
    approve' = endpoint @"approve" (const approve)
    release' = endpoint @"release" (const release)
    refund'  = endpoint @"refund"  (const refund)
