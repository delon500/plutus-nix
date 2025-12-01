{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Main where

import Prelude (IO, FilePath, String, putStrLn, (<>))
import qualified Prelude as P
import qualified Data.Text as T
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
import qualified Data.ByteString.Char8 as BSC

-- Plutus core
import qualified Plutus.V2.Ledger.Api as V2
import           PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins

-- Serialization
import qualified Codec.Serialise as Serialise

-- Cardano API (for text envelope)
import qualified Cardano.Api         as C
import qualified Cardano.Api.Shelley as CS

-- Our minting policy
import SportsTicketsPolicy
  ( TicketMintParams(..)
  , ticketPolicy
  )

--------------------------------------------------------------------------------
-- Parameters for this policy
--------------------------------------------------------------------------------

-- TODO: Replace this with the actual organiser PubKeyHash bytes
organizerPkh :: V2.PubKeyHash
organizerPkh =
  let bs = Builtins.toBuiltin (BSC.pack "organizer-wallet")
  in V2.PubKeyHash bs

params :: TicketMintParams
params =
  TicketMintParams
    { tmpOrganizer = organizerPkh
    , tmpEventId   = "EVENT-001"
    }

policy :: V2.MintingPolicy
policy = ticketPolicy params

--------------------------------------------------------------------------------
-- Write text-envelope .plutus file
--------------------------------------------------------------------------------

writePolicy :: FilePath -> V2.MintingPolicy -> IO ()
writePolicy path pol = do
  let script     :: V2.Script
      script      = V2.unMintingPolicyScript pol

      serialised :: SBS.ShortByteString
      serialised  = SBS.toShort . LBS.toStrict $ Serialise.serialise script

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      description :: C.TextEnvelopeDescr
      description = "Sports Tickets Minting Policy"

  result <- C.writeFileTextEnvelope path (Just description) plutusScript
  case result of
    Left err  -> putStrLn $ "Error writing minting policy: " <> C.displayError err
    Right ()  -> putStrLn $ "Minting policy written to: " <> path

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

main :: IO ()
main = do
  -- Use Testnet (network magic 1) just like your other writers
  let network = C.Testnet (C.NetworkMagic 1)

  -- 1) Write sports-tickets-policy.plutus
  writePolicy "sports-tickets-policy.plutus" policy

  -- 2) Compute / print script hash (this becomes the PolicyId on-chain)
  let script      = V2.unMintingPolicyScript policy
      serialised  = SBS.toShort . LBS.toStrict $ Serialise.serialise script
      plutusScript = CS.PlutusScriptSerialised serialised
      scriptHash  = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)
      policyId    = C.PolicyId scriptHash

  putStrLn "\n--- Sports Tickets Minting Policy Info ---"
  putStrLn $ "Script Hash: " <> P.show scriptHash
  putStrLn $ "Policy Id:   " <> P.show policyId
  putStrLn "------------------------------------------"
  putStrLn "Sports tickets minting policy generated successfully."
