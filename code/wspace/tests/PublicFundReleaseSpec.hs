{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NumericUnderscores  #-}

module PublicFundReleaseSpec (tests) where

import Prelude (IO, Eq(..), Show(..), ($), (.), (++))
import qualified Prelude as P

import Test.Tasty
import Test.Tasty.HUnit

import PlutusTx.Prelude hiding (Semigroup(..), unless, ($))
import qualified PlutusTx.Builtins as Builtins

import Plutus.V2.Ledger.Api
  ( Address(..), Credential(..), Datum(..), OutputDatum(..)
  , POSIXTime(..), POSIXTimeRange
  , PubKeyHash(..)
  , ScriptContext(..), ScriptPurpose(..)
  , TxId(..), TxInInfo(..), TxInfo(..), TxOut(..), TxOutRef(..)
  , ValidatorHash(..)
  )

import Plutus.V1.Ledger.Value (adaSymbol, adaToken)
import qualified Plutus.V1.Ledger.Value as Value
import qualified Plutus.V1.Ledger.Interval as I

import qualified Data.ByteString.Char8 as BSC

import PlutusTx.AssocMap (Map)
import qualified PlutusTx.AssocMap as Map

import qualified PlutusTx

import PublicFundReleaseContract
  ( FundDatum(..)
  , FundRedeemer(..)
  , mkValidator
  )

--------------------------------------------------------------------------------
-- Dummy identities + addresses
--------------------------------------------------------------------------------

dummyTxId :: TxId
dummyTxId = TxId (Builtins.toBuiltin (BSC.pack "pfr-dummy-txid"))

dummyVH :: ValidatorHash
dummyVH = ValidatorHash (Builtins.toBuiltin (BSC.pack "pfr-script"))

pkhDepositor, pkhBeneficiary, pkhOfficial1, pkhOfficial2, pkhOutsider :: PubKeyHash
pkhDepositor   = PubKeyHash (Builtins.toBuiltin (BSC.pack "depositor"))
pkhBeneficiary = PubKeyHash (Builtins.toBuiltin (BSC.pack "beneficiary"))
pkhOfficial1   = PubKeyHash (Builtins.toBuiltin (BSC.pack "official-1"))
pkhOfficial2   = PubKeyHash (Builtins.toBuiltin (BSC.pack "official-2"))
pkhOutsider    = PubKeyHash (Builtins.toBuiltin (BSC.pack "outsider"))

scriptAddr :: Address
scriptAddr = Address (ScriptCredential dummyVH) Nothing

pkAddr :: PubKeyHash -> Address
pkAddr pkh = Address (PubKeyCredential pkh) Nothing

lovelace :: Integer -> Value.Value
lovelace n = Value.singleton adaSymbol adaToken n

--------------------------------------------------------------------------------
-- TxOut builders
--------------------------------------------------------------------------------

scriptInputOut :: Integer -> TxOut
scriptInputOut amt =
  TxOut
    { txOutAddress         = scriptAddr
    , txOutValue           = lovelace amt
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

continuingOut :: Integer -> FundDatum -> TxOut
continuingOut amt d =
  TxOut
    { txOutAddress         = scriptAddr
    , txOutValue           = lovelace amt
    , txOutDatum           = OutputDatum (Datum (PlutusTx.toBuiltinData d))
    , txOutReferenceScript = Nothing
    }

payTo :: PubKeyHash -> Integer -> TxOut
payTo pkh amt =
  TxOut
    { txOutAddress         = pkAddr pkh
    , txOutValue           = lovelace amt
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

--------------------------------------------------------------------------------
-- Context builder
--------------------------------------------------------------------------------

mkInfo :: Integer -> [TxOut] -> [PubKeyHash] -> POSIXTimeRange -> TxInfo
mkInfo lockedAmt outs sigs range =
  let
    inputInfo = TxInInfo
      { txInInfoOutRef   = TxOutRef dummyTxId 0
      , txInInfoResolved = scriptInputOut lockedAmt
      }
  in
    TxInfo
      { txInfoInputs          = [inputInfo]
      , txInfoReferenceInputs = []
      , txInfoOutputs         = outs
      , txInfoFee             = mempty
      , txInfoMint            = mempty
      , txInfoDCert           = []
      , txInfoWdrl            = Map.empty
      , txInfoValidRange      = range
      , txInfoSignatories     = sigs
      , txInfoRedeemers       = Map.empty
      , txInfoData            = Map.empty
      , txInfoId              = dummyTxId
      }

mkCtx :: Integer -> [TxOut] -> [PubKeyHash] -> POSIXTimeRange -> ScriptContext
mkCtx lockedAmt outs sigs range =
  ScriptContext (mkInfo lockedAmt outs sigs range) (Spending (TxOutRef dummyTxId 0))

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup "PublicFundRelease (on-chain)"
    [ testCase "Approve succeeds: before deadline, official signed, datum updated, 1 continuing output" $
        assertBool "expected approve to pass" approve_ok

    , testCase "Approve fails: not an official" $
        assertBool "expected approve to fail" (P.not approve_notOfficial)

    , testCase "Approve fails: already approved" $
        assertBool "expected approve to fail" (P.not approve_already)

    , testCase "Release succeeds: approvals >= required, before deadline, pays beneficiary, no continuing outputs" $
        assertBool "expected release to pass" release_ok

    , testCase "Release fails: not enough approvals" $
        assertBool "expected release to fail" (P.not release_notEnough)

    , testCase "Refund succeeds: after deadline, approvals < required, pays depositor, no continuing outputs" $
        assertBool "expected refund to pass" refund_ok

    , testCase "Refund fails: too early" $
        assertBool "expected refund to fail" (P.not refund_tooEarly)

    , testCase "Fails when approvals are not unique" $
        assertBool "expected failure due to duplicates" (P.not dupApprovals_fails)

    , testCase "Fails when approvals include non-official" $
        assertBool "expected failure due to outsider approval" (P.not outsiderApproval_fails)
    ]
  where
    lockedAmt :: Integer
    lockedAmt = 2_000_000

    dl :: POSIXTime
    dl = POSIXTime 1_000

    beforeDl :: POSIXTimeRange
    beforeDl = I.to dl

    afterDl :: POSIXTimeRange
    afterDl = I.from (dl + 1)

    baseDatum :: FundDatum
    baseDatum =
      FundDatum
        { fdDepositor   = pkhDepositor
        , fdBeneficiary = pkhBeneficiary
        , fdOfficials   = [pkhOfficial1, pkhOfficial2]
        , fdRequired    = 2
        , fdDeadline    = dl
        , fdApprovals   = []
        }

    -- Approve happy path
    approve_ok :: P.Bool
    approve_ok =
      let who     = pkhOfficial1
          newDat  = baseDatum { fdApprovals = who : fdApprovals baseDatum }
          ctx     = mkCtx lockedAmt [continuingOut lockedAmt newDat] [who] beforeDl
      in mkValidator baseDatum (Approve who) ctx

    approve_notOfficial :: P.Bool
    approve_notOfficial =
      let who    = pkhOutsider
          newDat = baseDatum { fdApprovals = who : fdApprovals baseDatum }
          ctx    = mkCtx lockedAmt [continuingOut lockedAmt newDat] [who] beforeDl
      in mkValidator baseDatum (Approve who) ctx

    approve_already :: P.Bool
    approve_already =
      let who    = pkhOfficial1
          dat0   = baseDatum { fdApprovals = [who] }
          newDat = dat0 { fdApprovals = who : fdApprovals dat0 }
          ctx    = mkCtx lockedAmt [continuingOut lockedAmt newDat] [who] beforeDl
      in mkValidator dat0 (Approve who) ctx

    -- Release happy path
    release_ok :: P.Bool
    release_ok =
      let dat0 = baseDatum { fdApprovals = [pkhOfficial1, pkhOfficial2] }
          ctx  = mkCtx lockedAmt [payTo pkhBeneficiary lockedAmt] [] beforeDl
      in mkValidator dat0 Release ctx

    release_notEnough :: P.Bool
    release_notEnough =
      let dat0 = baseDatum { fdApprovals = [pkhOfficial1] } -- required=2
          ctx  = mkCtx lockedAmt [payTo pkhBeneficiary lockedAmt] [] beforeDl
      in mkValidator dat0 Release ctx

    -- Refund happy path
    refund_ok :: P.Bool
    refund_ok =
      let dat0 = baseDatum { fdApprovals = [pkhOfficial1] } -- < required
          ctx  = mkCtx lockedAmt [payTo pkhDepositor lockedAmt] [] afterDl
      in mkValidator dat0 Refund ctx

    refund_tooEarly :: P.Bool
    refund_tooEarly =
      let dat0 = baseDatum { fdApprovals = [] }
          ctx  = mkCtx lockedAmt [payTo pkhDepositor lockedAmt] [] beforeDl
      in mkValidator dat0 Refund ctx

    dupApprovals_fails :: P.Bool
    dupApprovals_fails =
      let dat0 = baseDatum { fdApprovals = [pkhOfficial1, pkhOfficial1] }
          ctx  = mkCtx lockedAmt [payTo pkhBeneficiary lockedAmt] [] beforeDl
      in mkValidator dat0 Release ctx

    outsiderApproval_fails :: P.Bool
    outsiderApproval_fails =
      let dat0 = baseDatum { fdApprovals = [pkhOfficial1, pkhOutsider] }
          ctx  = mkCtx lockedAmt [payTo pkhBeneficiary lockedAmt] [] beforeDl
      in mkValidator dat0 Release ctx
