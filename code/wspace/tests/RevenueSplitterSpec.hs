{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NumericUnderscores  #-}

module RevenueSplitterSpec
  ( revenueSplitterTests
  ) where

import Prelude (IO, Show(..), Eq(..), ($), (.), (++))
import qualified Prelude               as P

import Test.Tasty
import Test.Tasty.HUnit

-- On-chain Prelude
import PlutusTx.Prelude hiding (Semigroup(..), unless, ($))
import qualified PlutusTx.Builtins     as Builtins

import Plutus.V2.Ledger.Api
import Plutus.V1.Ledger.Value           (adaSymbol, adaToken)
import qualified Plutus.V1.Ledger.Value as Value
import qualified Plutus.V1.Ledger.Interval as I

import qualified Data.ByteString.Char8 as BSC

-- 🔁 Use Plutus associative Map, not Data.Map
import PlutusTx.AssocMap (Map)
import qualified PlutusTx.AssocMap as Map

import RevenueSplitterContract
  ( RevenueDatum(..)
  , RevenueRedeemer(..)   -- 🔁 bring in the redeemer type/constructor
  , mkRevenueValidator
  )

--------------------------------------------------------------------------------
-- Helpers for building dummy contexts
--------------------------------------------------------------------------------

dummyTxId :: TxId
dummyTxId =
  TxId (Builtins.toBuiltin (BSC.pack "dummy-tx-id"))

pkhA, pkhB :: PubKeyHash
pkhA = PubKeyHash (Builtins.toBuiltin (BSC.pack "alice"))
pkhB = PubKeyHash (Builtins.toBuiltin (BSC.pack "bob"))

-- | Build an Address for a normal public-key wallet.
pkAddress :: PubKeyHash -> Address
pkAddress pkh = Address (PubKeyCredential pkh) Nothing

-- | Script input UTxO sitting at the revenue splitter, holding @totalAda@.
scriptInputOut :: Integer -> TxOut
scriptInputOut totalAda =
  TxOut
    { txOutAddress         = Address (ScriptCredential dummyValidatorHash) Nothing
    , txOutValue           = Value.singleton adaSymbol adaToken totalAda
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

-- Dummy script hash – we don’t care about it for these tests.
dummyValidatorHash :: ValidatorHash
dummyValidatorHash =
  ValidatorHash (Builtins.toBuiltin (BSC.pack "rev-splitter"))

-- | Build a single TxOut paying @amt@ ADA to @pkh@.
recipientOut :: PubKeyHash -> Integer -> TxOut
recipientOut pkh amt =
  TxOut
    { txOutAddress         = pkAddress pkh
    , txOutValue           = Value.singleton adaSymbol adaToken amt
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

-- | Minimal TxInfo with:
--   * one script input (the revenue UTxO),
--   * some outputs paying to recipients,
--   * everything else empty / defaulted.
mkTxInfo :: Integer -> [(PubKeyHash, Integer)] -> TxInfo
mkTxInfo totalAda payouts =
  let
    inputOut  = scriptInputOut totalAda

    inputInfo = TxInInfo
      { txInInfoOutRef   = TxOutRef dummyTxId 0
      , txInInfoResolved = inputOut
      }

    outs = [ recipientOut p a | (p, a) <- payouts ]
  in
    TxInfo
      { txInfoInputs          = [inputInfo]
      , txInfoReferenceInputs = []
      , txInfoOutputs         = outs
      , txInfoFee             = mempty
      , txInfoMint            = mempty
      , txInfoDCert           = []
      , txInfoWdrl            = Map.empty      -- 🔁 Plutus Map
      , txInfoValidRange      = I.always
      , txInfoSignatories     = []
      , txInfoRedeemers       = Map.empty      -- 🔁 Plutus Map
      , txInfoData            = Map.empty      -- 🔁 Plutus Map
      , txInfoId              = dummyTxId
      }

-- | Full ScriptContext for a spending of the revenue UTxO.
mkCtx :: Integer -> [(PubKeyHash, Integer)] -> ScriptContext
mkCtx totalAda payouts =
  let info    = mkTxInfo totalAda payouts
      purpose = Spending (TxOutRef dummyTxId 0)
  in ScriptContext info purpose

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

revenueSplitterTests :: TestTree
revenueSplitterTests =
  testGroup "RevenueSplitter (on-chain)"
    [ testCase "valid split passes when totals and outputs match" $
        assertBool "expected valid revenue split" validCase

    , testCase "fails when sum of shares does not match input ADA" $
        assertBool "expected validator to fail" (P.not invalidTotalCase)

    , testCase "fails when one recipient is underpaid" $
        assertBool "expected validator to fail" (P.not underpaidCase)
    ]

  where
    -- 1) Happy path: script holds 1 000 000, shares are 600k + 400k,
    --    and outputs pay exactly those amounts.
    validCase :: P.Bool
    validCase =
      let dat = RevenueDatum
                  { rdEventId    = "event-1"
                  , rdRecipients = [(pkhA, 600_000), (pkhB, 400_000)]
                  }
          totalAda  = 1_000_000
          payouts   =
            [ (pkhA, 600_000)
            , (pkhB, 400_000)
            ]
          ctx = mkCtx totalAda payouts
      in mkRevenueValidator dat Distribute ctx   -- 🔁 use real redeemer

    -- 2) Shares don’t add up to input – should fail because
    --    sum(rdRecipients) /= inputAda.
    invalidTotalCase :: P.Bool
    invalidTotalCase =
      let dat = RevenueDatum
                  { rdEventId    = "event-2"
                  , rdRecipients = [(pkhA, 700_000), (pkhB, 400_000)] -- sum = 1.1M
                  }
          totalAda = 1_000_000
          payouts  =
            [ (pkhA, 700_000)
            , (pkhB, 400_000)
            ]
          ctx = mkCtx totalAda payouts
      in mkRevenueValidator dat Distribute ctx   -- 🔁 use real redeemer

    -- 3) Totals match, but Bob gets underpaid (300k instead of 400k).
    --    Should fail the "each recipient gets at least share" check.
    underpaidCase :: P.Bool
    underpaidCase =
      let dat = RevenueDatum
                  { rdEventId    = "event-3"
                  , rdRecipients = [(pkhA, 600_000), (pkhB, 400_000)]
                  }
          totalAda = 1_000_000
          payouts  =
            [ (pkhA, 600_000)
            , (pkhB, 300_000)  -- underpaid
            ]
          ctx = mkCtx totalAda payouts
      in mkRevenueValidator dat Distribute ctx   -- 🔁 use real redeemer
