{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module AtomicSwapHTLCSpec (tests) where

import Prelude
  ( ($)
  , (+)
  , Bool(..)
  , Integer
  , mempty
  )

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Interval as I
import qualified PlutusTx.AssocMap         as AM
import qualified PlutusTx.Builtins         as Builtins

import AtomicSwapHTLCScript
  ( HtlcDatum(..)
  , HtlcRedeemer(..)   -- Redeem, Refund
  , mkHtlc
  )

------------------------------------------------------------
-- fixed actors (PubKeyHash, not Credential)
------------------------------------------------------------

makerPkh :: V2.PubKeyHash
makerPkh = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

beneficiaryPkh :: V2.PubKeyHash
beneficiaryPkh = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

------------------------------------------------------------
-- helpers to build TxInfo / ScriptContext
------------------------------------------------------------

mkTxInfo :: V2.POSIXTimeRange -> [V2.PubKeyHash] -> V2.TxInfo
mkTxInfo range sigs =
  V2.TxInfo
    { V2.txInfoInputs          = []
    , V2.txInfoReferenceInputs = []
    , V2.txInfoOutputs         = []
    , V2.txInfoFee             = mempty
    , V2.txInfoMint            = mempty
    , V2.txInfoDCert           = []
    , V2.txInfoWdrl            = AM.empty
    , V2.txInfoValidRange      = range
    , V2.txInfoSignatories     = sigs
    , V2.txInfoRedeemers       = AM.empty
    , V2.txInfoData            = AM.empty
    , V2.txInfoId              = V2.TxId "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }

mkCtx :: V2.TxInfo -> V2.ScriptContext
mkCtx info =
  V2.ScriptContext
    { V2.scriptContextTxInfo = info
    , V2.scriptContextPurpose =
        V2.Spending (V2.TxOutRef (V2.TxId "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd") 0)
    }

------------------------------------------------------------
-- the tests
------------------------------------------------------------

tests :: TestTree
tests =
  testGroup "AtomicSwap HTLC"
    [
      -- 1. Beneficiary claims with correct preimage before deadline
      testCase "claim succeeds with correct preimage before deadline" $ do
        let preimage = "supersecret"
            hash     = Builtins.sha2_256 preimage
            deadline = 1_000
            datum    = HtlcDatum
              { hdMaker       = makerPkh
              , hdBeneficiary = beneficiaryPkh
              , hdHash        = hash
              , hdDeadline    = deadline
              }
            range = I.to deadline
            info  = mkTxInfo range [beneficiaryPkh]
            ctx   = mkCtx info
            ok    = mkHtlc datum (Redeem preimage) ctx
        ok @?= True

      -- 2. Wrong preimage
    , testCase "claim fails with wrong preimage" $ do
        let correct  = "supersecret"
            hash     = Builtins.sha2_256 correct
            wrong    = "oops"
            deadline = 1_000
            datum = HtlcDatum
              { hdMaker       = makerPkh
              , hdBeneficiary = beneficiaryPkh
              , hdHash        = hash
              , hdDeadline    = deadline
              }
            range = I.to deadline
            info  = mkTxInfo range [beneficiaryPkh]
            ctx   = mkCtx info
            ok    = mkHtlc datum (Redeem wrong) ctx
        ok @?= False

      -- 3. Maker refunds after deadline
    , testCase "refund succeeds for maker after deadline" $ do
        let deadline = 1_000
            datum = HtlcDatum
              { hdMaker       = makerPkh
              , hdBeneficiary = beneficiaryPkh
              , hdHash        = Builtins.sha2_256 "anything"
              , hdDeadline    = deadline
              }
            range = I.from (deadline + 1)
            info  = mkTxInfo range [makerPkh]
            ctx   = mkCtx info
            ok    = mkHtlc datum Refund ctx
        ok @?= True

      -- 4. Maker tries to refund before deadline
    , testCase "refund fails for maker before deadline" $ do
        let deadline = 1_000
            datum = HtlcDatum
              { hdMaker       = makerPkh
              , hdBeneficiary = beneficiaryPkh
              , hdHash        = Builtins.sha2_256 "anything"
              , hdDeadline    = deadline
              }
            range = I.to deadline
            info  = mkTxInfo range [makerPkh]
            ctx   = mkCtx info
            ok    = mkHtlc datum Refund ctx
        ok @?= False
    ]
