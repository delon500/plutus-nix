{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE DerivingStrategies  #-}

module SportsTicketsPolicySpec
  ( sportsTicketsPolicyTests
  , tests
  ) where

import Prelude (Show(..), Eq(..), ($), (.), (++), (<>))
import qualified Prelude               as P

import Test.Tasty
import Test.Tasty.HUnit

import PlutusTx.Prelude hiding (Semigroup(..), unless, ($))
import qualified PlutusTx.Builtins     as Builtins

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Value    as Value
import qualified Plutus.V1.Ledger.Interval as I
import qualified PlutusTx.AssocMap         as AMap

import qualified Data.ByteString.Char8     as BSC

-- 🔹 This is the *import* of your policy module (not a second module header)
import SportsTicketsPolicy
  ( TicketMintParams(..)
  , TicketMintRedeemer(..)
  , mkTicketPolicy
  )

--------------------------------------------------------------------------------
-- Helpers / constants
--------------------------------------------------------------------------------

dummyTxId :: V2.TxId
dummyTxId =
  V2.TxId (Builtins.toBuiltin (BSC.pack "dummy-tx-id"))

-- Dummy CurrencySymbol that represents "our" ticket policy in tests
dummyCs :: V2.CurrencySymbol
dummyCs =
  V2.CurrencySymbol (Builtins.toBuiltin (BSC.pack "sports-tickets-policy"))

orgPkh, otherPkh :: V2.PubKeyHash
orgPkh   = V2.PubKeyHash (Builtins.toBuiltin (BSC.pack "organizer-wallet"))
otherPkh = V2.PubKeyHash (Builtins.toBuiltin (BSC.pack "other-wallet"))

-- Seat IDs as BuiltinByteString
seat1, seat2 :: BuiltinByteString
seat1 = Builtins.toBuiltin (BSC.pack "BLOCK-A-ROW-1-SEAT-10")
seat2 = Builtins.toBuiltin (BSC.pack "BLOCK-A-ROW-1-SEAT-11")

-- Base params used in most tests
baseParams :: TicketMintParams
baseParams =
  TicketMintParams
    { tmpOrganizer = orgPkh
    , tmpEventId   = Builtins.toBuiltin (BSC.pack "EVENT-001")
    }

-- Build a ScriptContext for a minting transaction:
--  * txInfoMint = given Value
--  * txInfoSignatories = given signers
--  * purpose = Minting dummyCs
mkMintCtx :: Value.Value -> [V2.PubKeyHash] -> V2.ScriptContext
mkMintCtx minted signers =
  let info =
        V2.TxInfo
          { V2.txInfoInputs          = []
          , V2.txInfoReferenceInputs = []
          , V2.txInfoOutputs         = []
          , V2.txInfoFee             = mempty
          , V2.txInfoMint            = minted
          , V2.txInfoDCert           = []
          , V2.txInfoWdrl            = AMap.empty
          , V2.txInfoValidRange      = I.always
          , V2.txInfoSignatories     = signers
          , V2.txInfoRedeemers       = AMap.empty
          , V2.txInfoData            = AMap.empty
          , V2.txInfoId              = dummyTxId
          }
      purpose = V2.Minting dummyCs
  in V2.ScriptContext info purpose

--------------------------------------------------------------------------------
-- Test tree
--------------------------------------------------------------------------------

sportsTicketsPolicyTests :: TestTree
sportsTicketsPolicyTests =
  testGroup "SportsTicketsPolicy (NFT minting)"
    [ mintTests
    , burnTests
    ]

-- For Spec.hs convenience
tests :: TestTree
tests = sportsTicketsPolicyTests

--------------------------------------------------------------------------------
-- MintTicket tests
--------------------------------------------------------------------------------

mintTests :: TestTree
mintTests =
  testGroup "MintTicket"
    [ testCase "organiser-signed, correct +1 mint" $
        assertBool "expected mint to pass" validMint

    , testCase "missing organiser signature fails" $
        assertBool "expected policy to fail" (P.not organiserMissing)

    , testCase "wrong amount (2 instead of 1) fails" $
        assertBool "expected policy to fail" (P.not wrongAmountMint)

    , testCase "extra NFTs under same policy fails" $
        assertBool "expected policy to fail" (P.not extraTokensUnderPolicy)
    ]
  where
    tn1 :: Value.TokenName
    tn1 = Value.TokenName seat1

    tn2 :: Value.TokenName
    tn2 = Value.TokenName seat2

    -- Happy path: mint exactly 1 NFT for seat1, organiser signs.
    validMint :: P.Bool
    validMint =
      let val = Value.singleton dummyCs tn1 1
          ctx = mkMintCtx val [orgPkh]
          red = MintTicket seat1
      in mkTicketPolicy baseParams red ctx

    -- No organiser in signatories => should fail.
    organiserMissing :: P.Bool
    organiserMissing =
      let val = Value.singleton dummyCs tn1 1
          ctx = mkMintCtx val [otherPkh]
          red = MintTicket seat1
      in mkTicketPolicy baseParams red ctx

    -- Minting 2 instead of 1 => violates checkMint seat 1.
    wrongAmountMint :: P.Bool
    wrongAmountMint =
      let val = Value.singleton dummyCs tn1 2
          ctx = mkMintCtx val [orgPkh]
          red = MintTicket seat1
      in mkTicketPolicy baseParams red ctx

    -- Minting two different NFTs under the same CurrencySymbol
    -- => violates noExtraUnderPolicy.
    extraTokensUnderPolicy :: P.Bool
    extraTokensUnderPolicy =
      let val =  Value.singleton dummyCs tn1 1
             <> Value.singleton dummyCs tn2 1
          ctx = mkMintCtx val [orgPkh]
          red = MintTicket seat1
      in mkTicketPolicy baseParams red ctx

--------------------------------------------------------------------------------
-- BurnTicket tests
--------------------------------------------------------------------------------

burnTests :: TestTree
burnTests =
  testGroup "BurnTicket"
    [ testCase "organiser-signed, -1 burn passes" $
        assertBool "expected burn to pass" validBurn

    , testCase "burn with wrong amount fails" $
        assertBool "expected policy to fail" (P.not wrongAmountBurn)

    , testCase "burn without organiser signature fails" $
        assertBool "expected policy to fail" (P.not burnNoOrganiser)
    ]
  where
    tn1 :: Value.TokenName
    tn1 = Value.TokenName seat1

    -- Happy path: burn exactly -1 of seat1, organiser signs.
    validBurn :: P.Bool
    validBurn =
      let val = Value.singleton dummyCs tn1 (-1)
          ctx = mkMintCtx val [orgPkh]
          red = BurnTicket seat1
      in mkTicketPolicy baseParams red ctx

    -- Burning wrong amount (e.g. 0) => should fail.
    wrongAmountBurn :: P.Bool
    wrongAmountBurn =
      let val = Value.singleton dummyCs tn1 0
          ctx = mkMintCtx val [orgPkh]
          red = BurnTicket seat1
      in mkTicketPolicy baseParams red ctx

    -- Correct -1 amount but organiser not in signatories => should fail.
    burnNoOrganiser :: P.Bool
    burnNoOrganiser =
      let val = Value.singleton dummyCs tn1 (-1)
          ctx = mkMintCtx val [otherPkh]
          red = BurnTicket seat1
      in mkTicketPolicy baseParams red ctx
