# AtomicSwap.hs – Beginner Tutorial / Documentation

## Table of Contents

## Table of Contents

- [AtomicSwap.hs – Beginner Tutorial / Documentation](#atomicswaphs--beginner-tutorial--documentation)
  - [Table of Contents](#table-of-contents)
  - [Table of Contents](#table-of-contents-1)
  - [1. 📖 Overview](#1--overview)
  - [2. 💡 What Problem This Contract Solves](#2--what-problem-this-contract-solves)
  - [3. 🌊 High-Level Flow (Cancel vs Buy)](#3--high-level-flow-cancel-vs-buy)
    - [A) Cancel](#a-cancel)
    - [B) Buy](#b-buy)
  - [4. 🧬 On-Chain Data Types](#4--on-chain-data-types)
    - [4.1 `SwapParams`](#41-swapparams)
    - [4.2 `SwapDatum`](#42-swapdatum)
    - [4.3 `SwapRedeemer`](#43-swapredeemer)
    - [4.4 `Payout`](#44-payout)
    - [4.5 `Flags`](#45-flags)
    - [4.6 `Expectation`](#46-expectation)
  - [5. Language Extensions (Why they’re here) 🔧](#5-language-extensions-why-theyre-here-)
    - [5.1 `DataKinds` 🧱](#51-datakinds-)
    - [5.2 `DeriveAnyClass` 🧬](#52-deriveanyclass-)
    - [5.3 `DeriveGeneric` 🧠](#53-derivegeneric-)
    - [5.4 `LambdaCase` 🧪](#54-lambdacase-)
    - [5.5 `NamedFieldPuns` 🧩](#55-namedfieldpuns-)
    - [5.6 `OverloadedStrings` 🔤](#56-overloadedstrings-)
    - [5.7 `ScopedTypeVariables` 🔭](#57-scopedtypevariables-)
    - [5.8 `TemplateHaskell` 🧱🧪](#58-templatehaskell-)
    - [5.9 `NoImplicitPrelude` 🚫📚](#59-noimplicitprelude-)
    - [5.10 `MultiParamTypeClasses` 👥](#510-multiparamtypeclasses-)
    - [5.11 `FlexibleInstances` 🧷](#511-flexibleinstances-)
  - [6. Imports (What each one is for) 📦](#6-imports-what-each-one-is-for-)
    - [6.1 `module Main where` ▶️](#61-module-main-where-️)
    - [6.2 Prelude (IO, FilePath, (.)) \& qualified Prelude as P](#62-prelude-io-filepath---qualified-prelude-as-p)
    - [6.3 `PlutusTx` \& `PlutusTx.Prelude` 🧠](#63-plutustx--plutustxprelude-)
    - [6.4 `Plutus.V2.Ledger.Api as V2` 📜](#64-plutusv2ledgerapi-as-v2-)
    - [6.5 `Plutus.V1.Ledger.Interval as I` ⏱️](#65-plutusv1ledgerinterval-as-i-️)
    - [6.6 `Plutus.V1.Ledger.Value as Value` 💰](#66-plutusv1ledgervalue-as-value-)
    - [6.7 `Codec.Serialise (serialise)` 🔐](#67-codecserialise-serialise-)
    - [6.8 JSON \& ByteString stack for output 🗂️](#68-json--bytestring-stack-for-output-️)
  - [7. ✅ Validation Logic](#7--validation-logic)
    - [7.1 Cancel branch](#71-cancel-branch)
    - [7.2 Buy branch](#72-buy-branch)
    - [7.3 Beacon burn (optional)](#73-beacon-burn-optional)
  - [8. 📦 Producing the `atomic-swap.plutus` file](#8--producing-the-atomic-swapplutus-file)
  - [9. 🧪 Testing the Contract](#9--testing-the-contract)
    - [9.1 How the tests are structured](#91-how-the-tests-are-structured)
    - [9.2 Key scenarios we test](#92-key-scenarios-we-test)
    - [9.3 Running the tests](#93-running-the-tests)
    - [9.4 Why testing matters here](#94-why-testing-matters-here)
  - [10. 📚 Glossary of Terms](#10--glossary-of-terms)

---

## 1. 📖 Overview

`AtomicSwap.hs` is a Plutus V2 validator that acts like a **Cardano marketplace-style listing**.

* A **seller** locks some value (ADA or multi-asset) at the script.
* A **buyer** later builds a transaction that:
    1.  pays the seller (and whoever else is in the payouts),
    2.  and takes the offered value out of the script.
* If nobody buys before the **deadline**, the seller can **cancel** and get their funds back.
* There’s also an optional “**single fill**” rule so that once it’s bought, the script can’t just recreate itself.

So it’s “atomic” in the sense that **either all the required payments and the delivery happen in one transaction, or the transaction is invalid**.

---

## 2. 💡 What Problem This Contract Solves

On UTXO blockchains (like Cardano), you can’t easily say:

> “If someone pays me exactly X, at these addresses, before time T, then they can have the funds I locked.”

You need a script to **enforce**:

* the right person can cancel,
* the right amounts are paid,
* the deadline is respected,
* no one underpays.

`AtomicSwap.hs` is that script.

It’s not a cross-chain HTLC — it’s a “sell this UTXO under these conditions” script.

---

## 3. 🌊 High-Level Flow (Cancel vs Buy)

There are two real paths in the validator:

1.  **Cancel** (seller path)
2.  **Buy** (buyer path)

The choice is made by the **redeemer**.

### A) Cancel

Used when: nobody bought in time.

Checks:

1.  **After deadline**: transaction’s time range must be after `sdDeadline`.
2.  **Seller signed**: the credential in `sdSeller` must be among the tx signatories.
3.  **Exact refund**: the seller must receive **exactly** the value that was originally locked (`sdOffer`).
4.  **If there was a beacon** (`sdSwapId`), it must be **burned**.

If any of those fail → script fails.

### B) Buy

Used when: a buyer wants to take the offer.

Checks:

1.  **Before deadline**.
2.  **Payouts match expectation** (the `sdPayouts` must add up to what `sdExpect` says).
3.  **Those payouts are actually paid** in the outputs.
4.  **The offer is actually delivered** somewhere in the outputs (the thing the seller locked is leaving the script).
5.  **Single fill**: if `fSingleFill = True`, the transaction must **not** create another script output.
6.  **If there was a beacon**, it must be burned.

If all good → buy succeeds.

---

## 4. 🧬 On-Chain Data Types

These are the Haskell types file.

### 4.1 `SwapParams`

```haskell
data SwapParams = SwapParams
  { spOperator       :: Maybe V2.Credential
  , spBeaconPolicyId :: Maybe V2.CurrencySymbol
  , spVersionTag     :: BuiltinByteString
  }
````

In your validator you basically hardcode `defaultSwapParams`, so this isn’t what the user puts on-chain — it’s more like script config.

-----

### 4.2 `SwapDatum`

```haskell
data SwapDatum = SwapDatum
  { sdSeller   :: V2.Credential
  , sdOffer    :: V2.Value
  , sdExpect   :: Expectation
  , sdPayouts  :: [Payout]
  , sdDeadline :: V2.POSIXTime
  , sdFlags    :: Flags
  , sdSwapId   :: Maybe (V2.CurrencySymbol, V2.TokenName)
  }
```

This is the **main thing** your script stores.

  * `sdSeller`: who is allowed to cancel.
  * `sdOffer`: what the script is holding and will deliver on buy.
  * `sdExpect`: what must be paid in total.
  * `sdPayouts`: who must get paid and how much.
  * `sdDeadline`: time limit.
  * `sdFlags`: extra behavior (right now just single-fill).
  * `sdSwapId`: optional beacon that must be burned when spending.

-----

### 4.3 `SwapRedeemer`

```haskell
data SwapRedeemer
  = Cancel
  | Buy
  | ClaimWithPreimage BuiltinByteString
```

You currently use **Cancel** and **Buy**.
`ClaimWithPreimage` is stubbed out in your file (`traceError "HTLC path not implemented"`), so it’s effectively disabled.

-----

### 4.4 `Payout`

```haskell
data Payout = Payout
  { pAddress :: V2.Address
  , pValue   :: V2.Value
  }
```

Each of these must be exactly present in the transaction outputs when buying.

-----

### 4.5 `Flags`

```haskell
data Flags = Flags
  { fSingleFill :: Bool
  }
```

If `True`, the buy transaction may **not** leave another script UTXO (so one-and-done).

-----

### 4.6 `Expectation`

```haskell
data Expectation
  = ExpectExact V2.Value
```

Right now, it only supports “the payouts must add up to exactly this value”.

-----

## 5\. Language Extensions (Why they’re here) 🔧

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
```
### 5.1 `DataKinds` 🧱

* **What it does:** Promotes values (constructors, strings, etc.) to the type level.
* **Why here:** Commonly used with Plutus/TH-generated code and typed builtin machinery. Safe default in Plutus projects.
* **If removed:** Some advanced or generated types can stop typechecking in more complex setups.

### 5.2 `DeriveAnyClass` 🧬

* **What it does:** Enables `deriving anyclass (C1, C2, ...)`.
* **Why here:** Handy when you want to auto-derive instances (e.g., JSON or serialisation helpers) alongside `Generic`.
* **If removed:** You’ll need to write instances manually (only matters if you use such deriving).

### 5.3 `DeriveGeneric` 🧠

* **What it does:** Lets you `deriving (Generic)`, which many libraries use (e.g., Aeson).
* **Why here:** Useful if you later add generic-based deriving for your data types.
* **If removed:** Any generic-based auto-derivations won’t compile (only if you add them).

### 5.4 `LambdaCase` 🧪

* **What it does:** Allows anonymous `\case` pattern-matching.
* **Why here:** Convenient stylistically; **not strictly used** in the snippet.
* **If removed:** No effect unless you introduce `\case` expressions.

### 5.5 `NamedFieldPuns` 🧩

* **What it does:** Lets you pattern-match with `SwapDatum{sdSeller, sdOffer, ...}` instead of `sdSeller=sdSeller`.
* **Why here:** Cleaner record usage across `validateBuy`, `validateCancel`, etc.
* **If removed:** You must write full `field = local` assignments.

### 5.6 `OverloadedStrings` 🔤

* **What it does:** Makes string literals polymorphic (`Text`, `ByteString`, `BuiltinByteString`, …).
* **Why here:** You use string literals for `BuiltinByteString` (e.g., `"v1"`) and for JSON fields without manual packing.
* **If removed:** You’ll need explicit conversions like `BSC.pack` / `toBuiltin`.

### 5.7 `ScopedTypeVariables` 🔭

* **What it does:** Keeps explicit type variables in scope across a definition.
* **Why here:** Helpful around TH and `unsafeFromBuiltinData` patterns when you want precise type control.
* **If removed:** You might hit ambiguous type errors or need more explicit annotations.

### 5.8 `TemplateHaskell` 🧱🧪

* **What it does:** Compile-time metaprogramming (splices like `$$(...)`).
* **Why here:**

  * `PlutusTx.unstableMakeIsData ''Type` / `PlutusTx.makeLift ''Type` derive on-chain instances.
  * `PlutusTx.compile [|| mkUnted wrapValidator ||]` compiles the validator to Plutus Core.
    **If removed:** You can’t generate on-chain `IsData`/`Lift` or the compiled script.

### 5.9 `NoImplicitPrelude` 🚫📚

* **What it does:** Disables automatic import of base `Prelude`.
* **Why here:** On-chain code must use **`PlutusTx.Prelude`** (deterministic). Off-chain bits (`IO`, strings) are imported from base `Prelude` explicitly/qualified.
* **If removed:** You risk pulling non-deterministic functions into on-chain code.

### 5.10 `MultiParamTypeClasses` 👥

* **What it does:** Allows typeclasses with multiple parameters.
* **Why here:** Common in Plutus ecosystems/derivations; sometimes required by library internals.
* **If removed:** Some instances/macros could fail to compile (context-dependent).

### 5.11 `FlexibleInstances` 🧷

* **What it does:** Relaxes Haskell 2010 rules on instance heads.
* **Why here:** Often needed with TH-derived or non-trivial instances in Plutus projects.
* **If removed:** Instance generation/derivation might fail in certain shapes.

> 🧹 **Trimmable (if not actually used in your build):** `LambdaCase`, `DeriveAnyClass`, `DeriveGeneric`, sometimes `ScopedTypeVariables`, `MultiParamTypeClasses`, `FlexibleInstances`. Keep the rest.

-----

## 6\. Imports (What each one is for) 📦

```haskell
module Main where

import Prelude (IO, FilePath, (.))
import qualified Prelude as P

import qualified PlutusTx
import PlutusTx.Prelude
  ( Bool(..)
  , (==)
  , (&&)
  , not
  , traceIfFalse
  , traceError
  , elem
  , mconcat
  , Maybe(..)
  , BuiltinByteString
  )

import qualified Plutus.V2.Ledger.Api as V2
import qualified Plutus.V1.Ledger.Interval as I
import qualified Plutus.V1.Ledger.Value     as Value

import Codec.Serialise (serialise)

-- imports for pretty JSON .plutus
import qualified Data.Aeson               as Aeson
import qualified Data.ByteString.Base16   as B16
import qualified Data.ByteString.Lazy     as LBS
import qualified Data.ByteString          as BS
import qualified Data.ByteString.Char8    as BSC
```
### 6.1 `module Main where` ▶️

This file is an **executable**: it builds the validator and writes `atomic-swap.plutus` in `main :: IO ()`.

### 6.2 Prelude (IO, FilePath, (.)) & qualified Prelude as P

  * You disabled the default Prelude, but you still need **off-chain** bits: `IO`, `FilePath`, `(.)`, `P.putStrLn`, `P.String`, etc.
  * Pattern: **on-chain** → `PlutusTx.Prelude`; **off-chain** → base `Prelude` (qualified as `P` to avoid mixing).

### 6.3 `PlutusTx` & `PlutusTx.Prelude` 🧠

  * `PlutusTx`: Template Haskell utilities—`compile`, `unstableMakeIsData`, `makeLift`, `unsafeFromBuiltinData`.
  * `PlutusTx.Prelude`: deterministic **on-chain** Prelude providing `Bool`, `(==)`, `(&&)`, `not`, `elem`, `mconcat`, `traceIfFalse`, `traceError`, `Maybe`, and `BuiltinByteString`.
  * Why: on-chain code **must** use these to compile to Plutus Core and remain deterministic.

### 6.4 `Plutus.V2.Ledger.Api as V2` 📜

Ledger V2 types & accessors used throughout your validator:

  * **Core types:** `ScriptContext`, `TxInfo`, `Address`, `Credential`, `POSIXTime`, `Value`, `CurrencySymbol`, `TokenName`, `BuiltinData`, `Validator`.
  * **Accessors:** `txInfoValidRange`, `txInfoSignatories`, `txInfoOutputs`, `txOutAddress`, `txOutValue`, `mkValidatorScript`.
  * Why: Your validator is **Plutus V2**.

### 6.5 `Plutus.V1.Ledger.Interval as I` ⏱️

  * Interval helpers `I.to`, `I.from`, `I.contains` used in time checks:

      * **Before deadline:** `I.contains (I.to deadline) (txInfoValidRange info)`
      * **After deadline:** `I.contains (I.from deadline) (txInfoValidRange info)`

  * Using V1 interval utils with V2 API is standard—they’re shared and stable.

### 6.6 `Plutus.V1.Ledger.Value as Value` 💰

  * Utilities for `Value`, especially `flattenValue` (used in `mustBurnBeacon` to assert the mint field equals exactly one negative beacon `(-1)`).
  * Why: Makes beacon-burn checks precise and easy to reason about.

### 6.7 `Codec.Serialise (serialise)` 🔐

  * Converts your compiled `Validator` into **CBOR** bytes so it can be packed into the `.plutus` file.

### 6.8 JSON & ByteString stack for output 🗂️

  * `Data.Aeson` → Build the JSON envelope:

    ```json
    {"type":"PlutusScriptV2","description":"Atomic swap validator","cborHex":"..."}
    ```

  * `Data.ByteString.Base16` → Hex-encode the CBOR (`cborHex`) expected by wallets/CLI.

  * `Data.ByteString.Lazy` → Write the JSON file (`LBS.writeFile`).

  * `Data.ByteString` / `Data.ByteString.Char8` → Strict bytes and simple string conversions (`BSC.unpack`) for JSON fields.

> **Why this exact combo?** It’s the standard Cardano pipeline: **serialize → base16 encode → JSON** so your script is consumable by tooling.


-----

## 7\. ✅ Validation Logic

This is where your script actually **enforces** all that.

### 7.1 Cancel branch

Your function:

```haskell
validateCancel :: SwapDatum -> V2.TxInfo -> Bool
```

Checks:

  * `validAfterDeadline sdDeadline info`
  * `sellerSigned sdSeller info`
  * `refundIsExact sdSeller sdOffer info`
  * if `sdSwapId = Just beacon`, then `mustBurnBeacon beacon info`

So: **after time, correct signer, exact refund, optional beacon burn**.

-----

### 7.2 Buy branch

Your function:

```haskell
validateBuy :: SwapDatum -> V2.ScriptContext -> Bool
```

Checks:

  * before deadline
  * payouts match expectation
  * payouts actually paid
  * offer actually delivered out
  * if single-fill → no script outputs
  * if beacon → beacon burned

This is what makes it atomic: **either all payouts and delivery happen, or the tx is rejected.**

-----

### 7.3 Beacon burn (optional)

You added:

```haskell
mustBurnBeacon :: (V2.CurrencySymbol, V2.TokenName) -> V2.TxInfo -> Bool
```

This ensures that if the datum said “this listing has this beacon”, then the spending tx must **mint -1 of that token** → i.e. burn it.
That’s a pattern to prevent reusing a listing.

-----

## 8\. 📦 Producing the `atomic-swap.plutus` file

At the bottom of your file you:

1.  Compile the validator with `PlutusTx.compile`.

2.  Serialise to CBOR.

3.  Hex-encode it.

4.  Wrap it in JSON:

    ```json
    {
      "type": "PlutusScriptV2",
      "description": "Atomic swap validator",
      "cborHex": "<hex here>"
    }
    ```

5.  Write it as `atomic-swap.plutus`.

That’s the file your off-chain code / CLI will actually use.

-----

## 9\. 🧪 Testing the Contract

This project already has a Haskell test suite (`cabal test wspace-tests`) and we added a dedicated test module for this script (`tests/AtomicSwapSpec.hs`). The goal of these tests is to simulate the two validator branches (Cancel and Buy) without having to build full Cardano transactions on-chain.

### 9.1 How the tests are structured

  * Each test:
    1.  builds a **fake datum** (what was stored at the script),
    2.  builds a **fake transaction context** (outputs, signers, time range),
    3.  calls the on-chain validator function directly in Haskell,
    4.  asserts that it returns `True` (should pass) or `False` (should fail).

So you’re unit-testing the on-chain logic in normal Haskell.

### 9.2 Key scenarios we test

1.  **Cancel succeeds after deadline with seller signature and full refund**
      * Build a datum with a seller, offer, deadline.
      * Build a tx whose valid range is **after** the deadline.
      * Include seller’s pubkey in signatories.
      * Include an output back to the seller with **exactly** the offer.
      * Expect: `mkSwapValidator ... Cancel ctx == True`.
2.  **Cancel fails before deadline**
      * Same as above but the tx is valid **before** the deadline.
      * Expect: `False`.
3.  **Cancel fails without seller signature**
      * After deadline, correct refund, but **no seller in signatories**.
      * Expect: `False`.
4.  **Cancel fails if refund amount \!= full offer**
      * After deadline, seller signed, but seller is paid less than `sdOffer`.
      * Expect: `False`.
5.  **Buy succeeds before deadline with correct payouts and offer delivery**
      * Datum expects a price (e.g. 5 ADA) and lists a payout to the seller.
      * Tx pays that exact amount to the seller and delivers the offered asset to the taker.
      * Tx is valid **before** deadline.
      * Expect: `True`.
6.  **Buy fails if payout amount doesn’t match expectation**
      * Same as above but seller is underpaid (e.g. 4.9 ADA).
      * Expect: `False`.
7.  **Buy fails after deadline**
      * All amounts correct, but tx time is **after** deadline.
      * Expect: `False`.
8.  **Buy fails when single-fill is on but the tx recreates the script output**
      * Datum has `fSingleFill = True`.
      * Tx tries to pay seller, deliver offer, **and** create another output at the same script.
      * Expect: `False`.
9.  **Cancel with beacon present but not burned → fail**
      * Datum has `sdSwapId = Just (...)`.
      * Tx does not burn that beacon.
      * Expect: `False`.
10. **Cancel with beacon present and burned → pass**
      * Same as above but the tx mints `-1` of that beacon in `txInfoMint`.
      * Expect: `True`.

These map directly to the conditions in sections **5.1** and **5.2**.

### 9.3 Running the tests

From the project root:

```bash
cabal test wspace-tests
```

Cabal will:

1.  build the library (which contains your lecture code and validator),
2.  build the test suite,
3.  run `Spec.hs`, which group all tests, including `AtomicSwapSpec`.

If all logic is still in sync with the validator, you’ll see all the AtomicSwap tests passing in the output.

### 9.4 Why testing matters here

  * The validator is quite **strict** (exact value checks, time checks, signatory checks), so a small change in the datum or outputs can make the script fail.
  * By unit-testing in Haskell, you can change the validator and immediately confirm you didn’t break:
      * cancellation rules,
      * payout rules,
      * single-fill behavior,
      * optional beacon burn.

That way, when you export `atomic-swap.plutus`, you already know the core logic is correct.

-----

## 10\. 📚 Glossary of Terms

**Validator** – The Plutus on-chain script that decides if a UTXO can be spent.

**Script UTXO** – A UTXO locked by a Plutus script instead of a normal public key. To spend it, you must please the script.

**Datum** – Extra data stored with a script UTXO. Here it describes the listing (seller, offer, deadline, payouts).

**Redeemer** – Data provided by the spending transaction to tell the validator which path to follow (Cancel vs Buy).

**Credential** – How an address is secured (pubkey or script). You used it for `sdSeller`.

**Value** – Cardano’s multi-asset bundle (can include ADA and tokens).

**Payout** – A pair of (address, value) the buyer must pay when buying.

**Deadline / POSIX time** – A time (in ms since 1970) used to say “cancel only after this” or “buy only before this.” The script checks the tx’s validity range against this.

**Single fill** – A flag to stop the script from recreating itself after a successful buy.

**Beacon** – Optional identifying token. Your script can require it to be burned when the swap UTXO is consumed.

**Atomic** – All-or-nothing: either every required payment + delivery is in the transaction, or the validator rejects the transaction.
