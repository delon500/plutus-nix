    {-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Main where

import Prelude (IO, FilePath, String, putStrLn, (<>))
import qualified Prelude as P
import qualified Data.Text as T

-- Plutus core
import Plutus.V2.Ledger.Api
  ( Validator
  , Address(..)
  , Credential(..)
  )
import qualified Plutus.V2.Ledger.Api as PlutusV2
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins

-- Serialization
import qualified Codec.Serialise       as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
import qualified Data.ByteString       as BS

-- Cardano API (for Bech32 address & text envelope)
import qualified Cardano.Api          as C
import qualified Cardano.Api.Shelley  as CS

-- Our on-chain contract
import SportsTicketsContract (validator)

----------------------------------------------------------------------
-- Plutus-style hash & address
----------------------------------------------------------------------

plutusValidatorHash :: PlutusV2.Validator -> PlutusV2.ValidatorHash
plutusValidatorHash v =
  let bytes    = Serialise.serialise v        -- lazy ByteString
      strict   = LBS.toStrict bytes           -- ByteString
      short    = SBS.toShort strict           -- ShortByteString
      strictBS = SBS.fromShort short          -- back to ByteString
      builtin  = Builtins.toBuiltin strictBS  -- BuiltinByteString
  in PlutusV2.ValidatorHash builtin

plutusScriptAddress :: PlutusV2.Address
plutusScriptAddress =
  Address (ScriptCredential (plutusValidatorHash validator)) Nothing

----------------------------------------------------------------------
-- Bech32 script address via cardano-api
----------------------------------------------------------------------

toBech32ScriptAddress :: C.NetworkId -> Validator -> String
toBech32ScriptAddress network val =
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      scriptHash :: C.ScriptHash
      scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)

      shelleyAddr :: C.AddressInEra C.BabbageEra
      shelleyAddr =
        C.makeShelleyAddressInEra
          network
          (C.PaymentCredentialByScript scriptHash)
          C.NoStakeAddress
  in T.unpack (C.serialiseAddress shelleyAddr)

----------------------------------------------------------------------
-- Write text-envelope .plutus file
----------------------------------------------------------------------

-- | Writes the validator as a Cardano text-envelope Plutus script (.plutus),
-- which is what `cardano-cli --script-file` expects.
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      -- In this cardano-api version 'TextEnvelopeDescr' is just a type alias,
      -- so a plain string literal works with OverloadedStrings.
      description :: C.TextEnvelopeDescr
      description = "Sports Tickets Plutus Validator"

  result <- C.writeFileTextEnvelope path (Just description) plutusScript
  case result of
    Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
    Right ()  -> putStrLn $ "Validator written to: " <> path

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

main :: IO ()
main = do
  let network = C.Testnet (C.NetworkMagic 1)

  -- Produce sports-tickets.plutus (text envelope with description)
  writeValidator "sports-tickets.plutus" validator

  let vh      = plutusValidatorHash validator
      onchain = plutusScriptAddress
      bech32  = toBech32ScriptAddress network validator

  putStrLn "\n--- Sports Tickets Validator Info ---"
  putStrLn $ "Validator Hash (Plutus): " <> P.show vh
  putStrLn $ "Plutus Script Address:    " <> P.show onchain
  putStrLn $ "Bech32 Script Address:    " <> bech32
  putStrLn "--------------------------------------"
  putStrLn "Sports tickets validator generated successfully."
