{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module AtomicSwapSpec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Value    as Value
import qualified Plutus.V1.Ledger.Interval as I
import qualified PlutusTx.AssocMap         as AM

-- this is the pure on-chain module we made
import qualified AtomicSwapScript as AS

import Prelude
  ( Maybe(..)
  , ($)
  , IO
  , Bool(..)
  , Integer
  , mempty
  , (-)
  , (+)
  )

------------------------------------------------------------
-- tiny helper: build ADA value
------------------------------------------------------------
ada :: Integer -> V2.Value
ada n = Value.singleton Value.adaSymbol Value.adaToken n

------------------------------------------------------------
-- fixed actors
------------------------------------------------------------

sellerPkh :: V2.PubKeyHash
sellerPkh = "00000000000000000000000000000000000000000000000000000000"

sellerCred :: V2.Credential
sellerCred = V2.PubKeyCredential sellerPkh

sellerAddr :: V2.Address
sellerAddr = V2.Address sellerCred Nothing

takerPkh :: V2.PubKeyHash
takerPkh = "11111111111111111111111111111111111111111111111111111111"

takerCred :: V2.Credential
takerCred = V2.PubKeyCredential takerPkh

takerAddr :: V2.Address
takerAddr = V2.Address takerCred Nothing

------------------------------------------------------------
-- params: just take them from the script module
------------------------------------------------------------

testParams :: AS.SwapParams
testParams = AS.defaultSwapParams

------------------------------------------------------------
-- helpers to build tx info / ctx
------------------------------------------------------------

mkOut :: V2.Address -> V2.Value -> V2.TxOut
mkOut addr val = V2.TxOut
  { V2.txOutAddress         = addr
  , V2.txOutValue           = val
  , V2.txOutDatum           = V2.NoOutputDatum
  , V2.txOutReferenceScript = Nothing
  }

mkTxInfo :: [V2.TxOut] -> V2.POSIXTimeRange -> [V2.PubKeyHash] -> V2.TxInfo
mkTxInfo outs range sigs =
  V2.TxInfo
    { V2.txInfoInputs          = []
    , V2.txInfoReferenceInputs = []
    , V2.txInfoOutputs         = outs
    , V2.txInfoFee             = mempty
    , V2.txInfoMint            = mempty
    , V2.txInfoDCert           = []
    , V2.txInfoWdrl            = AM.empty
    , V2.txInfoValidRange      = range
    , V2.txInfoSignatories     = sigs
    , V2.txInfoRedeemers       = AM.empty
    , V2.txInfoData            = AM.empty
    , V2.txInfoId              = V2.TxId "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }

mkCtx :: V2.TxInfo -> V2.ScriptContext
mkCtx info =
  V2.ScriptContext
    { V2.scriptContextTxInfo = info
    , V2.scriptContextPurpose =
        V2.Spending (V2.TxOutRef (V2.TxId "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") 0)
    }

-- your single-file Flags only has one field
defaultFlags :: AS.Flags
defaultFlags = AS.Flags
  { AS.fSingleFill = True
  }

------------------------------------------------------------
-- tests
------------------------------------------------------------

tests :: TestTree
tests =
  testGroup "AtomicSwap (single-file)"
    [ -- 1. CANCEL: happy path
      testCase "Cancel succeeds after deadline with seller sig + exact refund" $ do
        let offer    = ada 10_000_000
            deadline = 1_000
            datum = AS.SwapDatum
              { AS.sdSeller   = sellerCred
              , AS.sdOffer    = offer
              , AS.sdExpect   = AS.ExpectExact mempty
              , AS.sdPayouts  = []
              , AS.sdDeadline = deadline
              , AS.sdFlags    = defaultFlags
              , AS.sdSwapId   = Nothing
              }
            outToSeller = mkOut sellerAddr offer
            range       = I.from deadline
            info        = mkTxInfo [outToSeller] range [sellerPkh]
            ctx         = mkCtx info
            ok          = AS.mkSwapValidator testParams datum AS.Cancel ctx
        ok @?= True

    , -- 2. CANCEL: too early
      testCase "Cancel fails before deadline" $ do
        let offer    = ada 10_000_000
            deadline = 1_000
            datum = AS.SwapDatum
              { AS.sdSeller   = sellerCred
              , AS.sdOffer    = offer
              , AS.sdExpect   = AS.ExpectExact mempty
              , AS.sdPayouts  = []
              , AS.sdDeadline = deadline
              , AS.sdFlags    = defaultFlags
              , AS.sdSwapId   = Nothing
              }
            outToSeller = mkOut sellerAddr offer
            range       = I.to (deadline - 1)
            info        = mkTxInfo [outToSeller] range [sellerPkh]
            ctx         = mkCtx info
            ok          = AS.mkSwapValidator testParams datum AS.Cancel ctx
        ok @?= False

    , -- 3. CANCEL: no seller sig
      testCase "Cancel fails without seller signature" $ do
        let offer    = ada 10_000_000
            deadline = 1_000
            datum = AS.SwapDatum
              { AS.sdSeller   = sellerCred
              , AS.sdOffer    = offer
              , AS.sdExpect   = AS.ExpectExact mempty
              , AS.sdPayouts  = []
              , AS.sdDeadline = deadline
              , AS.sdFlags    = defaultFlags
              , AS.sdSwapId   = Nothing
              }
            outToSeller = mkOut sellerAddr offer
            range       = I.from deadline
            info        = mkTxInfo [outToSeller] range []  -- no sigs
            ctx         = mkCtx info
            ok          = AS.mkSwapValidator testParams datum AS.Cancel ctx
        ok @?= False

    , -- 4. CANCEL: amount mismatch
      testCase "Cancel fails if refund amount != sdOffer" $ do
        let offer    = ada 10_000_000
            deadline = 1_000
            datum = AS.SwapDatum
              { AS.sdSeller   = sellerCred
              , AS.sdOffer    = offer
              , AS.sdExpect   = AS.ExpectExact mempty
              , AS.sdPayouts  = []
              , AS.sdDeadline = deadline
              , AS.sdFlags    = defaultFlags
              , AS.sdSwapId   = Nothing
              }
            outToSeller = mkOut sellerAddr (ada 9_000_000)
            range       = I.from deadline
            info        = mkTxInfo [outToSeller] range [sellerPkh]
            ctx         = mkCtx info
            ok          = AS.mkSwapValidator testParams datum AS.Cancel ctx
        ok @?= False

    , -- 5. BUY: happy path
      testCase "Buy succeeds before deadline with correct payouts and offer" $ do
        let offer    = ada 4_000_000
            price    = ada 5_000_000
            deadline = 1_000
            payouts  = [ AS.Payout { AS.pAddress = sellerAddr, AS.pValue = price } ]

            datum = AS.SwapDatum
              { AS.sdSeller   = sellerCred
              , AS.sdOffer    = offer
              , AS.sdExpect   = AS.ExpectExact price
              , AS.sdPayouts  = payouts
              , AS.sdDeadline = deadline
              , AS.sdFlags    = defaultFlags
              , AS.sdSwapId   = Nothing
              }

            outToSeller = mkOut sellerAddr price
            outToTaker  = mkOut takerAddr  offer

            range       = I.to deadline
            info        = mkTxInfo [outToSeller, outToTaker] range []
            ctx         = mkCtx info
            ok          = AS.mkSwapValidator testParams datum AS.Buy ctx
        ok @?= True
    ]
