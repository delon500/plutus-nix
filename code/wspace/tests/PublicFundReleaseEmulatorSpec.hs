{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE NumericUnderscores #-}

module PublicFundReleaseEmulatorSpec (tests) where

import Prelude (IO, Eq(..), Show(..), String, ($), (.), (++), (<>))
import PlutusTx.Prelude hiding (Semigroup(..), unless, ($))
import qualified Prelude as P

import Control.Monad (void, when)

import Test.Tasty (TestTree, testGroup)

import qualified Plutus.V1.Ledger.Interval as I
import Plutus.V1.Ledger.Time (POSIXTime(..), POSIXTimeRange)

import qualified Plutus.V1.Ledger.Address as Addr
import Cardano.Ledger.Alonzo.Language (Language(..))

import Plutus.V2.Ledger.Tx (TxOut(..)) -- gives record field txOutValue

import Plutus.Model
  ( Run
  , MockConfig
  , defaultBabbage
  , testNoErrors
  , mustFail
  , newUser
  , spend
  , submitTx
  , utxoAt
  , validateIn
  , valueAt
  , waitUntil
  , adaValue
  , adaOf
  , asAda
  , getLovelace
  , DatumMode (HashDatum)
  , payToScript
  , spendScript
  , userSpend
  , payToKey
  , HasAddress(..)
  , HasDatum(..)
  , HasRedeemer(..)
  , HasLanguage(..)
  , HasValidator(..)
  , FailReason(..)
  , pureFail
  , validatorHash
  )

import PublicFundReleaseContract
  ( FundDatum(..)
  , FundRedeemer(..)
  , validator
  )

--------------------------------------------------------------------------------
-- Script type for plutus-simple-model
--------------------------------------------------------------------------------

data PFR = PFR

instance HasValidator PFR where
  toValidator _ = validator

instance HasDatum PFR where
  type DatumType PFR = FundDatum

instance HasRedeemer PFR where
  type RedeemerType PFR = FundRedeemer

instance HasLanguage PFR where
  getLanguage _ = PlutusV2

instance HasAddress PFR where
  toAddress s = Addr.scriptHashAddress (validatorHash s)

pfrScript :: PFR
pfrScript = PFR

--------------------------------------------------------------------------------
-- Small helper: fail the Run (so testNoErrors fails) if condition is false
--------------------------------------------------------------------------------

expect :: Bool -> P.String -> Run ()
expect ok msg =
  when (P.not ok) $ void (pureFail (GenericFail msg))

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup "PublicFundRelease (plutus-simple-model)"
    [ release_ok
    , release_fails_notEnough
    , approve_fails_notOfficial
    , approve_fails_duplicate
    , refund_ok
    , refund_fails_tooEarly
    ]
  where
    initialFunds = adaValue 10_000_000
    cfg :: MockConfig
    cfg = defaultBabbage

    locked = adaValue 20

    deadline :: POSIXTime
    deadline = POSIXTime 100_000_000

    beforeDl :: POSIXTimeRange
    beforeDl = I.to deadline

    afterDl :: POSIXTimeRange
    afterDl = I.from (deadline + 1)

    -- deposit -> approve -> approve -> release (should succeed)
    release_ok :: TestTree
    release_ok =
      testNoErrors initialFunds cfg "release succeeds after 2 approvals (before deadline)" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = []
                }

        -- deposit
        sp <- spend depositor locked
        submitTx depositor $
          payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        -- approve 1
        u1 <- utxoAt pfrScript
        expect (P.not (P.null u1)) "no script UTxO after deposit"
        let ((ref1, out1):_) = u1
            vLocked1 = txOutValue out1
            d1 = d0 { fdApprovals = [off1] }

        txA1 <- validateIn beforeDl $
          spendScript pfrScript ref1 (Approve off1) d0 <>
          payToScript pfrScript (HashDatum d1) vLocked1
        submitTx off1 txA1

        -- approve 2
        u2 <- utxoAt pfrScript
        expect (P.not (P.null u2)) "no script UTxO after approve 1"
        let ((ref2, out2):_) = u2
            vLocked2 = txOutValue out2
            d2 = d1 { fdApprovals = [off2, off1] }

        txA2 <- validateIn beforeDl $
          spendScript pfrScript ref2 (Approve off2) d1 <>
          payToScript pfrScript (HashDatum d2) vLocked2
        submitTx off2 txA2

        -- release
        u3 <- utxoAt pfrScript
        expect (P.not (P.null u3)) "no script UTxO after approve 2"
        let ((ref3, out3):_) = u3
            vLocked3 = txOutValue out3
        
        -- beneficiary balance BEFORE release (in lovelace)
        vBen0 <- valueAt beneficiary
        let ben0 = getLovelace (adaOf vBen0)

        txR <- validateIn beforeDl $
          spendScript pfrScript ref3 Release d2 <>
          payToKey beneficiary vLocked3
        submitTx depositor txR

        -- checks: script should be empty and beneficiary should have >= 1000 + 20 ADA
        uAfter <- utxoAt pfrScript
        expect (P.null uAfter) "script UTxO not consumed by release"

        vBen1 <- valueAt beneficiary
        let ben1 = getLovelace (adaOf vBen1)
            want = getLovelace (adaOf vLocked3)
        expect (ben1 P.>= ben0 + want) "beneficiary did not receive released funds"

    -- release should fail if approvals < required
    release_fails_notEnough :: TestTree
    release_fails_notEnough =
      testNoErrors initialFunds cfg "release fails with not enough approvals" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = [off1] -- only 1
                }

        sp <- spend depositor locked
        submitTx depositor $ payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        u <- utxoAt pfrScript
        let ((ref, out):_) = u
            vLocked = txOutValue out

        txR <- validateIn beforeDl $
          spendScript pfrScript ref Release d0 <>
          payToKey beneficiary vLocked

        mustFail (submitTx beneficiary txR)

    -- approve should fail if signer is not in officials
    approve_fails_notOfficial :: TestTree
    approve_fails_notOfficial =
      testNoErrors initialFunds cfg "approve fails when signer is not an official" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)
        outsider    <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = []
                }

        sp <- spend depositor locked
        submitTx depositor $ payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        u <- utxoAt pfrScript
        let ((ref, out):_) = u
            vLocked = txOutValue out
            d1 = d0 { fdApprovals = [outsider] }

        txA <- validateIn beforeDl $
          spendScript pfrScript ref (Approve outsider) d0 <>
          payToScript pfrScript (HashDatum d1) vLocked

        mustFail (submitTx outsider txA)

    -- approve should fail if same official approves twice
    approve_fails_duplicate :: TestTree
    approve_fails_duplicate =
      testNoErrors initialFunds cfg "approve fails when approval is duplicated" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = [off1]
                }

        sp <- spend depositor locked
        submitTx depositor $ payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        u <- utxoAt pfrScript
        let ((ref, out):_) = u
            vLocked = txOutValue out
            d1 = d0 { fdApprovals = [off1, off1] }

        txA <- validateIn beforeDl $
          spendScript pfrScript ref (Approve off1) d0 <>
          payToScript pfrScript (HashDatum d1) vLocked

        mustFail (submitTx off1 txA)

    -- refund succeeds after deadline when approvals < required
    refund_ok :: TestTree
    refund_ok =
      testNoErrors initialFunds cfg "refund succeeds after deadline if approvals < required" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = [off1]
                }

        sp <- spend depositor locked
        submitTx depositor $ payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        waitUntil (deadline + 1)

        u <- utxoAt pfrScript
        let ((ref, out):_) = u
            vLocked = txOutValue out

        txF <- validateIn afterDl $
          spendScript pfrScript ref Refund d0 <>
          payToKey depositor vLocked
        submitTx depositor txF

        uAfter <- utxoAt pfrScript
        expect (P.null uAfter) "script UTxO not consumed by refund"

    -- refund fails before deadline
    refund_fails_tooEarly :: TestTree
    refund_fails_tooEarly =
      testNoErrors initialFunds cfg "refund fails before deadline" $ do
        depositor   <- newUser (adaValue 1_000)
        beneficiary <- newUser (adaValue 1_000)
        off1        <- newUser (adaValue 1_000)
        off2        <- newUser (adaValue 1_000)

        let d0 =
              FundDatum
                { fdDepositor   = depositor
                , fdBeneficiary = beneficiary
                , fdOfficials   = [off1, off2]
                , fdRequired    = 2
                , fdDeadline    = deadline
                , fdApprovals   = []
                }

        sp <- spend depositor locked
        submitTx depositor $ payToScript pfrScript (HashDatum d0) locked <> userSpend sp

        u <- utxoAt pfrScript
        let ((ref, out):_) = u
            vLocked = txOutValue out

        txF <- validateIn beforeDl $
          spendScript pfrScript ref Refund d0 <>
          payToKey depositor vLocked

        mustFail (submitTx depositor txF)
