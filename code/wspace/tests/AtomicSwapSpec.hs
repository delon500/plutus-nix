{-# LANGUAGE OverloadedStrings #-}
module AtomicSwapSpec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertFailure, (@?=))

-- We'll fill these tests in using plutus-simple-model to build fake chains/txs.
-- For now they document required validator behavior and will become real soon.

tests :: TestTree
tests = testGroup "AtomicSwap" 
    [ -- 1. CANCEL: happy path
        testCase "Cancel succeeds after deadline with seller signature and full refund" $ do
            -- GIVEN:
            --   * Listing UTxO with SwapDatum:
            --       sdSeller    = sellerCred
            --       sdOffer     = offerValue
            --       sdDeadline  = t_deadline
            --   * Tx:
            --       - validRange starts at/after t_deadline
            --       - signed by sellerCred
            --       - consumes that listing UTxO
            --       - pays offerValue back exactly to seller address
            --
            -- EXPECT:
            --   Validation should SUCCEED.
            --
            -- TODO: model tx and assert success.
        pure ()
    , -- 2. CANCEL: too early 
        testCase "Cancel fails before deadline" $ do
            -- Same setup BUT:
            --   * tx validRange is strictly before sdDeadline.
            --
            -- EXPECT:
            --   Validation should FAIL (not allowed to cancel yet).
            --
            -- TODO: model tx and assert failure.
        pure ()
    , -- 3. CANCEL: Unauthorized
        testCase "Cancel fails without seller signature" $ do
            --  Setup:
            --   * tx is NOT signed by sdSeller.
            --   * The tx is NOT signed by sdSeller.
            --
            -- EXPECT:
            --   Validation should FAIL (only seller can cancel).
            --
            -- TODO: model tx and assert failure.
        pure ()
    , -- 4. CANCEL: value leakage
        testCase "Cancel fails if refund amount != full sdOffer" $ do
            --  Setup:
            --   * After deadline
            --   * Seller DID sign
            --   * Tx consumes listing 
            --   * BUT tx output gives seller only of sdOffer, or routes some of sdOffer to any other address.
            --
            -- EXPECT:
            --   Validation should FAIL (full refund required) (no value leakage).
            --
            -- TODO: model tx and assert failure.
        pure ()
    ]