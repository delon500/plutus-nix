# SealedBid.hs – Beginner Tutorial / Documentation

## Table of Contents

- [SealedBid.hs – Beginner Tutorial / Documentation](#sealedbidhs--beginner-tutorial--documentation)
  - [Table of Contents](#table-of-contents)
  - [1. Overview](#1-overview)
  - [2. What Problem This Contract Solves](#2-what-problem-this-contract-solves)
  - [3. High-Level Flow (Commit → Reveal / Refund)](#3-high-level-flow-commit--reveal--refund)
    - [3.1 Commit phase (off-chain pattern)](#31-commit-phase-off-chain-pattern)
    - [3.2 Reveal branch (on-chain)](#32-reveal-branch-on-chain)
    - [3.3 Refund branch (on-chain)](#33-refund-branch-on-chain)
  - [4. On-Chain Data Types](#4-on-chain-data-types)
    - [4.1 `CommitDatum`](#41-commitdatum)
    - [4.2 `AuctionRedeemer`](#42-auctionredeemer)
    - [4.3 `bidHash`](#43-bidhash)
  - [5. Language Extensions (Why they’re here)](#5-language-extensions-why-theyre-here)
    - [5.1 `DataKinds`](#51-datakinds)
    - [5.2 `NoImplicitPrelude`](#52-noimplicitprelude)
    - [5.3 `TemplateHaskell`](#53-templatehaskell)
    - [5.4 `ScopedTypeVariables`](#54-scopedtypevariables)
    - [5.5 `OverloadedStrings`](#55-overloadedstrings)
    - [5.6 `TypeApplications`](#56-typeapplications)
  - [6. Imports (What each one is for)](#6-imports-what-each-one-is-for)
    - [6.1 `module Main where`](#61-module-main-where)
    - [6.2 `Prelude` and `qualified Prelude as P`](#62-prelude-and-qualified-prelude-as-p)
    - [6.3 Plutus core imports](#63-plutus-core-imports)
    - [6.4 Serialization stack](#64-serialization-stack)
    - [6.5 Cardano API imports](#65-cardano-api-imports)
  - [7. Validation Logic](#7-validation-logic)
    - [7.1 Shared helpers](#71-shared-helpers)
      - [`ownInput` and `inputAda`](#owninput-and-inputada)
    - [7.2 Reveal branch](#72-reveal-branch)
    - [7.3 Refund branch](#73-refund-branch)
  - [8. Producing `sealed-bid-commit-reveal-nft.plutus`](#8-producing-sealed-bid-commit-reveal-nftplutus)
  - [9. Testing the Contract](#9-testing-the-contract)
    - [9.1 What `SealedBidSpec` tests](#91-what-sealedbidspec-tests)
    - [9.2 Running the tests](#92-running-the-tests)
  - [10. Glossary of Terms](#10-glossary-of-terms)
    - [10.1 Sealed-bid auction](#101-sealed-bid-auction)
    - [10.2 Commit–reveal](#102-commitreveal)
    - [10.3 Commitment hash](#103-commitment-hash)
    - [10.4 Salt](#104-salt)
    - [10.5 Datum (`CommitDatum`)](#105-datum-commitdatum)
    - [10.6 Redeemer (`AuctionRedeemer`)](#106-redeemer-auctionredeemer)
    - [10.7 Script UTxO](#107-script-utxo)
    - [10.8 Validator](#108-validator)
    - [10.9 Script address](#109-script-address)
    - [10.10 Text envelope (`.plutus` file)](#1010-text-envelope-plutus-file)
    - [10.11 How these concepts connect (flow diagram)](#1011-how-these-concepts-connect-flow-diagram)

---

## 1. Overview

`SealedBid.hs` is a Plutus V2 validator that implements a **sealed-bid commit–reveal auction UTxO** for an NFT.

Each UTxO at this script represents **one committed bid**:

* The **bidder** locks some ADA at the script and stores a **hash of (amount, salt)** in the datum (the actual bid amount is hidden).
* Later, the bidder can:

  * **Reveal** the bid (before a deadline), paying ADA to the **seller** and receiving the NFT.
  * Or **Refund** (after the deadline), recovering their committed ADA if they don’t (or can’t) reveal.

The sealed-bid property comes from the fact that the amount is only known as a **commitment hash** until the bidder reveals `(amount, salt)`.

> 💡 This contract is *per-commitment*: it enforces correct reveal/refund for one bidder’s commitment.
> Selection of “highest bid wins” is handled off-chain by the dApp logic that chooses which Reveal transaction to submit.

---

## 2. What Problem This Contract Solves

On a transparent UTxO blockchain, if you just publish your bid as a value in a transaction:

> Everyone can see it immediately and potentially out-bid you.

A **sealed-bid commit–reveal** scheme solves this:

1. **Commit phase**

   * Bidder posts a transaction locking funds and a *hash* of their bid (amount + secret salt).
   * No one can see the actual amount, just the hash.

2. **Reveal phase**

   * After the commit phase and before a reveal deadline, bidders reveal `(amount, salt)`.
   * The contract recomputes the hash and checks it matches the committed one.

3. **Settlement / Refunds**

   * Off-chain logic picks which revealed bid should win (usually highest).
   * Winning bidder’s Reveal transaction:
     * pays the seller,
     * transfers the NFT to the bidder.
   * Losers (or non-revealers) get refunds after the deadline.

`SealedBid.hs` enforces the **on-chain rules** for:

* verifying commitments,
* enforcing timing (before/after deadline),
* ensuring correct ADA / NFT flows for reveal & refund.

---

## 3. High-Level Flow (Commit → Reveal / Refund)

The validator only sees **Reveal** or **Refund**.
The **Commit** step is just “send a UTxO with a suitable datum to this script address”.

### 3.1 Commit phase (off-chain pattern)

Off-chain, to **commit a bid**:

1. Compute:

   ```haskell
   commitHash = bidHash amount salt
   ```

2. Build a `CommitDatum`:

   ```haskell
   CommitDatum
     { cdBidder         = bidderPkh
     , cdSeller         = sellerPkh
     , cdCommitHash     = commitHash
     , cdDeadlineReveal = someDeadline
     , cdCurrency       = nftCurrency
     , cdToken          = nftToken
     }
   ```

3. Lock a UTxO at the script address with:

   * Value: bidder’s ADA (e.g. “max they’re willing to pay” or exactly `amount`).
   * Datum: the `CommitDatum` above.
   * No validator execution yet: it’s just creating the script UTxO.

### 3.2 Reveal branch (on-chain)

When the bidder wants to settle as the **winner**:

* They build a transaction that:

  * spends their committed UTxO from the script,
  * includes a **Reveal amount salt** redeemer,
  * pays at least `amount` ADA to the seller,
  * sends the NFT to the bidder.

The validator checks:

* The bid was revealed **before** `cdDeadlineReveal`.
* The `(amount, salt)` matches `cdCommitHash`.
* The seller receives at least `amount` ADA.
* The bidder receives at least 1 unit of the NFT.

If all conditions hold → Reveal branch passes.

### 3.3 Refund branch (on-chain)

After the reveal deadline:

* If the bidder did not (or cannot) reveal, they can take the **Refund path**:

The transaction:

* spends the script UTxO with redeemer `Refund`,
* is valid strictly **after** the reveal deadline,
* returns at least the committed ADA back to the bidder.

The validator enforces:

* Bidder signed the transaction.
* Time is after deadline.
* Bidder gets at least `inputAda` (the ADA originally locked in that commit UTxO).

---

## 4. On-Chain Data Types

### 4.1 `CommitDatum`

```haskell
data CommitDatum = CommitDatum
    { cdBidder         :: PubKeyHash          -- bidder who owns this commitment
    , cdSeller         :: PubKeyHash          -- seller who will receive the ADA
    , cdCommitHash     :: BuiltinByteString   -- hash of (amount, salt)
    , cdDeadlineReveal :: POSIXTime           -- reveal deadline
    , cdCurrency       :: CurrencySymbol      -- NFT currency symbol
    , cdToken          :: TokenName           -- NFT token name
    }
PlutusTx.unstableMakeIsData ''CommitDatum
```

* **`cdBidder`**

  * The public key hash that:

    * is allowed to **reveal** this bid,
    * is allowed to **refund** it after the deadline.

* **`cdSeller`**

  * The seller’s public key hash:

    * `Reveal` branch checks that seller is paid at least the revealed bid amount.

* **`cdCommitHash`**

  * A `BuiltinByteString` storing `sha2_256(serialiseData (amount, salt))`.
  * Hides the bid amount until the bidder reveals.

* **`cdDeadlineReveal`**

  * A POSIX timestamp.
  * Before this: bidder can reveal.
  * After this: bidder can refund.

* **`cdCurrency`, `cdToken`**

  * Identify the **NFT** being auctioned:

    * `cdCurrency :: CurrencySymbol`
    * `cdToken    :: TokenName`
  * `Reveal` branch ensures the bidder receives this NFT.

### 4.2 `AuctionRedeemer`

```haskell
data AuctionRedeemer
    = Reveal Integer BuiltinByteString
    | Refund
PlutusTx.unstableMakeIsData ''AuctionRedeemer
```

* **`Reveal amount salt`**

  * Used when the bidder reveals their bid.
  * `amount :: Integer` – the bid value.
  * `salt   :: BuiltinByteString` – secret nonce used in the commitment.
  * Validator recomputes `bidHash amount salt` and compares to `cdCommitHash`.

* **`Refund`**

  * Used when the bidder wants their money back after the deadline (no successful reveal).

### 4.3 `bidHash`

```haskell
{-# INLINABLE bidHash #-}
bidHash :: Integer -> BuiltinByteString -> BuiltinByteString
bidHash amount salt =
    Builtins.sha2_256 $
      Builtins.serialiseData (PlutusTx.toBuiltinData (amount, salt))
```

* Takes an `amount` and `salt`, turns them into on-chain `Data`, serialises, hashes with `sha2_256`.
* This is what is committed in `cdCommitHash`.

Properties:

* **Deterministic**:
  Same `(amount, salt)` → same hash.
* **Pre-image resistant**:
  Given just the hash, you cannot figure out `(amount, salt)` on-chain.

---

## 5. Language Extensions (Why they’re here)

At the top of `SealedBid.hs`:

```haskell
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}
```

### 5.1 `DataKinds`

* **What it does:**
  Promotes some values (like constructors, strings) to the type level.
* **Why here:**
  Common in Plutus projects (TH-generated code and ledger types can depend on it). It’s a safe default.
* **If removed:**
  Some advanced or generated types may fail in more complex codebases. In this file it’s mostly harmless/safe boilerplate.

### 5.2 `NoImplicitPrelude`

* **What it does:**
  Stops GHC from importing the default `Prelude`.
* **Why here:**
  On-chain code must use `PlutusTx.Prelude` (deterministic and Plutus-compatible).
  We only import from base `Prelude` **explicitly** for off-chain IO stuff.
* **If removed:**
  You might accidentally pull in non-deterministic or unsupported functions into on-chain parts.

### 5.3 `TemplateHaskell`

* **What it does:**
  Enables compile-time metaprogramming (splices like `$(...)`, `$$(...)`).
* **Why here:**

  * `PlutusTx.unstableMakeIsData ''CommitDatum`
  * `PlutusTx.unstableMakeIsData ''AuctionRedeemer`
  * `mkValidatorScript $$(PlutusTx.compile [|| mkValidatorUntyped ||])`
* **If removed:**
  You can’t derive on-chain `IsData` instances or compile your validator to Plutus Core.

### 5.4 `ScopedTypeVariables`

* **What it does:**
  Keeps explicit type variables in scope across the whole function.
* **Why here:**
  Used together with `TypeApplications` in:

  ```haskell
  let dat = unsafeFromBuiltinData @CommitDatum d
      red = unsafeFromBuiltinData @AuctionRedeemer r
      ctx = unsafeFromBuiltinData @ScriptContext   c
  ```

  It helps GHC know exactly which type you’re applying.
* **If removed:**
  You may get ambiguous type errors or need more repetitive annotations.

### 5.5 `OverloadedStrings`

* **What it does:**
  Makes string literals polymorphic (they can be `Text`, `ByteString`, etc.).
* **Why here:**
  For writing things like the text-envelope description:

  ```haskell
  (Just "Sealed-Bid Commit-Reveal NFT Auction Validator")
  ```

  without manual `T.pack` or similar.
* **If removed:**
  You’d need explicit conversions when using string literals for `Text`-like types.

### 5.6 `TypeApplications`

* **What it does:**
  Lets you specify type arguments explicitly using `@Type`.
* **Why here:**

  ```haskell
  unsafeFromBuiltinData @CommitDatum d
  unsafeFromBuiltinData @AuctionRedeemer r
  unsafeFromBuiltinData @ScriptContext c
  ```

  This makes it very clear which type we’re decoding from `BuiltinData`.
* **If removed:**
  You’d need alternative patterns or more verbose type annotations.

---

## 6. Imports (What each one is for)

### 6.1 `module Main where`

This file is an **executable**:

* It defines the validator (on-chain logic).
* It also has a `main :: IO ()` that:

  * writes `sealed-bid-commit-reveal-nft.plutus` (text envelope),
  * prints the script hash & addresses.

### 6.2 `Prelude` and `qualified Prelude as P`

```haskell
import Prelude (IO, String, FilePath, putStrLn, (<>))
import qualified Prelude as P
```

* Because of `NoImplicitPrelude`, base `Prelude` is not imported automatically.
* We selectively import:

  * `IO`, `String`, `FilePath`, `putStrLn`, `( <>)` for **off-chain** work (writing files, printing).
* We also import the rest of `Prelude` as `P` when we need `P.show`, etc.

On-chain logic never uses base `Prelude` directly; it uses `PlutusTx.Prelude`.

### 6.3 Plutus core imports

```haskell
import Plutus.V2.Ledger.Api
import Plutus.V2.Ledger.Contexts
import qualified Plutus.V2.Ledger.Api as PlutusV2
import Plutus.V1.Ledger.Interval as Interval
import Plutus.V1.Ledger.Value (valueOf, adaSymbol, adaToken)
import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins
```

* **`Plutus.V2.Ledger.Api` / `Plutus.V2.Ledger.Contexts`**

  * Types like `ScriptContext`, `TxInfo`, `Validator`, `Address`, `POSIXTime`, etc.
  * Helpers like `scriptContextTxInfo`, `txInInfoResolved`, `txOutValue`, `findOwnInput`, `valuePaidTo`, `txInfoValidRange`.

* **`Plutus.V1.Ledger.Interval as Interval`**

  * Interval functions for time range checking:

    * `Interval.to`, `Interval.from`, `Interval.contains`.

* **`Plutus.V1.Ledger.Value (valueOf, adaSymbol, adaToken)`**

  * `valueOf` – query how much of a given currency/token is in a `Value`.
  * `adaSymbol`, `adaToken` – identify ADA in the multi-asset system.

* **`PlutusTx` + `PlutusTx.Prelude`**

  * `PlutusTx` – TH utilities and `unsafeFromBuiltinData`.
  * `PlutusTx.Prelude` – safe, deterministic on-chain Prelude (Bool, Integer, `(==)`, `(&&)`, `traceIfFalse`, etc.).

* **`PlutusTx.Builtins`**

  * `sha2_256`, `serialiseData`, `toBuiltin`, etc.

### 6.4 Serialization stack

```haskell
import qualified Codec.Serialise as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
```

* `Serialise.serialise validator` → CBOR-encoded bytes of the validator.
* `LBS` + `SBS` used to:

  * convert between lazy / strict / short ByteString types,
  * prepare the script bytes for `Cardano.Api`.

### 6.5 Cardano API imports

```haskell
import qualified Cardano.Api as C
import qualified Cardano.Api.Shelley as CS
```

Used for:

* **Text envelope `.plutus` file**:

  * `C.PlutusScript C.PlutusScriptV2`
  * `C.writeFileTextEnvelope`

* **Address derivation**:

  * `C.hashScript`
  * `C.PaymentCredentialByScript`
  * `C.makeShelleyAddressInEra`
  * `C.serialiseAddress`
  * `C.NetworkId`, `C.Testnet`, `C.NetworkMagic`.

This is the bridge between your Plutus validator and the Cardano CLI ecosystem.

---

## 7. Validation Logic

The core function:

```haskell
{-# INLINABLE mkValidator #-}
mkValidator :: CommitDatum -> AuctionRedeemer -> ScriptContext -> Bool
```

There are **two branches**:

* `Reveal amount salt`
* `Refund`

### 7.1 Shared helpers

#### `ownInput` and `inputAda`

```haskell
{-# INLINABLE ownInput #-}
ownInput :: ScriptContext -> TxOut
ownInput ctx =
    case findOwnInput ctx of
        Nothing -> traceError "own input missing"
        Just i  -> txInInfoResolved i

{-# INLINABLE inputAda #-}
inputAda :: ScriptContext -> Integer
inputAda ctx =
    let v = txOutValue (ownInput ctx)
    in valueOf v adaSymbol adaToken
```

* `ownInput` finds **the UTxO being spent from this script**.
* `inputAda` reads how much ADA was locked in that script UTxO originally.

Used in the Refund branch to enforce **“you must refund at least what was locked”**.

### 7.2 Reveal branch

```haskell
mkValidator dat (Reveal amount salt) ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "reveal too late"           beforeDeadline
    && traceIfFalse "commitment mismatch"       commitMatches
    && traceIfFalse "seller not paid"           sellerPaid
    && traceIfFalse "bidder not receive NFT"    bidderGetsNFT
  where
    info  = scriptContextTxInfo ctx
    txRange = txInfoValidRange info

    bidder = cdBidder dat
    seller = cdSeller dat

    bidderSigned =
      txSignedBy info bidder

    beforeDeadline =
      Interval.contains (Interval.to (cdDeadlineReveal dat)) txRange

    commitMatches =
      cdCommitHash dat == bidHash amount salt

    sellerPaid =
      let v = valuePaidTo info seller
      in valueOf v adaSymbol adaToken >= amount

    bidderGetsNFT =
      let v = valuePaidTo info bidder
      in valueOf v (cdCurrency dat) (cdToken dat) >= 1
```

Checks:

1. **Bidder has signed**
   Only the original bidder can reveal this commitment.

2. **Reveal is on time**
   The transaction’s valid range must be contained in `to deadline`:

   * i.e. on or before `cdDeadlineReveal`.

3. **Commitment matches**
   Recompute `bidHash amount salt` and compare with `cdCommitHash`.

4. **Seller is paid**
   The total `Value` paid to `cdSeller` must contain at least `amount` ADA.

5. **Bidder receives NFT**
   The total `Value` paid to `cdBidder` must contain at least 1 unit of the NFT `(cdCurrency, cdToken)`.

If any condition fails → script rejects the Reveal.

> 🧠 Note: The script does **not** enforce that `amount == inputAda ctx` or that the ADA comes *from* the committed UTxO.
> That relationship is enforced by how you construct transactions off-chain.

### 7.3 Refund branch

```haskell
mkValidator dat Refund ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "too early for refund"       afterDeadline
    && traceIfFalse "refund not paid to bidder"  refundPaid
  where
    info  = scriptContextTxInfo ctx
    txRange = txInfoValidRange info

    bidder = cdBidder dat

    bidderSigned =
      txSignedBy info bidder

    afterDeadline =
      Interval.contains (Interval.from (cdDeadlineReveal dat + 1)) txRange

    refundPaid =
      let paidToBidder = valuePaidTo info bidder
      in valueOf paidToBidder adaSymbol adaToken
           >= inputAda ctx
```

Checks:

1. **Bidder has signed**
   Only the original bidder can claim the refund.

2. **After deadline**
   The tx validity range must be contained in `from (deadline + 1)`, i.e. strictly after the deadline.

3. **Refund amount**
   The amount of ADA paid to the bidder must be **at least the ADA that was locked** in the script input (`inputAda ctx`).

If any of these fails, the Refund attempt is rejected.

---

## 8. Producing `sealed-bid-commit-reveal-nft.plutus`

At the bottom of the file:

```haskell
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
    let serialised :: SBS.ShortByteString
        serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

        plutusScript :: C.PlutusScript C.PlutusScriptV2
        plutusScript = CS.PlutusScriptSerialised serialised

    result <- C.writeFileTextEnvelope
                path
                (Just "Sealed-Bid Commit-Reveal NFT Auction Validator")
                plutusScript

    case result of
      Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
      Right ()  -> putStrLn $ "Validator written to: " <> path
```

And in `main`:

```haskell
main :: IO ()
main = do
    let network = C.Testnet (C.NetworkMagic 1)

    writeValidator "sealed-bid-commit-reveal-nft.plutus" validator

    let vh      = plutusValidatorHash validator
        onchain = plutusScriptAddress
        bech32  = toBech32ScriptAddress network validator

    ...
```

This does:

1. Serialises the compiled `validator` to CBOR.
2. Wraps it as `PlutusScriptV2` for `cardano-api`.
3. Writes a **text envelope `.plutus` file** with:

   * `"type": "PlutusScriptV2"`
   * `"description": "Sealed-Bid Commit-Reveal NFT Auction Validator"`
   * `"cborHex": "<hex-encoded script>"`.
4. Prints:

   * Plutus validator hash,
   * Plutus script address,
   * Bech32 address.

You can then use:

* The **Bech32 address** to send commit UTxOs.
* The **`.plutus` file** with `cardano-cli --tx-in-script-file` when building Reveal / Refund transactions.

---

## 9. Testing the Contract

You added a test module `tests/SealedBidSpec.hs` and wired it into `wspace-tests`.

### 9.1 What `SealedBidSpec` tests

The current tests focus on the **hashing/commitment** logic:

* **Determinism**
  `bidHash amount salt` is the same every time for the same inputs.

* **Different amount → different hash**
  For a fixed salt, changing the amount should change the hash.

* **Different salt → different hash**
  For a fixed amount, changing the salt should change the hash.

* **Datum consistency**
  A `CommitDatum` constructed from a commitment hash stores that hash correctly in `cdCommitHash`.

This gives confidence that:

* Your commit–reveal scheme is built on a correct, deterministic hash.
* You won’t accidentally accept a Reveal that doesn’t match what was committed.

You can extend tests in the future to:

* Construct mock `ScriptContext`s and:

  * Assert `mkValidator dat (Reveal amount salt) ctx == True` in valid Reveal scenarios.
  * Assert failures if seller is underpaid, NFT not delivered, reveal too late, etc.
  * Test Refund scenarios (before vs after deadline, refund amount too low, etc.).

### 9.2 Running the tests

From project root:

```bash
nix develop          -- (if you’re using the dev shell)
cabal test wspace-tests
```

You’ll see a section like:

```text
Sealed-bid commit–reveal auction
  bidHash is deterministic for same (amount, salt):            OK
  bidHash changes when amount changes (same salt):              OK
  bidHash changes when salt changes (same amount):              OK
  CommitDatum stores bidHash(amount, salt) correctly:           OK
```

---

## 10. Glossary of Terms

### 10.1 Sealed-bid auction
A type of auction where bidders submit **hidden bids** (commitments).  
Bids are only revealed later, so no one can see others’ bid values ahead of time.

---

### 10.2 Commit–reveal
A two-step pattern used to hide values until later:

1. **Commit** – publish a hash of the secret value (e.g. `(amount, salt)`).
2. **Reveal** – later publish the original value and let others recompute the hash to verify it matches.

In this contract, the commit is `bidHash amount salt`, and the reveal is the `Reveal amount salt` redeemer.

---

### 10.3 Commitment hash
A hash that “locks in” a value without showing it.

- Here it is:  
  `sha2_256(serialiseData (amount, salt))`
- Anyone who knows `(amount, salt)` can recompute this hash.
- From the hash alone, you **cannot** feasibly recover `(amount, salt)`.

---

### 10.4 Salt
A secret random `BuiltinByteString` mixed with the bid amount:

- Prevents simple guess/brute-force attacks on low values.
- Ensures the `commitHash` is hard to reverse even if the search space of amounts is small.

---

### 10.5 Datum (`CommitDatum`)
On-chain data attached to a script UTxO.  
In this contract, the datum describes:

- who the bidder is (`cdBidder`),
- who the seller is (`cdSeller`),
- which commitment hash was stored (`cdCommitHash`),
- the reveal deadline (`cdDeadlineReveal`),
- which NFT is being auctioned (`cdCurrency`, `cdToken`).

Each committed bid UTxO carries exactly one `CommitDatum`.

---

### 10.6 Redeemer (`AuctionRedeemer`)
The value provided **when spending** a script UTxO.  
It tells the validator which path to follow:

- `Reveal amount salt` – bidder is revealing their bid and trying to settle.
- `Refund` – bidder is claiming their ADA back after the reveal deadline.

---

### 10.7 Script UTxO
A UTxO whose address is a **script address** (not a normal pubkey address).

- Locked by this validator.
- Can only be spent if `mkValidator` returns `True` for the given datum, redeemer, and context.

Each committed bid produces one script UTxO at the SealedBid script address.

---

### 10.8 Validator
The Plutus on-chain function that decides if a script UTxO can be spent:

```haskell
CommitDatum -> AuctionRedeemer -> ScriptContext -> Bool
```
- Returns True → the transaction is considered valid (w.r.t. this script).
- Returns False or throws an error → the transaction is invalid.

mkValidator is your sealed-bid auction validator.

---

### 10.9 Script address

An address derived from the **hash of the validator script**.

- You send ADA/NFTs to this address to lock them under the control of the SealedBid contract.
- Off-chain tools (or your `SealedBid.hs` main) compute and print this address using the validator.

---

### 10.10 Text envelope (`.plutus` file)

A JSON-like wrapper format used by `cardano-api` / `cardano-cli` to store scripts and keys.

For this contract, the `.plutus` file contains:

* `type` – e.g. `"PlutusScriptV2"`,
* `description` – human-readable label, like `"Sealed-Bid Commit-Reveal NFT Auction Validator"`,
* `cborHex` – hex-encoded CBOR bytes of the compiled validator.

This `.plutus` file is what you pass to `cardano-cli` with `--tx-in-script-file`.

--- 
### 10.11 How these concepts connect (flow diagram)

```text
Commit phase (off-chain)

  Bidder wallet
      |
      | 1) Choose amount + salt
      v
  Compute commitment hash:
      commitHash = bidHash amount salt
      |
      | 2) Build CommitDatum:
      |    - cdBidder  = bidder PKH
      |    - cdSeller  = seller PKH
      |    - cdCommitHash = commitHash
      |    - cdDeadlineReveal = deadline
      |    - cdCurrency, cdToken = NFT
      |
      | 3) Send tx:
      |    - Output to script address
      |    - Value = ADA being committed
      |    - Datum = CommitDatum
      v
+-----------------------------+
|  Script UTxO at SealedBid   |
|  address, with CommitDatum  |
+-----------------------------+
                |
        (time passes)
                |
   +------------+-------------+
   |                          |
   | Before deadline          | After deadline
   v                          v
Reveal path (winner)          Refund path (no reveal / loser)

  Tx spends script UTxO       Tx spends script UTxO
  with redeemer:              with redeemer:

    Reveal amount salt          Refund

  Validator checks:           Validator checks:
    - bidder signed             - bidder signed
    - within deadline           - strictly after deadline
    - cdCommitHash ==           - valuePaidTo(bidder) >= inputAda
      bidHash amount salt
    - seller is paid >= amount
    - bidder gets NFT

If all checks pass:           If all checks pass:
  - Seller receives ADA         - Bidder gets their ADA back
  - Bidder receives NFT         - Script UTxO is consumed
  - Script UTxO is consumed
```