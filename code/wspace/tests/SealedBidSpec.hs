{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}


module SealedBidSpec
  ( tests
  ) where

import Prelude (Integer, ($), IO)
import qualified Prelude as P

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Plutus.V2.Ledger.Api
  ( PubKeyHash(..)
  , POSIXTime(..)
  , CurrencySymbol(..)
  , TokenName(..)
  )
import qualified PlutusTx.Builtins as Builtins
import           PlutusTx.Builtins (BuiltinByteString)

import qualified Data.ByteString.Char8 as BSC

-- 🔴 Import your contract module here (not Main)
import SealedBidContract
  ( CommitDatum(..)
  , AuctionRedeemer(..)
  , bidHash
  )

------------------------------------------------------------------------
-- Helpers (pure)
------------------------------------------------------------------------

dummyBidder :: PubKeyHash
dummyBidder = PubKeyHash (Builtins.toBuiltin (BSC.pack "bidder-pkh"))

dummySeller :: PubKeyHash
dummySeller = PubKeyHash (Builtins.toBuiltin (BSC.pack "seller-pkh"))

dummyDeadline :: POSIXTime
dummyDeadline = POSIXTime 1_000_000

dummyCurrency :: CurrencySymbol
dummyCurrency = CurrencySymbol (Builtins.toBuiltin (BSC.pack "deadbeef"))

dummyToken :: TokenName
dummyToken = TokenName (Builtins.toBuiltin (BSC.pack "NFT-Token"))

mkCommitDatum :: BuiltinByteString -> CommitDatum
mkCommitDatum h =
  CommitDatum
    { cdBidder         = dummyBidder
    , cdSeller         = dummySeller
    , cdCommitHash     = h
    , cdDeadlineReveal = dummyDeadline
    , cdCurrency       = dummyCurrency
    , cdToken          = dummyToken
    }

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Sealed-bid commit–reveal auction"
  [ testBidHashDeterministic
  , testBidHashChangesWithAmount
  , testBidHashChangesWithSalt
  , testCommitDatumStoresCommitHash
  ]

testBidHashDeterministic :: TestTree
testBidHashDeterministic =
  testCase "bidHash is deterministic for same (amount, salt)" $ do
    let amount = 100 :: Integer
        salt   = Builtins.toBuiltin (BSC.pack "my-salt")
        h1     = bidHash amount salt
        h2     = bidHash amount salt
    h1 @?= h2

testBidHashChangesWithAmount :: TestTree
testBidHashChangesWithAmount =
  testCase "bidHash changes when amount changes (same salt)" $ do
    let salt = Builtins.toBuiltin (BSC.pack "same-salt")
        h1   = bidHash 100 salt
        h2   = bidHash 200 salt
    assertBool "hashes should differ when amounts differ" (h1 P./= h2)

testBidHashChangesWithSalt :: TestTree
testBidHashChangesWithSalt =
  testCase "bidHash changes when salt changes (same amount)" $ do
    let amount = 100 :: Integer
        h1     = bidHash amount (Builtins.toBuiltin (BSC.pack "salt-1"))
        h2     = bidHash amount (Builtins.toBuiltin (BSC.pack "salt-2"))
    assertBool "hashes should differ when salts differ" (h1 P./= h2)

testCommitDatumStoresCommitHash :: TestTree
testCommitDatumStoresCommitHash =
  testCase "CommitDatum stores bidHash(amount, salt) correctly" $ do
    let amount      = 150 :: Integer
        salt        = Builtins.toBuiltin (BSC.pack "secret-salt")
        hCommitment = bidHash amount salt
        dat         = mkCommitDatum hCommitment
    cdCommitHash dat @?= hCommitment
