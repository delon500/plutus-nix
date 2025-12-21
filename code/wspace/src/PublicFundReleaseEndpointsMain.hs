{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE NumericUnderscores #-}

module Main where

import Prelude
  ( IO, String, putStrLn
  , ($), (.), (<>)
  , show, either
  )
import qualified Prelude as P

import Control.Monad (void)
import System.Environment (getArgs)

import Plutus.Trace.Emulator as Emulator
import Wallet.Emulator.Wallet (Wallet, knownWallet, mockWalletPaymentPubKeyHash)

import Ledger (unPaymentPubKeyHash)
import Plutus.V2.Ledger.Api (POSIXTime, PubKeyHash)

import Ledger.TimeSlot (slotToEndPOSIXTime)
import Data.Default (def)

import PublicFundReleaseEndpoints (endpoints, DepositParams(..))

-- Helpers: Wallet -> PubKeyHash
wPKH :: Wallet -> PubKeyHash
wPKH = unPaymentPubKeyHash . mockWalletPaymentPubKeyHash

-- Demo 1: deposit -> approve -> approve -> release (before deadline)
traceRelease :: EmulatorTrace ()
traceRelease = do
  let wDepositor   = knownWallet 1
      wBeneficiary = knownWallet 2
      wOff1        = knownWallet 3
      wOff2        = knownWallet 4

      -- Deadline at slot 30 (comfortably in the future for this trace)
      deadline :: POSIXTime
      deadline = slotToEndPOSIXTime def 30

      dp = DepositParams
            { dpBeneficiary = wPKH wBeneficiary
            , dpOfficials   = [wPKH wOff1, wPKH wOff2]
            , dpRequired    = 2
            , dpDeadline    = deadline
            , dpLovelace    = 20_000_000 -- 20 ADA
            }

  hDep <- activateContractWallet wDepositor endpoints
  hO1  <- activateContractWallet wOff1 endpoints
  hO2  <- activateContractWallet wOff2 endpoints
  hBen <- activateContractWallet wBeneficiary endpoints

  callEndpoint @"deposit" hDep dp
  void $ waitNSlots 2

  callEndpoint @"approve" hO1 ()
  void $ waitNSlots 2

  callEndpoint @"approve" hO2 ()
  void $ waitNSlots 2

  callEndpoint @"release" hBen ()
  void $ waitNSlots 2

-- Demo 2: deposit -> wait past deadline -> refund (after deadline)
traceRefund :: EmulatorTrace ()
traceRefund = do
  let wDepositor   = knownWallet 1
      wBeneficiary = knownWallet 2
      wOff1        = knownWallet 3
      wOff2        = knownWallet 4

      -- Deadline at slot 10, then we wait until slot 12+ before refund
      deadline :: POSIXTime
      deadline = slotToEndPOSIXTime def 10

      dp = DepositParams
            { dpBeneficiary = wPKH wBeneficiary
            , dpOfficials   = [wPKH wOff1, wPKH wOff2]
            , dpRequired    = 2
            , dpDeadline    = deadline
            , dpLovelace    = 20_000_000 -- 20 ADA
            }

  hDep <- activateContractWallet wDepositor endpoints

  callEndpoint @"deposit" hDep dp
  void $ waitNSlots 1

  -- Ensure we've passed the deadline
  void $ waitUntilSlot 12

  callEndpoint @"refund" hDep ()
  void $ waitNSlots 2

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["release"] -> runEmulatorTraceIO traceRelease
    ["refund"]  -> runEmulatorTraceIO traceRefund
    _ -> do
      putStrLn "Usage:"
      putStrLn "  cabal run public-fund-release-endpoints-exe -- release"
      putStrLn "  cabal run public-fund-release-endpoints-exe -- refund"