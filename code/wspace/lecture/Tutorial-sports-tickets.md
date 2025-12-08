# Tutorial-Sports-Tickets – Beginner Tutorial / Documentation

## Table of Contents

- [Tutorial-Sports-Tickets – Beginner Tutorial / Documentation](#tutorial-sports-tickets--beginner-tutorial--documentation)
  - [Table of Contents](#table-of-contents)
  - [1. Overview](#1-overview)
  - [2. What Problem This Contract Solves](#2-what-problem-this-contract-solves)
  - [3. High-Level Flow (Mint → Sell/Resell → Gate Use)](#3-high-level-flow-mint--sellresell--gate-use)
    - [3.1 Mint \& primary sale (off-chain pattern)](#31-mint--primary-sale-off-chain-pattern)
    - [3.2 Resale/Transfer branch (On-chain)](#32-resaletransfer-branch-on-chain)
    - [3.3 UseAtGate branch (on-chain entry scan)](#33-useatgate-branch-on-chain-entry-scan)
  - [4. On-Chain Data Types](#4-on-chain-data-types)
    - [4.1 `TicketDatum`](#41-ticketdatum)
    - [4.2 `TicketRedeemer`](#42-ticketredeemer)
      - [`Transfer PubKeyHash Integer`](#transfer-pubkeyhash-integer)
      - [`UseAtGate`](#useatgate)
    - [4.3 `TicketMintParams`](#43-ticketmintparams)
    - [4.4 `TicketMintRedeemer`](#44-ticketmintredeemer)
      - [`MintTicket BuiltinByteString`](#mintticket-builtinbytestring)
      - [`BurnTicket BuiltinByteString`](#burnticket-builtinbytestring)
  - [5. Language Extensions (Why they’re here)](#5-language-extensions-why-theyre-here)
    - [5.1 `DataKinds`](#51-datakinds)
    - [5.2 `NoImplicitPrelude`](#52-noimplicitprelude)
    - [5.3 `TemplateHaskell`](#53-templatehaskell)
    - [5.4 `ScopedTypeVariables`](#54-scopedtypevariables)
    - [5.5 `OverloadedStrings`](#55-overloadedstrings)
    - [5.6 `TypeApplications`](#56-typeapplications)
    - [5.7 Imports in `SportsTicketsContract.hs` (validator)](#57-imports-in-sportsticketscontracths-validator)
    - [5.8 Imports in `SportsTicketsPolicy.hs` (minting policy)](#58-imports-in-sportsticketspolicyhs-minting-policy)
    - [5.9 Imports in `SportsTickets.hs` (validator generator / writer)](#59-imports-in-sportsticketshs-validator-generator--writer)
  - [6. Imports (What each one is for)](#6-imports-what-each-one-is-for)
    - [6.1 Module structure (`SportsTicketsContract`, `SportsTicketsPolicy`, `SportsTickets`)](#61-module-structure-sportsticketscontract-sportsticketspolicy-sportstickets)
    - [6.2 `Prelude` and `qualified Prelude as P`](#62-prelude-and-qualified-prelude-as-p)
    - [6.3 Plutus core imports](#63-plutus-core-imports)
      - [`SportsTicketsContract.hs`](#sportsticketscontracths)
      - [`SportsTicketsPolicy.hs`](#sportsticketspolicyhs)
    - [6.4 Serialization stack](#64-serialization-stack)
    - [6.5 Cardano API imports](#65-cardano-api-imports)
  - [7. Ticket Validator Logic (`SportsTicketsContract`)](#7-ticket-validator-logic-sportsticketscontract)
    - [7.1 Shared helpers](#71-shared-helpers)
      - [`info`, `txRange`, `ticketNftBound`](#info-txrange-ticketnftbound)
        - [`ticketNftBound`](#ticketnftbound)
      - [`getContinuingOutput` and `datumFromOutput`](#getcontinuingoutput-and-datumfromoutput)
        - [`getContinuingOutput`](#getcontinuingoutput)
        - [`datumFromOutput`](#datumfromoutput)
      - [`ticketStaticFieldsEqual` and `noContinuingOutput`](#ticketstaticfieldsequal-and-nocontinuingoutput)
        - [`ticketStaticFieldsEqual`](#ticketstaticfieldsequal)
        - [`noContinuingOutput`](#nocontinuingoutput)
    - [7.2 Transfer branch (`Transfer newOwner price`)](#72-transfer-branch-transfer-newowner-price)
      - [1. Ticket NFT must be present and correct](#1-ticket-nft-must-be-present-and-correct)
      - [2. Ticket must be unused](#2-ticket-must-be-unused)
      - [3. Owner must sign, and KYC authority if any](#3-owner-must-sign-and-kyc-authority-if-any)
      - [4. Price must respect the cap, owner must change](#4-price-must-respect-the-cap-owner-must-change)
      - [5. Owner must be paid exactly the declared price](#5-owner-must-be-paid-exactly-the-declared-price)
      - [6. Ticket state transition must be correct (`ticketStateTransitionOk`)](#6-ticket-state-transition-must-be-correct-ticketstatetransitionok)
    - [7.3 UseAtGate branch (`UseAtGate`)](#73-useatgate-branch-useatgate)
      - [1. Ticket existence + unused status](#1-ticket-existence--unused-status)
      - [2. Time restriction: on or before `tdEventTime`](#2-time-restriction-on-or-before-tdeventtime)
      - [3. Mint/burn keys: `usedTokenName`, `mintedAmountOf`, `valuePaidOf`](#3-mintburn-keys-usedtokenname-mintedamountof-valuepaidof)
      - [4. Burn exactly one ticket, mint exactly one USED souvenir](#4-burn-exactly-one-ticket-mint-exactly-one-used-souvenir)
      - [5. No extra minting](#5-no-extra-minting)
      - [6. USED souvenir goes to the owner](#6-used-souvenir-goes-to-the-owner)
      - [7. No continuing script output (`noContinuingOutput`)](#7-no-continuing-script-output-nocontinuingoutput)
  - [8. Minting Policy Logic (`SportsTicketsPolicy`)](#8-minting-policy-logic-sportsticketspolicy)
    - [8.1 Parameters (`TicketMintParams` and organiser role)](#81-parameters-ticketmintparams-and-organiser-role)
    - [8.2 `MintTicket seat` branch](#82-mintticket-seat-branch)
    - [8.3 `BurnTicket seat` branch](#83-burnticket-seat-branch)
    - [8.4 Preventing extra tokens under the same policy](#84-preventing-extra-tokens-under-the-same-policy)
  - [9. Producing `sports-tickets.plutus` and `sports-tickets-policy.plutus`](#9-producing-sports-ticketsplutus-and-sports-tickets-policyplutus)
    - [9.1 `sports-tickets-exe` (validator writer)](#91-sports-tickets-exe-validator-writer)
      - [9.1.1 Computing the Plutus validator hash](#911-computing-the-plutus-validator-hash)
      - [9.1.2 Computing the Plutus script address](#912-computing-the-plutus-script-address)
      - [9.1.3 Bech32 script address via cardano-api](#913-bech32-script-address-via-cardano-api)
      - [9.1.4 Writing `sports-tickets.plutus`](#914-writing-sports-ticketsplutus)
      - [9.1.5 What `main` prints](#915-what-main-prints)
    - [9.2 `sports-tickets-policy-exe` (minting policy writer)](#92-sports-tickets-policy-exe-minting-policy-writer)
      - [9.2.1 Building `TicketMintParams` (organiser + event id)](#921-building-ticketmintparams-organiser--event-id)
      - [9.2.2 Serialising the policy and computing the policy id](#922-serialising-the-policy-and-computing-the-policy-id)
      - [9.2.3 Writing `sports-tickets-policy.plutus`](#923-writing-sports-tickets-policyplutus)
      - [9.2.4 Why you need both `.plutus` files](#924-why-you-need-both-plutus-files)
  - [10. Testing the Contracts](#10-testing-the-contracts)
    - [10.1 What `SportsTicketsSpec` tests (validator)](#101-what-sportsticketsspec-tests-validator)
      - [10.1.1 Transfer tests](#1011-transfer-tests)
      - [10.1.2 UseAtGate tests](#1012-useatgate-tests)
    - [10.2 What `SportsTicketsPolicySpec` tests (minting policy)](#102-what-sportsticketspolicyspec-tests-minting-policy)
    - [10.3 Running the tests](#103-running-the-tests)
  - [11. Glossary of Terms](#11-glossary-of-terms)
    - [11.1 NFT ticket](#111-nft-ticket)
    - [11.2 Primary sale / face value](#112-primary-sale--face-value)
    - [11.3 Resale cap (`tdMaxPrice`)](#113-resale-cap-tdmaxprice)
    - [11.4 KYC authority (`tdKycAuthority`)](#114-kyc-authority-tdkycauthority)
    - [11.5 USED souvenir token (`tdUsedPolicyId` + `usedTokenName`)](#115-used-souvenir-token-tdusedpolicyid--usedtokenname)
    - [11.6 Gate / entry scan (`UseAtGate`)](#116-gate--entry-scan-useatgate)
    - [11.7 Datum (`TicketDatum`)](#117-datum-ticketdatum)
    - [11.8 Redeemer (`TicketRedeemer`)](#118-redeemer-ticketredeemer)
    - [11.9 Minting policy](#119-minting-policy)
    - [11.10 Validator](#1110-validator)
    - [11.11 Script address](#1111-script-address)
    - [11.12 Policy ID](#1112-policy-id)
    - [11.13 Text envelope (`.plutus` file)](#1113-text-envelope-plutus-file)
    - [11.14 How these concepts connect (ticket lifecycle diagram)](#1114-how-these-concepts-connect-ticket-lifecycle-diagram)

## 1. Overview

`SportsTicketsContract` and `SportsTicketsPolicy` together implement an **NFT-based ticketing system** for sports & entertainment events on Cardano.

At a high level:

- **Each ticket is an NFT** under a specific minting policy.
- That NFT is **bound to a script UTxO** whose datum (`TicketDatum`) describes:
  - which **event** and **seat** it represents,
  - who currently **owns** it,
  - whether it is already **used**,
  - the **face value** and **maximum allowed resale price**,
  - an optional **KYC authority** who must co-sign transfers,
  - which **NFT policy + token name** represent this ticket,
  - which **“USED souvenir” policy** will be used at the gate.

The system is split into two on-chain pieces:

1. **Ticket validator (`SportsTicketsContract`)**

   - Controls the **life cycle of a single ticket UTxO**.
   - Supports two actions via `TicketRedeemer`:
     - `Transfer newOwner price` – controlled resale / transfer.
     - `UseAtGate` – gate entry: burn the ticket, mint a USED souvenir.
   - Enforces:
     - Ticket NFT is present and preserved correctly on transfer.
     - Static ticket fields (event, seat, face value, cap, policies) **never change**.
     - Resale price **cannot exceed** the configured cap.
     - Current owner must sign; optional KYC signer may be required.
     - Gate usage happens **before or at** event time.
     - Gate usage burns exactly 1 ticket NFT and mints exactly 1 USED token.
     - USED token is sent to the **current owner**, no continuing script UTxO.

2. **Minting policy (`SportsTicketsPolicy`)**

   - Controls **which NFT tickets can be minted/burned**, and by whom.
   - Parameters (`TicketMintParams`) bake in:
     - `tmpOrganizer` – organizer’s `PubKeyHash`.
     - `tmpEventId` – event identifier (mostly for off-chain grouping).
   - Redeemer (`TicketMintRedeemer`) distinguishes:
     - `MintTicket seat` – mint 1 NFT for a given seat.
     - `BurnTicket seat` – burn 1 NFT for a given seat.
   - Enforces:
     - Only the **organizer** (tmpOrganizer) can mint/burn.
     - Exactly **one** token per seat is minted/burned in each tx.
     - No extra tokens under the same policy.

The executable `SportsTickets.hs` ties this together for deployment:

- Compiles the validator to a **text-envelope `.plutus` file** (`sports-tickets.plutus`).
- Prints the **validator hash** and **script address** (including a Bech32 address) for use with `cardano-cli` and wallets.

---

## 2. What Problem This Contract Solves

Traditional ticketing systems — even when “digital” — suffer from several recurring problems:

1. **Scalping and price gouging**

   - Tickets are resold on secondary markets at **huge markups**.
   - Organizers have little on-chain control over resale prices.
   - Fans who arrive late to the sale face inflated secondary prices.

2. **Fake or duplicated tickets**

   - Screenshots, PDFs, or simple QR codes can be **copied** and resold.
   - Event staff must rely on off-chain systems to detect duplicates.
   - It’s not obvious, on-chain, whether a ticket has already been used.

3. **Messy gate operations**

   - Verifying that each ticket is **valid, unused, and unique** at the gate is tricky.
   - It’s hard to get a clean on-chain audit trail of **who actually entered**.

4. **Regulatory / KYC requirements for certain events**

   - Some events (VIP, age-restricted, high-value) may require that **only KYC’d users** can hold or resell tickets.
   - Most simple NFT-based ticket systems don’t provide an on-chain hook for this.

---

The Sports Tickets contracts address these issues as follows:

- **Anti-scalping via `tdMaxPrice`**

  - Each ticket carries a **maximum resale price** in its datum (`tdMaxPrice`).
  - The `Transfer` branch checks that the actual ADA paid to the current owner
    **equals the declared price** and that `price <= tdMaxPrice`.
  - This limits price gouging while still allowing a controlled secondary market.

- **Uniqueness and authenticity via NFT binding**

  - Each ticket is **tightly bound** to a specific NFT:
    - `tdPolicyId` + `tdTokenName` identify the ticket token.
  - The validator enforces:
    - Input UTxO must contain **exactly 1** of that NFT.
    - Continuing output must keep **exactly 1** of that NFT, with no extra non-ADA tokens.
  - Fake copies or duplicated tokens under other policies **won’t pass** the validator.

- **On-chain “used” semantics at the gate**

  - Gate usage (`UseAtGate`) enforces:
    - Transaction is valid **before or at** `tdEventTime`.
    - One ticket NFT is **burned** (under `tdPolicyId`).
    - One **USED souvenir NFT** is **minted** (under `tdUsedPolicyId`, name `USED-…`).
    - USED token is paid to the ticket owner; **no continuing script output** remains.
  - This gives a clean invariant:
    - **Before gate**: exactly one ticket NFT exists.
    - **After gate**: no ticket NFT; exactly one USED souvenir NFT for that holder.
  - You get a tamper-resistant, on-chain record of **who actually entered**.

- **Optional KYC control**

  - `tdKycAuthority :: Maybe PubKeyHash` in the datum:
    - If `Nothing`, transfers only require owner signature.
    - If `Just pk`, any `Transfer` must also be signed by this KYC authority.
  - That lets organizers:
    - Enforce compliance for certain events (e.g. age/ID-checked).
    - Maintain a clean on-chain separation: normal events with no KYC vs controlled events with KYC co-sign.

- **Organizer control over ticket supply**

  - The minting policy (`SportsTicketsPolicy`) ensures:
    - Only the organizer can **mint** or **burn** tickets for a given event.
    - Each seat NFT is minted/burned in isolation (no hidden extra tokens).
  - This prevents:
    - Unauthorized duplication of seat tickets.
    - Silent over-selling under the same policy.

In short, these contracts model a **full ticket lifecycle** on-chain:

> **Mint once → sell/resell with caps and (optional) KYC → scan at gate → burn ticket & mint souvenir.**

All of this is encoded as **validator rules and a minting policy**, giving both organizers and fans stronger guarantees than a traditional off-chain-only ticket system.

## 3. High-Level Flow (Mint → Sell/Resell → Gate Use)

The full lifecycle of a ticket in this system looks like:

1. **Mint** – organizer mints NFT tickets for each seat using the minting policy.
2. **Sell / Resell** – tickets move between wallets via the **validator**:
   - primary sale (organizer → first buyer), or
   - secondary resale (buyer → buyer), with price caps and optional KYC.
3. **Gate use** – at the event gate, the ticket is **consumed**:
   - the original ticket NFT is **burned**,
   - a “USED” souvenir NFT is **minted** to the attendee.

The validator itself only sees **two branches** via `TicketRedeemer`:

- `Transfer newOwner price`
- `UseAtGate`

Minting is handled by the **minting policy**, not the validator.

---

### 3.1 Mint & primary sale (off-chain pattern)

Off-chain, for each event, the organizer:

1. **Instantiate the minting policy**  
   Choose parameters:

   ```haskell
   TicketMintParams
     { tmpOrganizer = organiserPkh
     , tmpEventId   = "EVENT-001"
     }
    ```
This is baked into ticketPolicy params.

1. **Mint ticket NFT per seat** 
2. For each seat (e.g. `"BLOCK-A-ROW-1-SEAT-10"`), the organizer submits a transaction 
   - Uses `ticketPolicy params`. 
   - Redeemer: `MintTicket seatByte`.
   - Mints exactly 1 NFT under that policy, with token name = seat (or seat ID).
The policy enforces: 
   - Only `tmpOrganizer` can mint.
   - Exactly one token for that seat, no extras under this policy 
3. Wrap the NFT in a script UTxO with `TicketDatum`
   To make the ticket **governed by the validator**, the off-chain code creates a UTxO at the **SportsTickets script address**:

```haskell
TicketDatum
    { tdEventId      = "EVENT-001"
    , tdSeat         = "BLOCK-A-ROW-1-SEAT-10"
    , tdOwner        = firstBuyerPkh
    , tdUsed         = False
    , tdFaceValue    = faceValueLovelace
    , tdMaxPrice     = maxResaleLovelace
    , tdEventTime    = eventTime
    , tdKycAuthority = maybeKycPkh
    , tdPolicyId     = ticketPolicyId
    , tdTokenName    = ticketTokenName
    , tdUsedPolicyId = usedSouvenirPolicyId
    }
```

- The script input (when later spent) must contain 1 ticket NFT with (tdPolicyId, tdTokenName).
- The ADA locked alongside the NFT is up to your off-chain flow (face value, deposits, etc).
   
4. **Primary sale UX**

   In the dApp:

   * The user picks a seat on your **seat map UI**.
   * Off-chain code finds / mints the corresponding NFT + datum.
   * When the purchase is complete, they end up controlling a **script UTxO** that:

     * live at the SportsTickets script address,
     * holds the ticket NFT,
     * carries a `TicketDatum` with them as `tdOwner`.

> 💡 The validator doesn’t distinguish “primary” vs “secondary” sale — both happen through `Transfer`.
> Primary sale is just “the first time we create / move a script UTxO with that seat NFT and datum”.

---

### 3.2 Resale/Transfer branch (On-chain)

Later, a ticket holder may want to **resell or gift** the ticket.

On-chain, this is the `Transfer newOwner price` branch.

**Off-chain pattern for resale:**

* Build a transaction that:

  * **Inputs**:

    * The ticket UTxO at the script (with its `TicketDatum`).
  * **Redeemer**:

    * `Transfer newOwner price`, where:

      * `newOwner :: PubKeyHash` – buyer / recipient.
      * `price   :: Integer` – ADA to pay current owner.
  * **Outputs**:

    1. A **new script UTxO** at the same validator address:

       * Contains the **same ticket NFT** (1 unit).
       * Datum identical to the input, except:

         * `tdOwner` updated to `newOwner`.
    2. A **plain ADA output** to the current owner:

       * Exactly `price` lovelace.
    3. (Optionally) other outputs, as long as they don’t violate the validator rules.

**What the validator enforces in `validateTransfer`:**

* **Ticket NFT is bound & input is correct**

  * `ticketNftBound dat ctx`:

    * The script input UTxO must contain **exactly 1** `(tdPolicyId, tdTokenName)`.

* **Ticket not used**

  * `tdUsed dat` must be `False`.

* **Owner signature**

  * `txSignedBy info (tdOwner dat)`:

    > The current owner must sign the resale / transfer.

* **Optional KYC authority**

  * If `tdKycAuthority = Just pk`, then:

    * `txSignedBy info pk` must also be `True`.
  * If `Nothing`, no extra KYC signature is required.

* **Price cap & correct payment**

  * Actual ADA paid to the owner:

    ```haskell
    let v = valuePaidTo info (tdOwner dat)
    in valueOf v adaSymbol adaToken == price
    ```

  * And it must respect:

    ```haskell
    price <= tdMaxPrice dat
    ```

  * So the declared `price` matches the **real money flow**,
    and the money flow must not exceed the cap.

* **Owner actually changes**

  * `newOwner /= tdOwner dat`:

    > You can’t “transfer” to yourself.

* **Ticket state transition is valid**

  * `ticketStateTransitionOk dat newOwner ctx` checks:

    * There is **exactly one** continuing script output at the same validator.
    * That output:

      * Contains **exactly 1** of the ticket NFT.
      * Contains **no other non-ADA assets** besides that NFT.
      * Has datum `outDat` such that:

        * `tdOwner outDat == newOwner`
        * All **static fields** match the old datum:

          * event id, seat, face value, max price, time, KYC, policy IDs, token name.
        * `tdUsed` is unchanged (still `False` on transfer).

**Result:**

> Resales are allowed only within the configured price cap, with correct payment to the seller, with optional KYC, and without ever mutating the ticket’s identity (event/seat/NFT) or rules.

Gifts are also possible by using `price = 0`, still subject to KYC and signatures.

---

### 3.3 UseAtGate branch (on-chain entry scan)

When the attendee arrives at the **stadium gate**, the ticket must be:

* verified,
* consumed,
* and turned into a **souvenir** that proves they actually entered.

On-chain, this is the `UseAtGate` branch.

**Off-chain pattern for gate scan:**

The dApp (or gate scanner) builds a transaction that:

* **Inputs**:

  * The ticket UTxO at the script with its `TicketDatum`.
* **Redeemer**:

  * `UseAtGate`.
* **Mint / Burn**:

  * Burns **1 ticket NFT**: `(tdPolicyId, tdTokenName)` with amount `-1`.
  * Mints **1 USED souvenir NFT**:

    * Policy: `tdUsedPolicyId`
    * Token name: `usedTokenName (tdTokenName dat)` = `"USED-" <> originalName`
* **Outputs**:

  1. A **plain UTxO** to the ticket owner:

     * Contains exactly 1 unit of the **USED souvenir NFT**.
  2. (Optionally) change ADA, fees, etc.

  👉 **No continuing script UTxO** for that ticket – the ticket is truly “spent”.

**What the validator enforces in `validateUseAtGate`:**

* **Ticket NFT still present in input**

  * Reuses `ticketNftBound dat ctx`:

    * Script input must have exactly 1 of the ticket NFT.

* **Ticket not already used**

  * `not (tdUsed dat)`:

    > Gate cannot be used twice with the same ticket datum.

* **Time restriction**

  * Transaction’s validity range must be contained in:

    ```haskell
    Interval.to (tdEventTime dat)
    ```

  * i.e. **on or before** `tdEventTime`.

* **Mint / burn pattern**

  With:

  ```haskell
  csTicket = tdPolicyId dat
  tn       = tdTokenName dat
  csUsed   = tdUsedPolicyId dat
  utn      = usedTokenName tn  -- "USED-" <> original name
  ```

  The script checks:

  * Burn exactly 1 ticket:

    ```haskell
    mintedAmountOf csTicket tn ctx == (-1)
    ```

  * Mint exactly 1 USED souvenir:

    ```haskell
    mintedAmountOf csUsed utn ctx == 1
    ```

  * **No extra minting/burning** besides these two triples:

    ```haskell
    all allowed mintedTriples && length mintedTriples == 2
    ```

* **USED souvenir must go to the owner**

  ```haskell
  souvenirPaidToOwner =
    valuePaidOf (tdOwner dat) csUsed utn ctx == 1
  ```

  * The only place the newly minted USED token can end up is the current owner’s wallet.

* **No continuing script output**

  ```haskell
  noContinuingOutput ctx
  ```

  * After gate use, the script must **not** appear as an address on any output.
  * The ticket UTxO is consumed; only the souvenir + any ADA remain.

**Result:**

> A ticket can only be used at or before event time, exactly once, and doing so atomically burns the original ticket NFT and mints a USED souvenir NFT to the rightful owner, leaving no ticket UTxO behind.

A gate operator (or auditor) can later see on-chain:

* How many tickets were minted (from the minting policy).
* How many were actually used (count of USED souvenirs).
* For any particular ticket NFT, whether it’s:

  * still unspent (valid ticket),
  * or already consumed (corresponding USED minted and ticket burned).

---

## 4. On-Chain Data Types

The Sports Tickets system is made from **two main scripts**:

1. A **validator** script (`SportsTicketsContract`) that controls each ticket UTxO.
2. A **minting policy** (`SportsTicketsPolicy`) that controls how ticket NFTs are minted/burned.

Each script has its own on-chain types:

* `TicketDatum`, `TicketRedeemer` → used by the validator.
* `TicketMintParams`, `TicketMintRedeemer` → used by the minting policy.

---

### 4.1 `TicketDatum`

```haskell
data TicketDatum = TicketDatum
    { tdEventId      :: BuiltinByteString  -- ^ Event identifier
    , tdSeat         :: BuiltinByteString  -- ^ Seat / section description
    , tdOwner        :: PubKeyHash         -- ^ Current owner of the ticket
    , tdUsed         :: Bool               -- ^ Has this ticket been used at the gate?
    , tdFaceValue    :: Integer            -- ^ Primary sale price (in lovelace)
    , tdMaxPrice     :: Integer            -- ^ Max allowed resale price (in lovelace)
    , tdEventTime    :: POSIXTime          -- ^ Event time (for gate checks)
    , tdKycAuthority :: Maybe PubKeyHash   -- ^ If Just pk, transfers require pk's signature
    , tdPolicyId     :: CurrencySymbol     -- ^ Policy ID of the ticket NFT
    , tdTokenName    :: TokenName          -- ^ Token name of the ticket NFT
    , tdUsedPolicyId :: CurrencySymbol     -- ^ Policy for USED souvenir tokens
    }
PlutusTx.unstableMakeIsData ''TicketDatum
```
Each **ticket UTxO** at the validator address carries exactly one `TicketDatum`. Field-by-field:

* **`tdEventId :: BuiltinByteString`**
  A short identifier for the event, e.g. `"MATCH-2025-APR-01"` or `"CONCERT-XYZ"`.
  Used mainly for **off-chain grouping** and UI, but it also ensures the static identity of this ticket never changes.

* **`tdSeat :: BuiltinByteString`**
  Human-readable seat/section info, e.g. `"BLOCK-A-ROW-1-SEAT-10"`.
  This is treated as a **static field**: it cannot change during transfers.

* **`tdOwner :: PubKeyHash`**
  The **current owner** of the ticket:

  * Must sign any `Transfer` transaction.
  * Receives resale ADA.
  * Receives the USED souvenir when the ticket is used at the gate.

* **`tdUsed :: Bool`**
  Logical flag meaning “has this ticket already been used?”.

  * In `validateTransfer`: ticket must **not** be used (`False`).
  * In `validateUseAtGate`: ticket must **not** be used (`False`) to allow entry.
  * In practice, “used” is represented on-chain by **burning the ticket NFT and minting a USED souvenir**, but this flag gives an additional logical guard.

* **`tdFaceValue :: Integer` (lovelace)**
  The **primary sale price** of the ticket (face value).
  This is a static reference value and doesn’t change after minting.

* **`tdMaxPrice :: Integer` (lovelace)**
  The **maximum allowed resale price**:
  * In `validateTransfer` we enforce:
    `price <= tdMaxPrice`
  * This implements the **anti-scalping cap**: owners cannot resell above this limit. 

* **`tdEventTime :: POSIXTime`**
  Time of the event:
  * `UseAtGate` requires the transaction’s valid range to be **on or before** `tdEventTime`.
  * Prevents entry after the event has effectively “expired”.

* **`tdKycAuthority :: Maybe PubKeyHash`**
  * `Nothing` → no extra KYC check: only owner needs to sign transfers.
  * `Just pk` → any `Transfer` must be signed by **both**:
    * the current owner (`tdOwner`), and
    * the KYC authority (`pk`).

  This allows optional **KYC-gated resale** for certain events.

* **`tdPolicyId :: CurrencySymbol`**
  Which **policy** this ticket NFT belongs to (usually created by `SportsTicketsPolicy`):
  * Used to check the script input contains exactly 1 matching NFT.
  * Used in `ticketNftBound` and `ticketStateTransitionOk`.

* **`tdTokenName :: TokenName`**
  The **token name** for this specific ticket, e.g. `"TICKET-001"`.
  Together with `tdPolicyId`, it uniquely identifies the ticket on-chain.

* **`tdUsedPolicyId :: CurrencySymbol`**
  The policy ID for **USED souvenir NFTs**:
  * `UseAtGate` burns `(tdPolicyId, tdTokenName)` and mints
    `(tdUsedPolicyId, "USED-" <> originalTokenName)`.
  * This allows souvenir NFTs to live under a separate policy if desired.

> 🔎 The validator treats most of these fields as **static**.
> For transfers, only `tdOwner` is allowed to change; all other “identity” fields must remain identical on the continuing output datum.
---

### 4.2 `TicketRedeemer`

```haskell
data TicketRedeemer
    = Transfer PubKeyHash Integer  -- ^ new owner, resale price (in lovelace)
    | UseAtGate
PlutusTx.unstableMakeIsData ''TicketRedeemer
```

Each time a ticket UTxO at the script is spent, a `TicketRedeemer` tells the validator **which path** to run:

#### `Transfer PubKeyHash Integer`

* Two arguments:

  1. `newOwner :: PubKeyHash` — who will become the **new owner** of the ticket.
  2. `price    :: Integer`   — the **resale price in lovelace**.

* On this branch `mkTicketValidator` calls `validateTransfer` and enforces:

  * ticket is **unused**,
  * current `tdOwner` signed the transaction,
  * KYC authority signed (if `tdKycAuthority = Just pk`),
  * actual ADA paid to `tdOwner` equals `price`,
  * `price <= tdMaxPrice`, enforcing the anti-scalping cap,
  * `newOwner /= tdOwner` (no fake self-transfer),
  * continuing output’s datum has:

    * same static fields,
    * `tdOwner` updated to `newOwner`,
    * NFT preserved correctly.

#### `UseAtGate`

* No arguments; it’s just “I’m trying to use this ticket at the **entry gate**”.

* On this branch `mkTicketValidator` calls `validateUseAtGate` and enforces:

  * ticket is unused and within event time,
  * 1 ticket NFT is **burned**,
  * 1 USED souvenir NFT is **minted** under `tdUsedPolicyId`,
  * USED souvenir is paid to `tdOwner`,
  * **no** continuing script output remains.

---

### 4.3 `TicketMintParams`

```haskell
data TicketMintParams = TicketMintParams
  { tmpOrganizer :: V2.PubKeyHash       -- ^ Who is allowed to mint / burn
  , tmpEventId   :: BuiltinByteString   -- ^ Event id this policy is for
  }

PlutusTx.makeLift ''TicketMintParams
```

These are **parameters baked into the minting policy** for ticket NFTs.

* **`tmpOrganizer :: PubKeyHash`**

  * The **only party allowed** to mint or burn tickets under this policy.

  * `mkTicketPolicy` checks that any `MintTicket` / `BurnTicket` action is signed by this PKH:

    ```haskell
    V2Ctx.txSignedBy txInfo (tmpOrganizer params)
    ```

  * In practice: you set this to the **event organizer**’s payment key.

* **`tmpEventId :: BuiltinByteString`**

  * Event identifier used at the policy level (parallel to `tdEventId` in the datum).
  * Mainly for **linking this policy to a specific event** and for off-chain UX/logging.
  * Can be used to ensure that all tokens under this policy belong to the same event group.

Because of `PlutusTx.makeLift`, `TicketMintParams` can be **embedded at compile time** into the minting policy code, and used to derive the `CurrencySymbol` of the ticket NFTs.

---

### 4.4 `TicketMintRedeemer`

```haskell
data TicketMintRedeemer
  = MintTicket BuiltinByteString
  | BurnTicket BuiltinByteString
  deriving (Haskell.Eq, Haskell.Show)

PlutusTx.unstableMakeIsData ''TicketMintRedeemer
```

This is the redeemer type for the **minting policy** `SportsTicketsPolicy`.

#### `MintTicket BuiltinByteString`

* Represents the action **“mint exactly one ticket NFT for a given seat”**.
* The `BuiltinByteString` is the seat identifier, e.g. `"BLOCK-A-ROW-1-SEAT-10"`.

Under the hood:

* The policy turns this into a `TokenName seat`.
* It then checks that:

  * under this policy’s `CurrencySymbol`:

    * exactly **one** token with that `TokenName` is minted (amount `+1`),
    * and **no other tokens** under this policy are minted in the same transaction.

This prevents:

* double-minting for the same seat (without burning),
* minting multiple different seats in one go if the policy is configured that way.

#### `BurnTicket BuiltinByteString`

* Represents the action **“burn exactly one ticket NFT for a given seat”**.
* Same seat identifier, same `TokenName` strategy.

The policy enforces:

* organizer signed, and
* exactly one token under this policy for that seat is burned (amount `-1`),
* with no extra tokens under the same policy being minted or burned.

> 🧩 Together, `TicketMintParams` + `TicketMintRedeemer` define a **tight minting contract**:
>
> * Only the organizer can mint/burn.
> * Each seat corresponds to a specific token name.
> * Each mint/burn transaction must involve exactly **one** ticket token for that seat under this policy.

---

## 5. Language Extensions (Why they’re here)

At the top of your **on-chain** and **generator** modules you’ll see things like:

```haskell
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}
```

(and in the policy: `NumericUnderscores`, `MultiParamTypeClasses`, `FlexibleInstances`, etc.)

These extensions are standard for Plutus projects. They enable:

* on-chain compilation (`TemplateHaskell`, `DataKinds`),
* safe/custom Prelude (`NoImplicitPrelude`),
* nicer ergonomics (`OverloadedStrings`, `TypeApplications`, `ScopedTypeVariables`).

Below we focus on the **core six** used across **`SportsTicketsContract.hs`**, **`SportsTickets.hs`**, and **`SportsTicketsPolicy.hs`**.

---

### 5.1 `DataKinds`

**What it does**
Promotes certain values (like constructors, string-like things) to the type level, giving you extra type information.

**Why here**

* Plutus ledger types and TH-generated code often rely on `DataKinds` under the hood.
* It’s part of the “standard Plutus header” and plays nicely with:

  * `PlutusTx.compile`
  * generated `IsData` instances
  * type-level tags inside the ledger API.

You don’t use it directly in `SportsTicketsContract.hs`, but it keeps the Plutus / TH machinery happy in the background.

**If removed**

* Some Plutus or TH code might stop compiling in more complex setups.
* It’s safe, standard boilerplate to leave on.

---

### 5.2 `NoImplicitPrelude`

**What it does**
Prevents GHC from automatically importing the default `Prelude`.

**Why here**

On-chain we **must** use `PlutusTx.Prelude`, not the normal Haskell `Prelude`, because:

* Plutus needs **deterministic**, integer-only, blockchain-safe code.
* Many standard `Prelude` functions are not supported or would break determinism.

So your modules do things like:

```haskell
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified Prelude as P
```

* `PlutusTx.Prelude` is used for **on-chain logic**: `Bool`, `Integer`, `(==)`, `(&&)`, `traceIfFalse`, `error`, etc.
* `Prelude` is imported as `P` only for **off-chain IO** / debugging, e.g.:

  ```haskell
  putStrLn $ "Validator Hash (Plutus): " <> P.show vh
  ```

**If removed**

* GHC would silently import `Prelude`.
* You might accidentally use off-chain-only functions inside on-chain code, causing compilation or runtime issues.

---

### 5.3 `TemplateHaskell`

Used in:

* `SportsTicketsContract.hs`
* `SportsTicketsPolicy.hs`
  (Not needed in `SportsTickets.hs` which is only a generator.)

**What it does**
Enables compile-time metaprogramming via splices like `$$(...)`, `$(...)`.

**Why here**

You use TH in two crucial ways:

1. **Deriving on-chain data instances**

   ```haskell
   PlutusTx.unstableMakeIsData ''TicketDatum
   PlutusTx.unstableMakeIsData ''TicketRedeemer
   PlutusTx.makeLift ''TicketMintParams
   PlutusTx.unstableMakeIsData ''TicketMintRedeemer
   ```

   This generates the `IsData` / `Lift` machinery so `TicketDatum`, `TicketRedeemer`, `TicketMintParams`, etc. can be:

   * encoded/decoded in `BuiltinData`,
   * used inside Plutus Core.

2. **Compiling validators/policies to Plutus Core**

   ```haskell
   validator =
     mkValidatorScript $$(PlutusTx.compile [|| mkTicketValidatorUntyped ||])
   ```

   and in the policy:

   ```haskell
   ticketPolicy params =
     V2.mkMintingPolicyScript $
       $$(PlutusTx.compile [|| \p -> mkWrappedPolicy p ||])
         `PlutusTx.applyCode` PlutusTx.liftCode params
   ```

   TH is what actually **turns your Haskell validator/policy into Plutus Core** at compile time.

**If removed**

* You couldn’t derive `IsData`/`Lift` automatically.
* You couldn’t use `PlutusTx.compile` or produce a `Validator` / `MintingPolicy` script.

---

### 5.4 `ScopedTypeVariables`

**What it does**
Makes explicit type variables stay in scope across the whole function body.

**Why here**

It pairs with `TypeApplications` inside your untyped wrappers:

```haskell
{-# INLINABLE mkTicketValidatorUntyped #-}
mkTicketValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkTicketValidatorUntyped d r c =
    let dat = unsafeFromBuiltinData @TicketDatum    d
        red = unsafeFromBuiltinData @TicketRedeemer r
        ctx = unsafeFromBuiltinData @ScriptContext  c
    in if mkTicketValidator dat red ctx
          then ()
          else error ()
```

and similarly in the minting policy:

```haskell
mkWrappedPolicy :: TicketMintParams -> BuiltinData -> BuiltinData -> ()
mkWrappedPolicy params r ctxData =
  let redeemer :: TicketMintRedeemer
      redeemer = unsafeFromBuiltinData r
      ctx      = unsafeFromBuiltinData ctxData
  in ...
```

`ScopedTypeVariables` ensures that type variables you mention in the signature can be referred to properly when you use `@TicketDatum`, `@TicketRedeemer`, etc.

**If removed**

* GHC might complain about ambiguous types.
* You’d need more verbose annotations, or the compiler could guess the wrong type.

---

### 5.5 `OverloadedStrings`

**What it does**
Makes string literals polymorphic – they can become `Text`, `ByteString`, `BuiltinByteString`, etc. based on context.

**Why here**

You use string literals in multiple contexts:

* **Descriptions for text envelopes** (off-chain):

  ```haskell
  description :: C.TextEnvelopeDescr
  description = "Sports Tickets Plutus Validator"
  ```

* **Event IDs, seat strings, etc.** that end up as `BuiltinByteString`:

  ```haskell
  tdEventId = "EVENT-001"
  tdSeat    = "BLOCK-A-ROW-1-SEAT-10"
  ```

Because of `OverloadedStrings`, these literals automatically adapt to:

* `BuiltinByteString` (via `toBuiltin` in the background),
* `Text`, `String`, etc. where needed.

**If removed**

* You’d have to wrap a lot of values manually, like:

  ```haskell
  tdEventId = Builtins.toBuiltin ("EVENT-001" :: ByteString)
  ```

  or explicitly use `T.pack`, etc.

---

### 5.6 `TypeApplications`

**What it does**
Allows you to explicitly specify type arguments with `@Type`.

**Why here**

It shows up in your **untyped wrappers** where you decode `BuiltinData`:

```haskell
unsafeFromBuiltinData @TicketDatum    d
unsafeFromBuiltinData @TicketRedeemer r
unsafeFromBuiltinData @ScriptContext  c
```

Instead of hoping the compiler guesses the right type, you tell it:

> “Decode this `BuiltinData` as a `TicketDatum`.”

That’s crystal clear and avoids ambiguity.

Similarly for policy redeemers/contexts if you choose to annotate them.

**If removed**

* You’d need more verbose patterns or helper functions.
* Type inference might become unclear, especially as the contract grows.

--- 

### 5.7 Imports in `SportsTicketsContract.hs` (validator)

This is the **core on-chain validator** for tickets (transfer + gate). Its imports are all about:

* Plutus V2 types & contexts,
* V1 helpers for intervals and values,
* Template Haskell helpers (`PlutusTx`, `unsafeFromBuiltinData`),
* The Plutus on-chain Prelude.

```haskell
import Plutus.V2.Ledger.Api
  ( Validator
  , ScriptContext(..)
  , TxInfo(..)
  , TxOut(..)
  , TxInInfo(..)
  , TxOutRef
  , Address(..)
  , Credential(..)
  , OutputDatum(..)
  , Datum(..)
  , POSIXTime
  , POSIXTimeRange
  , PubKeyHash
  , CurrencySymbol
  , TokenName(..)
  , unTokenName
  , ValidatorHash
  , BuiltinData
  , mkValidatorScript
  )
```

* **What these are for:**

  * `Validator` – final compiled script type.
  * `ScriptContext`, `TxInfo`, `TxOut`, `TxInInfo`, `TxOutRef` – describe the spending transaction and UTxOs.
  * `Address`, `Credential` – used to detect script vs pubkey addresses (for continuing outputs).
  * `OutputDatum`, `Datum` – unwrap inline datums to `TicketDatum`.
  * `POSIXTime`, `POSIXTimeRange` – event time and validity ranges.
  * `PubKeyHash`, `CurrencySymbol`, `TokenName` – identities of owners and tokens.
  * `BuiltinData` – raw on-chain data used by the untyped wrapper.
  * `mkValidatorScript` – wraps compiled core into a `Validator`.

```haskell
import Plutus.V2.Ledger.Contexts
  ( txSignedBy
  , scriptContextTxInfo
  , valuePaidTo
  , findOwnInput
  , ownHash
  , txInInfoResolved
  )
```

* **What these are for:**

  * `scriptContextTxInfo` – extract `TxInfo` from `ScriptContext`.
  * `txSignedBy` – check if given `PubKeyHash` signed the transaction (owner / KYC).
  * `valuePaidTo` – how much value a given `PubKeyHash` received (for payments + souvenirs).
  * `findOwnInput`, `txInInfoResolved` – locate this script’s input and get its `TxOut`.
  * `ownHash` – script’s own `ValidatorHash`, used to find continuing outputs.

```haskell
import Plutus.V1.Ledger.Interval as Interval
  ( contains
  , to
  )
```

* Time logic:

  * `Interval.to t` – build  `(-∞, t]`.
  * `Interval.contains` – check if `txInfoValidRange` lies within allowed bounds.
  * Used to enforce “before or at event time” in `UseAtGate`.

```haskell
import Plutus.V1.Ledger.Value
  ( Value
  , valueOf
  , adaSymbol
  , adaToken
  , flattenValue
  )
```

* Asset / value logic:

  * `Value` – multi-asset container.
  * `valueOf` – how much of (cs, token) is in a `Value`.
  * `adaSymbol`, `adaToken` – identify ADA.
  * `flattenValue` – turn a `Value` into `[(CurrencySymbol, TokenName, Integer)]` triples; used to:

    * check exactly one ticket NFT in input,
    * check mint/burn triples for `UseAtGate`.

```haskell
import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins
```

* `PlutusTx` – TH utilities (`unstableMakeIsData`, `compile`, `unsafeFromBuiltinData`).
* `PlutusTx.Prelude` – on-chain Prelude: `Bool`, `Integer`, `(==)`, `(&&)`, `traceError`, `traceIfFalse`, etc.
* `PlutusTx.Builtins` – low-level builtins, here used for:

  * `Builtins.appendByteString` to build `"USED-" <> tokenName`.

---

### 5.8 Imports in `SportsTicketsPolicy.hs` (minting policy)

This module defines the **NFT minting policy** for tickets.

```haskell
import qualified Prelude as Haskell
```

* Only used for **off-chain-ish derivations and instances**, e.g.:

  * `deriving (Haskell.Eq, Haskell.Show)` for `TicketMintRedeemer`.
* On-chain logic still uses `PlutusTx.Prelude`.

```haskell
import PlutusTx
import PlutusTx.Prelude
```

* Same role as in the validator:

  * `PlutusTx` – TH code (`makeLift`, `unstableMakeIsData`, `compile`, `liftCode`).
  * `PlutusTx.Prelude` – on-chain logic operators and functions.

```haskell
import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V2.Ledger.Contexts as V2Ctx
import qualified Plutus.V1.Ledger.Value    as Value
```

* **V2 API / Contexts:**

  * `V2.ScriptContext`, `V2.TxInfo`, `V2.CurrencySymbol`, `V2.PubKeyHash`, etc.
  * `V2Ctx.scriptContextTxInfo` – extract `TxInfo`.
  * `V2Ctx.ownCurrencySymbol` – policy’s own `CurrencySymbol`.
  * `V2Ctx.txSignedBy` – ensure organiser signed.

* **Value API:**

  * `Value.flattenValue (V2.txInfoMint info)` – inspect all `(cs, token, amount)` minted or burned.
  * `Value.TokenName` – construct token names from seat bytes.

Together these imports allow `mkTicketPolicy` to:

* check organiser’s signature,
* enforce **exactly one** ticket minted/burned per transaction under this policy,
* disallow extra tokens under the same `CurrencySymbol`.

---

### 5.9 Imports in `SportsTickets.hs` (validator generator / writer)

This is the **off-chain helper executable** that:

* takes the compiled `validator`,
* serialises it,
* writes `sports-tickets.plutus`,
* prints script hash & addresses.

```haskell
import Prelude (IO, FilePath, String, putStrLn, (<>))
import qualified Prelude as P
import qualified Data.Text as T
```

* Minimal `Prelude` bits for IO and string operations.
* `P.show` used to print hashes/addresses.
* `Data.Text` used with `Cardano.Api` for Bech32 addresses.

```haskell
import Plutus.V2.Ledger.Api
  ( Validator
  , Address(..)
  , Credential(..)
  )
import qualified Plutus.V2.Ledger.Api as PlutusV2
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins
```

* `Validator` – the type of the compiled Plutus script.
* `Address`, `Credential` – used to build the on-chain `scriptAddress`.
* `PlutusV2` – qualified import for things like `ValidatorHash`.
* `PlutusTx.Prelude` & `Builtins` – used to convert serialised bytes into `BuiltinByteString` and construct `ValidatorHash` in a Plutus-like way:

  ```haskell
  plutusValidatorHash :: PlutusV2.Validator -> PlutusV2.ValidatorHash
  ```

```haskell
import qualified Codec.Serialise       as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
import qualified Data.ByteString       as BS
```

* Raw **serialisation stack**:

  * `Serialise.serialise validator` → CBOR bytes.
  * `LBS` / `SBS` – convert between lazy/strict/short `ByteString`.
  * These are the bytes that get wrapped into a `PlutusScriptV2`.

```haskell
import qualified Cardano.Api          as C
import qualified Cardano.Api.Shelley  as CS
```

* Bridge to the Cardano CLI world:

  * `C.PlutusScript C.PlutusScriptV2`
  * `C.writeFileTextEnvelope`
  * `C.hashScript`
  * `C.makeShelleyAddressInEra`
  * `C.serialiseAddress`
  * `C.Testnet`, `C.NetworkMagic` to build a Bech32 script address.

```haskell
import SportsTicketsContract (validator)
```

* Imports the **on-chain validator** defined in `SportsTicketsContract.hs`.
* Everything in this file revolves around taking that `validator` and outputting:

  * `sports-tickets.plutus` file,
  * the human-readable Bech32 address,
  * the Plutus-style `ValidatorHash` and `Address` for debugging.

---

## 6. Imports (What each one is for)

This section explains **how the three main modules are structured** and **what their imports are doing**:

* `SportsTicketsContract.hs` – **on-chain validator** (ticket transfer + gate use).
* `SportsTicketsPolicy.hs` – **on-chain minting policy** (ticket NFTs).
* `SportsTickets.hs` – **off-chain helper executable** to dump `sports-tickets.plutus` and print addresses.

---

### 6.1 Module structure (`SportsTicketsContract`, `SportsTicketsPolicy`, `SportsTickets`)

**1. `SportsTicketsContract`**

```haskell
module SportsTicketsContract
  ( TicketDatum(..)
  , TicketRedeemer(..)
  , mkTicketValidator
  , mkTicketValidatorUntyped
  , validator
  ) where
```

* Exposes:

  * `TicketDatum` – on-chain state (who owns the ticket, seat, event, caps, KYC, NFT ids,…).
  * `TicketRedeemer` – `Transfer` / `UseAtGate`.
  * `mkTicketValidator` – **typed** validator: `TicketDatum -> TicketRedeemer -> ScriptContext -> Bool`.
  * `mkTicketValidatorUntyped` – `BuiltinData` wrapper used by PlutusTx.
  * `validator` – final `Validator` value used by the writer and tests.

**2. `SportsTicketsPolicy`**

```haskell
module SportsTicketsPolicy
  ( TicketMintParams(..)
  , TicketMintRedeemer(..)
  , mkTicketPolicy
  , ticketPolicy
  ) where
```

* Exposes:

  * `TicketMintParams` – baked-in organiser PKH + event id.
  * `TicketMintRedeemer` – `MintTicket seat` / `BurnTicket seat`.
  * `mkTicketPolicy` – core policy logic.
  * `ticketPolicy` – final `MintingPolicy` parameterised by `TicketMintParams`.

**3. `SportsTickets`**

```haskell
module Main where
```

* Small **executable** whose job is:

  * import `validator` from `SportsTicketsContract`,
  * serialise it,
  * write `sports-tickets.plutus`,
  * print:

    * Plutus `ValidatorHash`,
    * Plutus `Address`,
    * Bech32 script address via `cardano-api`.

---

### 6.2 `Prelude` and `qualified Prelude as P`

Because you use `NoImplicitPrelude` in the on-chain files, you control exactly **which Prelude** is visible.

**On-chain modules (`SportsTicketsContract`, `SportsTicketsPolicy`)**

* They don’t import base `Prelude` at all for logic.

* Instead they use:

  ```haskell
  import PlutusTx.Prelude hiding (Semigroup(..), unless)
  ```

* This ensures only **Plutus-safe** functions (deterministic, on-chain) are used in validation logic.

**Off-chain writer (`SportsTickets.hs`)**

```haskell
import Prelude (IO, FilePath, String, putStrLn, (<>))
import qualified Prelude as P
```

* Minimal base Prelude for:

  * `IO`, `FilePath`, `String`, `putStrLn`, `( <>)`.
  * `P.show` when printing hashes and addresses.

You get a clean separation:

* **On-chain**: `PlutusTx.Prelude`.
* **Off-chain IO & printing**: base `Prelude` imported explicitly.

---

### 6.3 Plutus core imports

The Plutus imports give you all the **ledger types**, **context accessors**, and **value utilities** for validator & policy logic.

#### `SportsTicketsContract.hs`

Key imports:

```haskell
import Plutus.V2.Ledger.Api
  ( Validator
  , ScriptContext(..)
  , TxInfo(..)
  , TxOut(..)
  , TxInInfo(..)
  , TxOutRef
  , Address(..)
  , Credential(..)
  , OutputDatum(..)
  , Datum(..)
  , POSIXTime
  , POSIXTimeRange
  , PubKeyHash
  , CurrencySymbol
  , TokenName(..)
  , unTokenName
  , ValidatorHash
  , BuiltinData
  , mkValidatorScript
  )
```

* Types used to **inspect the transaction** and **encode ticket identity**.
* `Validator`, `BuiltinData`, `mkValidatorScript` are needed to turn `mkTicketValidatorUntyped` into a Plutus script.

```haskell
import Plutus.V2.Ledger.Contexts
  ( txSignedBy
  , scriptContextTxInfo
  , valuePaidTo
  , findOwnInput
  , ownHash
  , txInInfoResolved
  )
```

* Check signatures: `txSignedBy` (owner / KYC).
* Inspect payments: `valuePaidTo` (owner paid `price`, owner receives USED souvenir).
* Discover script input and outputs: `findOwnInput`, `txInInfoResolved`, `ownHash`.

```haskell
import Plutus.V1.Ledger.Interval as Interval
  ( contains
  , to
  )
```

* Time checks:

  * `Interval.to (tdEventTime dat)` + `contains` → **before or at event time** for `UseAtGate`.

```haskell
import Plutus.V1.Ledger.Value
  ( Value
  , valueOf
  , adaSymbol
  , adaToken
  , flattenValue
  )
```

* Multi-asset ops:

  * `valueOf` – checks ADA paid to owner / ticket NFT presence / souvenir distribution.
  * `flattenValue` – used to:

    * enforce “exactly 1 ticket NFT in input” (`ticketNftBound`),
    * enforce mint/burn pattern (`tk -1`, `USED +1`).

```haskell
import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins
```

* `PlutusTx` – Template Haskell derivations & `unsafeFromBuiltinData`.
* `PlutusTx.Prelude` – Boolean logic, arithmetic, `traceIfFalse`, etc.
* `Builtins.appendByteString` – creates `"USED-" <> unTokenName tn` to derive the USED token name.

#### `SportsTicketsPolicy.hs`

```haskell
import PlutusTx
import PlutusTx.Prelude
import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V2.Ledger.Contexts as V2Ctx
import qualified Plutus.V1.Ledger.Value    as Value
```

* `V2Ctx.ownCurrencySymbol ctx` – identifies the policy’s own `CurrencySymbol`.
* `Value.flattenValue (V2.txInfoMint info)` – sees exactly what is minted/burned.
* Used to enforce:

  * organiser signed,
  * exactly one `(cs, seatTokenName, amount)` under this policy,
  * no extra tokens under this policy.

---

### 6.4 Serialization stack

The serialization stack is used only in the **writer executables** (e.g. `SportsTickets.hs`) to convert the compiled validator into a `.plutus` file.

```haskell
import qualified Codec.Serialise       as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
import qualified Data.ByteString       as BS
```

How they work together in `SportsTickets.hs`:

1. **Serialise** the validator:

   ```haskell
   let bytes    = Serialise.serialise validator       -- lazy ByteString
   ```

2. Convert between byte representations:

   ```haskell
   let strict   = LBS.toStrict bytes                  -- strict ByteString
       short    = SBS.toShort strict                  -- ShortByteString
   ```

3. Use:

   * `short` when constructing `C.PlutusScript C.PlutusScriptV2`.
   * The same bytes (via `Builtins.toBuiltin`) when building a `PlutusV2.ValidatorHash` in `plutusValidatorHash`.

This stack never runs on-chain; it’s purely off-chain tooling to make:

* `sports-tickets.plutus`
* `revenue-splitter.plutus`
* `sports-tickets-policy.plutus`

usable by `cardano-cli` / wallets / scripts.

---

### 6.5 Cardano API imports

Finally, the **Cardano API** connects your Plutus code to the real Cardano node & CLI ecosystem.

```haskell
import qualified Cardano.Api         as C
import qualified Cardano.Api.Shelley as CS
```

Used in **writer executables** like `SportsTickets.hs` to:

1. Wrap raw bytes as a Plutus script:

   ```haskell
   plutusScript :: C.PlutusScript C.PlutusScriptV2
   plutusScript = CS.PlutusScriptSerialised serialised
   ```

2. **Write a text envelope** `.plutus`:

   ```haskell
   C.writeFileTextEnvelope path (Just "Sports Tickets Plutus Validator") plutusScript
   ```

3. Compute a **script hash** and **Bech32 script address**:

   ```haskell
   scriptHash  = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)
   shelleyAddr = C.makeShelleyAddressInEra
                    network
                    (C.PaymentCredentialByScript scriptHash)
                    C.NoStakeAddress
   bech32      = C.serialiseAddress shelleyAddr
   ```

This is what lets you:

* Take the on-chain validator from Haskell,
* Turn it into a `.plutus` file,
* Use it with:

  ```bash
  cardano-cli transaction build \
    --tx-in-script-file sports-tickets.plutus \
    ...
  ```

---

## 7. Ticket Validator Logic (`SportsTicketsContract`)

The core validator lives in:

```haskell
mkTicketValidator :: TicketDatum -> TicketRedeemer -> ScriptContext -> Bool
```

It branches on the redeemer:

* `Transfer newOwner price` – resale / secondary-market transfer.
* `UseAtGate` – gate scan at the venue entrance.

Before looking at each branch, it’s useful to understand the shared helpers that enforce:

* **ticket identity binding** (NFT must be present),
* **safe state transitions** (owner changes only as allowed),
* **no “ghost” tickets** (no extra script outputs or unexpected tokens),
* **mint/burn patterns** for gate usage.

---
 
### 7.1 Shared helpers

#### `info`, `txRange`, `ticketNftBound`

These helpers are used in both branches to get transaction context and enforce that the script input really is *the* ticket UTxO.

```haskell
{-# INLINABLE info #-}
info :: ScriptContext -> TxInfo
info = scriptContextTxInfo

{-# INLINABLE txRange #-}
txRange :: ScriptContext -> POSIXTimeRange
txRange = txInfoValidRange . info
```

* `info ctx` – extracts the `TxInfo` from the `ScriptContext`.

  * This contains inputs, outputs, signatures, minted tokens, validity range, etc.
* `txRange ctx` – convenience helper for the **validity time range** of the transaction.

These are used to:

* Check **signatures** (`txSignedBy (info ctx) ...`).
* Check **time** (with `Interval.contains` and `txRange`).
* Inspect **minting**, payments, and script outputs.

---

##### `ticketNftBound`

```haskell
{-# INLINABLE ticketNftBound #-}
ticketNftBound :: TicketDatum -> ScriptContext -> Bool
ticketNftBound dat ctx =
  case findOwnInput ctx of
    Nothing  -> traceIfFalse "ticket input missing" False
    Just inp ->
      let v       = txOutValue (txInInfoResolved inp)
          triples = flattenValue v
          ours    =
            [ amt
            | (cs, tn, amt) <- triples
            , cs == tdPolicyId dat
            , tn == tdTokenName dat
            ]
      in case ours of
           [1] -> True
           _   -> traceIfFalse "expected exactly one matching ticket NFT in input" False
```

This enforces that **the script input UTxO is uniquely bound to the ticket NFT**:

* It looks up the **UTxO being spent from this script** via `findOwnInput ctx`.

* It flattens its `Value` and filters for:

  * `CurrencySymbol == tdPolicyId dat`
  * `TokenName == tdTokenName dat`

* It requires **exactly one entry with amount `1`**:

  * If there is no such entry, or multiple, or a different amount → the ticket is invalid.

This prevents:

* Spending a script UTxO that *pretends* to be this ticket but doesn’t hold the correct NFT.
* Double-counting / mis-binding scenarios where there are multiple ticket NFTs in the same UTxO.

> Think of `ticketNftBound` as: “is the script really guarding this single, specific ticket token?”

---

#### `getContinuingOutput` and `datumFromOutput`

These helpers ensure **safe state transitions** for the `Transfer` branch.

##### `getContinuingOutput`

```haskell
{-# INLINABLE getContinuingOutput #-}
getContinuingOutput :: ScriptContext -> TxOut
getContinuingOutput ctx =
  let ti   = info ctx
      vh   = ownHash ctx
      outs = txInfoOutputs ti
      isOwn o = case txOutAddress o of
                  Address (ScriptCredential vh') _ -> vh' == vh
                  _                                -> False
      ownOuts = filter isOwn outs
  in case ownOuts of
       [o] -> o
       _   -> traceError "expected exactly one continuing ticket output"
```

* It computes the script’s own `ValidatorHash` via `ownHash ctx`.
* It scans all **outputs** and keeps only those whose `Address` is a **script address with this hash**.
* It requires **exactly one** such output.

If there are:

* **Zero** continuing outputs → for `Transfer`, this is invalid (you’d be destroying the ticket without gate use).
* **More than one** → that would create multiple script UTxOs and effectively duplicate the ticket’s logical state.

So, for transfers:

> There must be exactly one “next state” ticket UTxO at the script.

##### `datumFromOutput`

```haskell
{-# INLINABLE datumFromOutput #-}
datumFromOutput :: TxOut -> TicketDatum
datumFromOutput o =
  case txOutDatum o of
    OutputDatum (Datum d) -> unsafeFromBuiltinData d
    _                     -> traceError "expected inline datum on continuing output"
```

* Expects the continuing output to have an **inline datum**.
* Decodes that datum into a `TicketDatum`.

If it’s not inline, or if it’s missing, the script fails.

This guarantees:

* The new ticket state is explicitly present as a `TicketDatum` on the continuing UTxO.
* Off-chain code can build the new datum, and on-chain code checks that it is structurally correct.

---

#### `ticketStaticFieldsEqual` and `noContinuingOutput`

These helpers enforce **immutability of certain ticket fields** and ensure no “zombie” ticket remains after gate use.

##### `ticketStaticFieldsEqual`

```haskell
{-# INLINABLE ticketStaticFieldsEqual #-}
ticketStaticFieldsEqual :: TicketDatum -> TicketDatum -> Bool
ticketStaticFieldsEqual old new =
       tdEventId old      == tdEventId new
    && tdSeat old         == tdSeat new
    && tdFaceValue old    == tdFaceValue new
    && tdMaxPrice old     == tdMaxPrice new
    && tdEventTime old    == tdEventTime new
    && tdKycAuthority old == tdKycAuthority new
    && tdPolicyId old     == tdPolicyId new
    && tdTokenName old    == tdTokenName new
```

This enforces that, between the **old datum** and the **new datum**:

* **Cannot change**:

  * `tdEventId`      – same event.
  * `tdSeat`         – same seat.
  * `tdFaceValue`    – original primary price stays in history.
  * `tdMaxPrice`     – anti-scalping cap remains the same.
  * `tdEventTime`    – gate time does not move.
  * `tdKycAuthority` – no sneaky removal of a KYC requirement.
  * `tdPolicyId` / `tdTokenName` – still the **same ticket NFT**.

Only fields allowed to change in a transfer:

* `tdOwner` – current holder.
* `tdUsed` – only in gate branch (UseAtGate) / conceptual; in this contract `UseAtGate` consumes the UTxO entirely.
* `tdUsedPolicyId` – stays fixed, it doesn’t change.

In practice, `ticketStaticFieldsEqual` is used inside `ticketStateTransitionOk` to assert:

> “All static aspects of the ticket remained the same across a Transfer; only the owner changed.”

##### `noContinuingOutput`

```haskell
{-# INLINABLE noContinuingOutput #-}
noContinuingOutput :: ScriptContext -> Bool
noContinuingOutput ctx =
  let vh   = ownHash ctx
      outs = txInfoOutputs (scriptContextTxInfo ctx)
      isOwn o = case txOutAddress o of
                  Address (ScriptCredential vh') _ -> vh' == vh
                  _                                -> False
  in all (not . isOwn) outs
```

* Checks that **no outputs** in the transaction go back to this script’s address.
* Used in the **`UseAtGate`** branch to enforce:

  > After the gate scan, there is **no more ticket at the script**.
  > The ticket is fully consumed; only the USED souvenir remains.

This ensures:

* Tickets cannot be “double-used” by keeping a script UTxO alive.
* Gate use is a true **one-way transition** (ticket → USED souvenir).

---

### 7.2 Transfer branch (`Transfer newOwner price`)

The transfer branch handles **resale** of tickets on a secondary market or P2P transfer, under these rules:

* Ticket must exist and be un-used.
* Current owner must sign.
* Optional KYC authority must also sign (if configured).
* Price cannot exceed `tdMaxPrice`.
* Owner must be paid exactly the `price`.
* Owner must change (no dummy self-transfer).
* New state must preserve all static fields and the ticket NFT.

The core function:

```haskell
{-# INLINABLE validateTransfer #-}
validateTransfer :: TicketDatum -> PubKeyHash -> Integer -> ScriptContext -> Bool
validateTransfer dat newOwner price ctx =
       traceIfFalse "ticket NFT missing / invalid" ticketHasNft
    && traceIfFalse "ticket already used"          ticketNotUsed
    && traceIfFalse "owner signature missing"      ownerSigned
    && traceIfFalse "kyc signature missing"        kycOk
    && traceIfFalse "resale price too high"        withinCap
    && traceIfFalse "owner unchanged"              ownerChanges
    && traceIfFalse "owner not paid correctly"     ownerPaidCorrectly
    && traceIfFalse "ticket state invalid"         stateOk
    && traceIfFalse "ticket state invalid"         (ticketStateTransitionOk dat newOwner ctx)
```

We’ll unpack each condition.

---

#### 1. Ticket NFT must be present and correct

```haskell
ticketHasNft :: Bool
ticketHasNft = ticketNftBound dat ctx
```

* Uses the helper described above.
* Enforces **exactly one** matching `(tdPolicyId, tdTokenName)` in the script input UTxO.

**Effect:** You cannot transfer a “ticket” datum that is not backed by the correct NFT.

---

#### 2. Ticket must be unused

```haskell
ticketNotUsed :: Bool
ticketNotUsed = not (tdUsed dat)
```

* Ensures you cannot transfer an already-used ticket.
* In this contract’s actual gate design, `UseAtGate` consumes the UTxO entirely and there is no continuing ticket, but keeping `tdUsed` in the datum enforces the model consistently if extended.

**Effect:** Secondary sales only apply to **fresh** tickets.

---

#### 3. Owner must sign, and KYC authority if any

```haskell
ownerSigned :: Bool
ownerSigned = txSignedBy ti (tdOwner dat)

kycOk :: Bool
kycOk =
  case tdKycAuthority dat of
    Nothing      -> True
    Just authPkh -> txSignedBy ti authPkh
```

* `ownerSigned` – the current `tdOwner` must sign the transaction.
* `kycOk` – if `tdKycAuthority = Just pkh`, that pkh must also sign.

**Effect:**

* Prevents stolen tickets from being transferred without the owner’s key.
* Allows optional KYC/co-sign policies enforced purely on-chain (e.g. organiser signs all transfers or supervised marketplace).

---

#### 4. Price must respect the cap, owner must change

```haskell
withinCap :: Bool
withinCap = price <= tdMaxPrice dat

ownerChanges :: Bool
ownerChanges = newOwner /= tdOwner dat
```

* `withinCap` – prevents scalping above `tdMaxPrice`.
* `ownerChanges` – rules out meaningless transfers where the owner does not change.

**Effect:**

* Ensures resale stays within allowed limits.
* Guarantees that `Transfer` actually performs a **change in ownership**.

---

#### 5. Owner must be paid exactly the declared price

```haskell
actualPaidAda :: Integer
actualPaidAda =
  let v = valuePaidTo ti (tdOwner dat)
  in valueOf v adaSymbol adaToken

ownerPaidCorrectly :: Bool
ownerPaidCorrectly = actualPaidAda == price
```

* `valuePaidTo ti (tdOwner dat)` computes everything the owner receives in **all outputs**.
* `valueOf ... adaSymbol adaToken` extracts the **ADA** portion.
* This must match exactly the `price` in the redeemer.

**Effect:**

* The `price` in the redeemer is **not just a hint**; it must match actual ADA paid.
* Someone cannot underpay or overpay relative to the declared on-chain price.

> 🔎 Combined with `withinCap`, this ensures the **real** sale price is both:
>
> * exactly what the redeemer claims, and
> * not above the configured cap.

---

#### 6. Ticket state transition must be correct (`ticketStateTransitionOk`)

This helper is where most of the Transfer invariants live.

```haskell
{-# INLINABLE ticketStateTransitionOk #-}
ticketStateTransitionOk :: TicketDatum -> PubKeyHash -> ScriptContext -> Bool
ticketStateTransitionOk dat newOwner ctx =
  let out    = getContinuingOutput ctx
      outDat = datumFromOutput out

      -- must still hold exactly 1 of *this* ticket NFT
      nftOk  = valueOf (txOutValue out) (tdPolicyId dat) (tdTokenName dat) == 1

      -- forbid any other non-ADA assets in the continuing output
      nonAdaTriples =
        [ (cs, tn, amt)
        | (cs, tn, amt) <- flattenValue (txOutValue out)
        , not (cs == adaSymbol && tn == adaToken)
        ]

      onlyThisNft :: Bool
      onlyThisNft =
        case nonAdaTriples of
          [(cs, tn, amt)] -> cs == tdPolicyId dat && tn == tdTokenName dat && amt == 1
          _               -> False
  in     traceIfFalse "ticket NFT not preserved in output" nftOk
     &&  traceIfFalse "continuing output contains extra non-ADA tokens" onlyThisNft
     &&  traceIfFalse "owner not updated to new owner"     (tdOwner outDat == newOwner)
     &&  traceIfFalse "static ticket fields changed"       (ticketStaticFieldsEqual dat outDat)
     &&  traceIfFalse "used flag changed on transfer"      (tdUsed outDat == tdUsed dat)
```

Breakdown:

1. **Exactly one continuing output at this script**
   – enforced by `getContinuingOutput ctx`.
   Any deviation (0 or >1) is rejected.

2. **Ticket NFT preserved:**

   ```haskell
   nftOk =
     valueOf (txOutValue out) (tdPolicyId dat) (tdTokenName dat) == 1
   ```

   * The continuing output must still hold *exactly one* of the ticket NFT.

3. **No extra non-ADA tokens:**

   ```haskell
   nonAdaTriples =
     [ (cs, tn, amt)
     | (cs, tn, amt) <- flattenValue (txOutValue out)
     , not (cs == adaSymbol && tn == adaToken)
     ]

   onlyThisNft =
     case nonAdaTriples of
       [(cs, tn, amt)] -> cs == tdPolicyId dat && tn == tdTokenName dat && amt == 1
       _               -> False
   ```

   * Among all non-ADA assets in the output:

     * There must be **exactly one triple**.
     * It must match the ticket NFT with amount `1`.
   * No airdrops, no bundled extra tokens; just ADA + the ticket.

4. **Owner updated correctly:**

   ```haskell
   tdOwner outDat == newOwner
   ```

   * The new datum’s `tdOwner` must be the `newOwner` from the redeemer.

5. **Static fields unchanged:**

   ```haskell
   ticketStaticFieldsEqual dat outDat
   ```

   * All immutable fields (event id, seat, caps, event time, KYC, NFT ids) must stay the same.

6. **`tdUsed` unchanged on transfer:**

   ```haskell
   tdUsed outDat == tdUsed dat
   ```

   * Transfer alone should not mark the ticket as used.
   * Marking used is a **gate-only** privilege (UseAtGate branch conceptually; here the gate burns the UTxO instead).

The `validateTransfer` function then calls this twice (once via `stateOk`, once directly), which is redundant but safe; it ensures the transition is checked.

**Overall effect:**

> A Transfer can only:
>
> * change the `tdOwner`,
> * keep the ticket NFT exactly intact,
> * preserve all core ticket attributes,
> * keep `tdUsed` unchanged,
> * respect price limits and payments.

---

### 7.3 UseAtGate branch (`UseAtGate`)

The `UseAtGate` branch enforces the **gate scan** logic: the ticket is validated, consumed, and converted into a USED souvenir.

```haskell
{-# INLINABLE validateUseAtGate #-}
validateUseAtGate :: TicketDatum -> ScriptContext -> Bool
validateUseAtGate dat ctx =
       traceIfFalse "ticket NFT missing / invalid"        ticketHasNft
    && traceIfFalse "ticket already used"                 ticketNotUsed
    && traceIfFalse "too late for entry"                  beforeOrAtEventTime
    && traceIfFalse "must burn 1 ticket NFT"              burnedExactlyOne
    && traceIfFalse "must mint 1 USED souvenir"           mintedExactlyOne
    && traceIfFalse "unexpected extra minting"            noExtraMinting
    && traceIfFalse "USED souvenir not paid to owner"     souvenirPaidToOwner
    && traceIfFalse "no continuing output expected"       noContinuingOutput ctx
  where
    ti :: TxInfo
    ti = info ctx

    ticketHasNft :: Bool
    ticketHasNft = ticketNftBound dat ctx

    ticketNotUsed :: Bool
    ticketNotUsed = not (tdUsed dat)
```

We saw the high-level flow in Section 3.3; here’s how the code enforces it.

---

#### 1. Ticket existence + unused status

* `ticketHasNft` – same `ticketNftBound dat ctx` as in Transfer.
* `ticketNotUsed` – again enforces it hasn’t been marked as used.

Even though `UseAtGate` **burns** the ticket and leaves no continuing output, these checks ensure:

* You can only gate-scan a UTxO that truly holds this ticket NFT.
* You can’t gate-scan a datum that already flagged `tdUsed = True`.

---

#### 2. Time restriction: on or before `tdEventTime`

```haskell
beforeOrAtEventTime :: Bool
beforeOrAtEventTime =
  Interval.contains (Interval.to (tdEventTime dat)) (txRange ctx)
```

* Requires the transaction’s validity range (`txRange ctx`) to be contained in `to tdEventTime`.
* This means:

  * The tx must be valid at or before `tdEventTime`.
  * You **cannot** enter after the event time (strict rule).

---

#### 3. Mint/burn keys: `usedTokenName`, `mintedAmountOf`, `valuePaidOf`

These helpers are used here:

```haskell
csTicket = tdPolicyId     dat
tn       = tdTokenName    dat
csUsed   = tdUsedPolicyId dat
utn      = usedTokenName  tn
```

**`usedTokenName`**

```haskell
{-# INLINABLE usedTokenName #-}
usedTokenName :: TokenName -> TokenName
usedTokenName tn =
  TokenName (Builtins.appendByteString "USED-" (unTokenName tn))
```

* Derives a **souvenir token name** from the original ticket name, e.g.:

  * `TICKET-001` → `USED-TICKET-001`.

**`mintedAmountOf`**

```haskell
{-# INLINABLE mintedAmountOf #-}
mintedAmountOf :: CurrencySymbol -> TokenName -> ScriptContext -> Integer
mintedAmountOf cs tn ctx =
  let mintedTriples = flattenValue (txInfoMint (info ctx))
  in sum [ amt | (cs', tn', amt) <- mintedTriples, cs' == cs, tn' == tn ]
```

* Sums all **minted/burned amounts** for a given `(cs, tn)` from `txInfoMint`.
* Positive → mint; negative → burn.

**`valuePaidOf`**

```haskell
{-# INLINABLE valuePaidOf #-}
valuePaidOf :: PubKeyHash -> CurrencySymbol -> TokenName -> ScriptContext -> Integer
valuePaidOf pkh cs tn ctx =
  let v = valuePaidTo (info ctx) pkh
  in valueOf v cs tn
```

* Checks how many units of a given token are paid to a particular PKH in outputs.

These are the tools used to enforce the gate mint/burn pattern.

---

#### 4. Burn exactly one ticket, mint exactly one USED souvenir

```haskell
burnedExactlyOne :: Bool
burnedExactlyOne = mintedAmountOf csTicket tn  ctx == (-1)

mintedExactlyOne :: Bool
mintedExactlyOne = mintedAmountOf csUsed   utn ctx == 1
```

* The transaction must:

  * Burn exactly 1 ticket NFT (`-1` under `tdPolicyId/tdTokenName`).
  * Mint exactly 1 souvenir NFT (`+1` under `tdUsedPolicyId/usedTokenName`).

**Effect:**

* A ticket cannot be used without being destroyed at the policy level.
* A USED souvenir is always created 1:1 when a ticket is used.

---

#### 5. No extra minting

```haskell
noExtraMinting :: Bool
noExtraMinting =
  let mintedTriples = flattenValue (txInfoMint ti)
      allowed (cs, tnm, amt) =
           (cs == csTicket && tnm == tn  && amt == (-1))
        || (cs == csUsed   && tnm == utn && amt == 1)
  in  all allowed mintedTriples && length mintedTriples == 2
```

* It flattens the entire `txInfoMint`.
* It checks that:

  * Every triple matches either:

    * `(csTicket, tn, -1)` – ticket burn, or
    * `(csUsed, utn, 1)` – souvenir mint.
  * And there are exactly **two** triples in total.

**Effect:**

* No other tokens can be minted or burned in this transaction (including other tickets).
* Gate scan tx is “pure” — only concerned with **this** ticket → USED souvenir.

---

#### 6. USED souvenir goes to the owner

```haskell
souvenirPaidToOwner :: Bool
souvenirPaidToOwner = valuePaidOf (tdOwner dat) csUsed utn ctx == 1
```

* Using `valuePaidOf`:

  * It checks that **exactly 1** USED token is paid to the **current owner (`tdOwner dat`)**.

**Effect:**

* The attendee whose ticket is being consumed becomes the holder of the souvenir.
* Souvenir cannot be siphoned to someone else or left at the script.

---

#### 7. No continuing script output (`noContinuingOutput`)

Finally:

```haskell
traceIfFalse "no continuing output expected" (noContinuingOutput ctx)
```

* Uses the helper described earlier.
* Ensures **the script does not reappear as an output**.

**Effect:**

* After gate validation, the ticket UTxO is fully consumed.
* Only regular outputs remain (USED souvenir and ADA change).
* Prevents creating a new ticket UTxO to re-use later.

---

**Overall behaviour of `UseAtGate`:**

* Ticket must be valid and unused.
* Gate use must be at or before event time.
* One ticket NFT is burned.
* One USED souvenir NFT is minted under `tdUsedPolicyId`.
* That souvenir goes to the ticket owner.
* No other minting occurs.
* No ticket UTxO continues at the script.

This locks in the invariant:

> **Each ticket can be used at most once**, and the on-chain history clearly shows:
>
> * it existed (minted under the ticket policy),
> * it was consumed (burned),
> * it was used at the gate (USED souvenir minted to the owner).

---

## 8. Minting Policy Logic (`SportsTicketsPolicy`)

While the ticket validator controls **resale and gate usage**, the **minting policy** controls:

* **Who** is allowed to create/burn ticket NFTs.
* **How many** can be minted or burned per transaction.
* Ensuring there are no “extra” tokens under the same policy.

The core on-chain function:

```haskell
{-# INLINABLE mkTicketPolicy #-}
mkTicketPolicy :: TicketMintParams -> TicketMintRedeemer -> V2.ScriptContext -> Bool
```

There are two branches via the redeemer:

* `MintTicket seat` – mint **one** NFT for a specific seat.
* `BurnTicket seat` – burn **one** NFT for a specific seat.

Everything is parameterised by `TicketMintParams`, containing the event organiser and event id.

---

### 8.1 Parameters (`TicketMintParams` and organiser role)

```haskell
data TicketMintParams = TicketMintParams
  { tmpOrganizer :: V2.PubKeyHash       -- ^ Who is allowed to mint / burn
  , tmpEventId   :: BuiltinByteString   -- ^ Event id this policy is for
  }

PlutusTx.makeLift ''TicketMintParams
```

**`tmpOrganizer :: PubKeyHash`**

* The **organiser’s public key hash**.
* This key must **sign every mint or burn** under this policy.
* It acts as the **on-chain authority** for ticket creation/destruction.

Practical meaning:

* Only transactions signed by `tmpOrganizer` can:

  * Mint new seat tickets for the event.
  * Burn existing seat tickets (e.g. cleanup / admin operations).

**`tmpEventId :: BuiltinByteString`**

* A byte string that identifies the **event** (e.g. `"BOK-2025-FINAL"`).
* Not actively used in the policy logic itself, but important for:

  * Off-chain labelling,
  * Grouping policies by event,
  * Future extensions where you might enforce relations between event id and seat format.

`makeLift` lets these parameters be embedded at compile-time into the policy so we can have:

* One policy per event (with its own organiser + id),
* Multiple seat NFTs under that single event-specific policy.

---

### 8.2 `MintTicket seat` branch

Redeemer:

```haskell
data TicketMintRedeemer
  = MintTicket BuiltinByteString
  | BurnTicket BuiltinByteString
  deriving (Haskell.Eq, Haskell.Show)

PlutusTx.unstableMakeIsData ''TicketMintRedeemer
```

For minting:

```haskell
mkTicketPolicy params redeemer ctx =
  case redeemer of
    MintTicket seat ->
         traceIfFalse "organizer not signed" (signedByOrganizer info)
      && traceIfFalse "wrong minting for seat" (checkMint seat 1)
      && traceIfFalse "no extra tokens under this policy" noExtraUnderPolicy
    ...
  where
    info :: V2.TxInfo
    info = V2Ctx.scriptContextTxInfo ctx
```

**What this branch enforces:**

1. **Organiser must sign the transaction**

   ```haskell
   signedByOrganizer :: V2.TxInfo -> Bool
   signedByOrganizer txInfo =
     V2Ctx.txSignedBy txInfo (tmpOrganizer params)
   ```

   * The `tmpOrganizer` PKH must be in `txInfoSignatories`.
   * Prevents anyone else from minting/burning event tickets.

2. **Exactly one seat NFT is minted with amount `+1`**

   ```haskell
   minted :: [(V2.CurrencySymbol, Value.TokenName, Integer)]
   minted = Value.flattenValue (V2.txInfoMint info)

   checkMint :: BuiltinByteString -> Integer -> Bool
   checkMint seat expected =
     let tn   = Value.TokenName seat
         ours = [amt | (cs', tn', amt) <- minted, cs' == cs, tn' == tn]
     in case ours of
          [amt] -> amt == expected
          _     -> False
   ```

   * `cs` is the policy’s own `CurrencySymbol`:

     ```haskell
     cs :: V2.CurrencySymbol
     cs = V2Ctx.ownCurrencySymbol ctx
     ```

   * `Value.flattenValue` returns all mint/burn triples `(cs, tokenName, amount)`.

   * `checkMint seat 1` requires:

     * Find all minted/burned entries for this policy’s `cs` and the `TokenName seat`.
     * There must be **exactly one** such entry.
     * Its amount must be **`+1`**.

   Effect:

   > When using `MintTicket seat`, you must mint **exactly** 1 ticket NFT for that specific seat under this policy.

3. **No extra tokens under the same policy (see 8.4)**

   ```haskell
   traceIfFalse "no extra tokens under this policy" noExtraUnderPolicy
   ```

   This ensures you can’t sneak in additional tickets for other seats in the same transaction when using this redeemer.

---

### 8.3 `BurnTicket seat` branch

For burning:

```haskell
mkTicketPolicy params redeemer ctx =
  case redeemer of
    ...
    BurnTicket seat ->
         traceIfFalse "organizer not signed" (signedByOrganizer info)
      && traceIfFalse "burn must be -1" (checkMint seat (-1))
      && traceIfFalse "no extra tokens under this policy" noExtraUnderPolicy
```

**What this branch enforces:**

1. **Organiser must sign**

   * Same `signedByOrganizer info` as the mint branch.

   Effect:

   > Only the organiser can destroy tickets under this policy (e.g. event cancelled, admin cleanup, etc.).

2. **Exactly one seat NFT is burned with amount `-1`**

   * Uses **the same `checkMint` helper**, but this time `expected = -1`:

     ```haskell
     checkMint seat (-1)
     ```

   * Requires:

     * Exactly one triple with `(cs, TokenName seat, -1)` in `txInfoMint`.
     * No other triple for that `seat` under this `cs`.

   Effect:

   > Burning a seat ticket is a **precise** operation: one token for that seat is burned, no more, no less.

3. **No extra tokens under the same policy**

   * Again, enforced by `noExtraUnderPolicy` (see below).

---

### 8.4 Preventing extra tokens under the same policy

Beyond checking a specific `(seat, amount)`, the policy also enforces that the transaction does **not** mint or burn **any other token** for this `CurrencySymbol`:

```haskell
noExtraUnderPolicy :: Bool
noExtraUnderPolicy =
  let underThis = [(tn, amt) | (cs', tn, amt) <- minted, cs' == cs]
  in length underThis == 1
```

Breakdown:

* `minted` is the full flattened list:

  ```haskell
  minted :: [(V2.CurrencySymbol, Value.TokenName, Integer)]
  minted = Value.flattenValue (V2.txInfoMint info)
  ```

* `underThis` filters **only** entries where `cs' == cs` (this policy’s own symbol):

  ```haskell
  underThis = [(tn, amt) | (cs', tn, amt) <- minted, cs' == cs]
  ```

* And it requires:

  ```haskell
  length underThis == 1
  ```

  i.e. there is exactly **one** `(TokenName, amount)` pair affected by this policy.

Combined with `checkMint seat expected`, this means:

* For `MintTicket seat`:

  * You can only mint **exactly one** `TokenName seat` with amount `+1`.
  * No other seats or extra tokens can be minted under this same policy in the transaction.

* For `BurnTicket seat`:

  * You can only burn **exactly one** `TokenName seat` with amount `-1`.
  * No other seats or tokens can be burned under this same policy at the same time.

**Why this matters:**

* It gives strong, per-seat control:

  * You can tie UI / off-chain logic so that every seat mint is **one tx, one seat**, with `MintTicket "BLOCK-A-ROW-1-SEAT-10"`.
  * You avoid mistakes like accidentally minting **multiple seats** in one go under the same redeemer.

* Organiser-driven patterns:

  * Organiser can script ticket creation as a batch of transactions, each explicitly specifying a seat.
  * Validates that the smart contract, not just off-chain code, keeps seat-count correct per policy.

> 🔒 **Security intuition:**
> The minting policy ensures that **any change under this ticket policy is 1:1 and organiser-approved** – there’s always a clear `(seat, ±1)` operation, with no hidden extra tokens riding along.

---

## 9. Producing `sports-tickets.plutus` and `sports-tickets-policy.plutus`

The on-chain logic for tickets lives in **two different scripts**:

1. A **validator script** (`SportsTicketsContract`)
   → compiled + written by `sports-tickets-exe` into `sports-tickets.plutus`.

2. A **minting policy** (`SportsTicketsPolicy`)
   → compiled + written by `sports-tickets-policy-exe` into `sports-tickets-policy.plutus`.

Both executables follow the same core pattern:

* Take the in-memory Plutus script (`Validator` or `MintingPolicy`).
* Serialise it to CBOR using `serialise`.
* Wrap it in a **Cardano text envelope**.
* Save as `.plutus` on disk so `cardano-cli` can use it.

---

### 9.1 `sports-tickets-exe` (validator writer)

The **main module** `SportsTickets.hs` is an executable whose only job is to:

* Turn the Plutus **ticket validator** into a `.plutus` file.
* Print its hash and Bech32 script address for you to use off-chain.

Key pieces:

```haskell
module Main where

import SportsTicketsContract (validator)
```

Here `validator :: Validator` is the Plutus V2 script compiled from:

```haskell
mkTicketValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
validator :: Validator
validator =
  mkValidatorScript $$(PlutusTx.compile [|| mkTicketValidatorUntyped ||])
```

#### 9.1.1 Computing the Plutus validator hash

```haskell
plutusValidatorHash :: PlutusV2.Validator -> PlutusV2.ValidatorHash
plutusValidatorHash v =
  let bytes    = Serialise.serialise v        -- lazy ByteString
      strict   = LBS.toStrict bytes           -- ByteString
      short    = SBS.toShort strict           -- ShortByteString
      strictBS = SBS.fromShort short          -- back to ByteString
      builtin  = Builtins.toBuiltin strictBS  -- BuiltinByteString
  in PlutusV2.ValidatorHash builtin
```

What this is doing:

* `Serialise.serialise v` → CBOR of the validator.
* Convert between lazy/strict/short ByteStrings to get the raw bytes.
* Wrap it in a `BuiltinByteString`.
* Construct the **on-chain** `ValidatorHash`.

This hash is what defines the **script address** in Plutus-land and is what you see on-chain.

#### 9.1.2 Computing the Plutus script address

```haskell
plutusScriptAddress :: PlutusV2.Address
plutusScriptAddress =
  Address (ScriptCredential (plutusValidatorHash validator)) Nothing
```

* This is the low-level Plutus `Address`:

  * Payment credential = `ScriptCredential <validatorHash>`.
  * No staking part (`Nothing`).

You mainly use this inside tests or when reasoning about on-chain address structure.

#### 9.1.3 Bech32 script address via cardano-api

```haskell
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
```

Steps:

1. Serialise the validator to short bytes.
2. Wrap as `PlutusScriptV2` for `cardano-api`.
3. `hashScript` to get a `ScriptHash`.
4. Build a **Shelley script address** for a given network (`Testnet (NetworkMagic 1)` in your code).
5. Convert to Bech32 string with `serialiseAddress`.

This Bech32 address is what you’ll use to:

* Send ticket UTxOs (with `TicketDatum`) in real transactions.
* Fund the script in your testnet workflow.

#### 9.1.4 Writing `sports-tickets.plutus`

```haskell
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      description :: C.TextEnvelopeDescr
      description = "Sports Tickets Plutus Validator"

  result <- C.writeFileTextEnvelope path (Just description) plutusScript
  case result of
    Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
    Right ()  -> putStrLn $ "Validator written to: " <> path
```

* `writeFileTextEnvelope` creates a file like:

  ```jsonc
  {
    "type": "PlutusScriptV2",
    "description": "Sports Tickets Plutus Validator",
    "cborHex": "4e4d010000332222..."
  }
  ```

* That `.plutus` file is exactly what `cardano-cli` expects for `--tx-in-script-file`.

#### 9.1.5 What `main` prints

```haskell
main :: IO ()
main = do
  let network = C.Testnet (C.NetworkMagic 1)

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
```

Running:

```bash
cabal run sports-tickets-exe
```

does three things:

1. Writes **`sports-tickets.plutus`** in the current directory.
2. Prints the **Plutus validator hash** and **Plutus address** (for debugging / docs).
3. Prints the **Bech32 script address** you’ll use to lock ticket UTxOs.

---

### 9.2 `sports-tickets-policy-exe` (minting policy writer)

The **minting policy** is compiled separately and produces:

* A `.plutus` file: `sports-tickets-policy.plutus`.
* A **policy id** (script hash) you’ll use as `CurrencySymbol` when minting NFTs.

The executable (your `sports-tickets-policy-exe`) wires together:

* The on-chain policy:

  ```haskell
  ticketPolicy :: TicketMintParams -> V2.MintingPolicy
  ```

* With concrete parameters: `TicketMintParams { tmpOrganizer, tmpEventId }`.

When you ran:

```bash
cabal run sports-tickets-policy-exe
```

you saw output like:

```text
Minting policy written to: sports-tickets-policy.plutus

--- Sports Tickets Minting Policy Info ---
Script Hash: "873843ea464a6068cd8e29ca7729e9766766daa7973c19555ba798e0"
Policy Id:   "873843ea464a6068cd8e29ca7729e9766766daa7973c19555ba798e0"
------------------------------------------
Sports tickets minting policy generated successfully.
```

Let’s unpack what that executable is doing conceptually.

#### 9.2.1 Building `TicketMintParams` (organiser + event id)

Inside the writer module (your `Main` for policy) you do something like:

```haskell
let params = TicketMintParams
               { tmpOrganizer = organiserPkh
               , tmpEventId   = "EVENT-001"
               }
```

Where:

* `organiserPkh` is the on-chain `PubKeyHash` of the organiser.
* `tmpEventId` is a `BuiltinByteString` describing the event.

These params get “baked into” the policy:

```haskell
let policy :: V2.MintingPolicy
    policy = ticketPolicy params
```

Every token minted with this `.plutus` file will:

* Be governed by that specific organiser PKH,
* Conceptually belong to `tmpEventId`.

#### 9.2.2 Serialising the policy and computing the policy id

The writer script:

1. Serialises the `MintingPolicy` to CBOR.
2. Wraps it as `PlutusScriptV2`.
3. Uses `cardano-api` to compute a **script hash** (the policy id).

Conceptually:

```haskell
serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise policy
plutusScript = CS.PlutusScriptSerialised serialised

scriptHash :: C.ScriptHash
scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)
```

When converted to hex and printed as `"8738...98e0"`, that hex string is both:

* The **Script Hash** (cardano-api view),
* The **Policy Id** (ledger / wallet view),

and on-chain it corresponds to the `CurrencySymbol` you’ll use in:

* `Value.singleton policyId tokenName amount`,
* `flattenValue`, etc.

#### 9.2.3 Writing `sports-tickets-policy.plutus`

The logic is very similar to the validator writer:

```haskell
C.writeFileTextEnvelope
  "sports-tickets-policy.plutus"
  (Just "Sports Tickets Minting Policy")
  plutusScript
```

Result:

* A text envelope file containing the minting policy’s CBOR and a human-readable description.
* This file is what you pass to:

  ```bash
  cardano-cli transaction build \
    ... \
    --mint-script-file sports-tickets-policy.plutus \
    --mint "<amount> <policyId>.<tokenName>" \
    ...
  ```

#### 9.2.4 Why you need both `.plutus` files

* **`sports-tickets.plutus`** (validator)

  * Used when **spending** ticket UTxOs (transfer / resale / UseAtGate).
  * Passed as `--tx-in-script-file` (or similar) when your transaction consumes a ticket script UTxO.

* **`sports-tickets-policy.plutus`** (minting policy)

  * Used when **minting or burning** ticket NFTs (seats).
  * Passed as `--mint-script-file` when you create or destroy ticket tokens.

They represent two different pieces of the system:

* The validator controls **behaviour** of ticket UTxOs.
* The minting policy controls **existence** and **supply** of ticket NFTs.

---

## 10. Testing the Contracts

The **Sports Tickets** system is covered by two Haskell test modules:

* `SportsTicketsSpec.hs` – tests the **validator** (`SportsTicketsContract`).
* `SportsTicketsPolicySpec.hs` – tests the **minting policy** (`SportsTicketsPolicy`).

They both run under the shared `wspace-tests` test suite:

```bash
cabal test wspace-tests
```

This section explains **what** each group of tests is checking and **which on-chain rules** they correspond to.

---

### 10.1 What `SportsTicketsSpec` tests (validator)

`SportsTicketsSpec` focuses on the **UTxO validator** that controls ticket life-cycle:

* **Transfers / resales** (branch `Transfer newOwner price`).
* **Gate usage** (branch `UseAtGate`).

It directly exercises the core business rules described in Sections 3 & 7.

#### 10.1.1 Transfer tests

The `Transfer` group checks that **secondary market resales** obey:

* **Ownership & signatures**
* **Price caps**
* **Static field immutability**
* **Correct ticket NFT continuity**

The tests:

1. **`valid transfer passes (owner signed, price <= cap)`**

   Scenario:

   * Original owner = `pkhOwner`.
   * Buyer = `pkhBuyer`.
   * Price = `1_200_000` lovelace.
   * `tdMaxPrice = 1_500_000`.
   * Owner is in `txInfoSignatories`.

   The validator is expected to **accept** when:

   * Ticket is unused (`tdUsed = False`).
   * Owner signed.
   * Price ≤ cap.
   * New owner changes from `pkhOwner` to `pkhBuyer`.
   * Continuing script output:

     * Keeps exactly 1 ticket NFT `(tdPolicyId, tdTokenName)`.
     * Has only ADA + that one NFT (no extra tokens).
     * Preserves all static fields (event id, seat, face value, max price, event time, KYC).
     * Keeps `tdUsed` unchanged.

2. **`transfer fails when owner not signed`**

   Scenario:

   * Same as above, but `txInfoSignatories = []` (owner did **not** sign).

   Expected:

   * Fails at the check:

     ```haskell
     txSignedBy ti (tdOwner dat)
     ```

   This ensures **no one except the owner** can initiate a transfer of their ticket.

3. **`transfer fails when price is above cap`**

   Scenario:

   * Price set to `2_000_000` lovelace (> `tdMaxPrice = 1_500_000`).
   * Owner *does* sign.

   Expected:

   * Fails the cap check:

     ```haskell
     price <= tdMaxPrice dat
     ```

   This enforces your **anti-scalping rule**: resales can’t exceed the configured ceiling.

4. **`transfer fails if static fields change`**

   Scenario:

   * Build a normal valid transfer.
   * Then **tamper** with the continuing datum, e.g. change:

     ```haskell
     tdSeat = "BLOCK-Z-ROW-99-SEAT-99"
     ```

   Expected:

   * Fails the static field check:

     ```haskell
     ticketStaticFieldsEqual oldDat outDat == True
     ```

   This confirms that only the **owner** field may change in a resale; all other ticket metadata must remain identical.

5. **`transfer fails if continuing output lacks the ticket NFT`**

   Scenario:

   * The continuing script output is built with **no ticket NFT** in its `txOutValue`.
   * Owner is signed, price ≤ cap, etc.

   Expected:

   * Fails the checks in `ticketStateTransitionOk`:

     * Either `nftOk` is False:

       ```haskell
       valueOf (txOutValue out) (tdPolicyId dat) (tdTokenName dat) == 1
       ```

     * Or `onlyThisNft` fails (no non-ADA token there).

   This ensures there is **no way** to “strip” the ticket NFT out of the script state while still pretending to have a valid ticket UTxO.

---

#### 10.1.2 UseAtGate tests

The `UseAtGate` group tests the **entry scan** / gate logic:

* Ticket can only be used once.
* Usage must happen at or before event time.
* Correct burn/mint pattern for original vs USED souvenir token.
* USED souvenir must go to the ticket owner.
* No continuing script output.

Each test tweaks one condition:

1. **`unused ticket before event (burn + mint USED to owner) passes`**

   Scenario:

   * `tdUsed = False`.

   * `txInfoValidRange` is **before or at** `tdEventTime`.

   * Mint field:

     ```haskell
     -1 (tdPolicyId, tdTokenName)   -- burn 1 ticket
     +1 (tdUsedPolicyId, usedTokenName tn)  -- mint 1 USED souvenir
     ```

   * Outputs: one UTxO to `tdOwner` with exactly 1 USED NFT under `tdUsedPolicyId`.

   Expected:

   * `validateUseAtGate` returns True:

     * Ticket NFT still in input.
     * Not used yet.
     * Time in range.
     * Mint/burn pattern exactly matches.
     * USED goes to owner.
     * `noContinuingOutput` holds.

2. **`already-used ticket fails at gate`**

   Scenario:

   * Same as above, but `tdUsed = True` in the datum.

   Expected:

   * Fails `ticketNotUsed = not (tdUsed dat)`.

   This prevents **double entry**: a ticket marked as used should never validate `UseAtGate` again.

3. **`ticket after event time fails`**

   Scenario:

   * `tdUsed = False`.
   * Validity range is **after** `tdEventTime` (using `Interval.from (eventTime + 1)`).

   Expected:

   * Fails time condition:

     ```haskell
     Interval.contains (Interval.to (tdEventTime dat)) (txRange ctx)
     ```

   So you can’t enter the gate with that ticket after the event time window.

4. **`missing burn of original ticket fails`**

   Scenario:

   * Mint only the USED souvenir:

     ```haskell
     +1 USED
     ```

   * Do **not** burn the original ticket.

   Expected:

   * Fails:

     ```haskell
     mintedAmountOf csTicket tn ctx == (-1)
     ```

   This prevents minting a USED token without consuming the corresponding ticket.

5. **`missing mint of USED souvenir fails`**

   Scenario:

   * Burn the original ticket:

     ```haskell
     -1 (ticket NFT)
     ```

   * But **don’t** mint the USED souvenir.

   * Also, the outputs list is empty (no souvenir output).

   Expected:

   * Fails:

     ```haskell
     mintedAmountOf csUsed utn ctx == 1
     ```

   You can’t burn the ticket without issuing the “proof of entry” NFT.

6. **`USED souvenir not sent to owner fails`**

   Scenario:

   * Mint & burn pattern is correct.
   * But the USED souvenir is sent to **another PKH** (`pkhBuyer`).

   Expected:

   * Fails:

     ```haskell
     valuePaidOf (tdOwner dat) csUsed utn ctx == 1
     ```

   This ensures the USED token is a **soul-bound style souvenir** for the actual holder of the ticket.

7. **`USED souvenir under wrong policy fails`**

   Scenario:

   * Burn the original ticket under `tdPolicyId`.
   * Mint the USED souvenir under a **different `CurrencySymbol`** (wrong policy).

   Expected:

   * The mint checks (`mintedAmountOf`, `noExtraMinting`) and/or `souvenirPaidToOwner` fail, because:

     * The minted USED triple doesn’t match `tdUsedPolicyId`.

   This prevents someone from “forging” USED souvenirs under a fake policy.

8. **`USED souvenir minted but not paid to owner fails`**

   Scenario:

   * Burn original ticket, mint USED under correct policy.
   * But send the USED token to the **script address** (not to owner).

   Expected:

   * Fails `souvenirPaidToOwner`.

   This confirms the on-chain rule: **only the owner wallet** can receive the newly minted USED NFT; it must not stay locked in the script.

---

### 10.2 What `SportsTicketsPolicySpec` tests (minting policy)

`SportsTicketsPolicySpec` tests the **minting policy** that governs creation and destruction of ticket NFTs (one per seat).

The tests map directly to `mkTicketPolicy` rules:

1. **Minting tests (`MintTicket`)**

   * **`organiser-signed, correct +1 mint`**

     * txInfo:

       * `txSignedBy info (tmpOrganizer params)` is True.

       * `txInfoMint` contains exactly:

         ```haskell
         +1 (cs, TokenName seat)
         ```

       * Nothing else under this policy id.

     * Expected: policy returns True.

   * **`missing organiser signature fails`**

     * Same mint pattern, but organiser PKH **doesn’t sign**.

     * Expected: fails `signedByOrganizer`.

   * **`wrong amount (2 instead of 1) fails`**

     * Mint 2 of the seat token instead of 1.

     * Expected: fails `checkMint seat 1` because amount ≠ 1.

     This enforces “**one NFT per seat**” per mint transaction.

   * **`extra NFTs under same policy fails`**

     * Include more than one `(CurrencySymbol == cs, TokenName, amt)` triple in `flattenValue txInfoMint`.

     * Example: mint seat A and seat B in the same tx under the same policy.

     * Expected: fails `noExtraUnderPolicy` where `length underThis == 1`.

     This keeps each transaction focused on a **single seat token** for clarity and reduces complexity in the dApp flow.

2. **Burning tests (`BurnTicket`)**

   * **`organiser-signed, -1 burn passes`**

     * Organiser signs.

     * `txInfoMint` includes exactly:

       ```haskell
       -1 (cs, TokenName seat)
       ```

     * No other tokens under that policy.

     * Expected: policy returns True.

   * **`burn with wrong amount fails`**

     * Same seat, but amount is e.g. `-2` or `0`.

     * Expected: fails `checkMint seat (-1)`.

   * **`burn without organiser signature fails`**

     * Correct `-1` pattern, but organiser does not sign.

     * Expected: fails organizer check.

Together, these tests guarantee:

* **Only the organiser** (defined in `TicketMintParams`) can mint/burn seat tickets.
* Each policy transaction is **minimal and precise**:

  * **Mint**: exactly one seat NFT, +1.
  * **Burn**: exactly that seat NFT, -1.
  * No batch mint/burn under the same policy in a single tx.

---

### 10.3 Running the tests

All tests are wired into the `wspace-tests` suite in your `.cabal` file:

```cabal
test-suite wspace-tests
  ...
  other-modules:
    ...
    SportsTicketsContract
    SportsTicketsSpec
    SportsTicketsPolicy
    RevenueSplitterContract
    RevenueSplitterSpec
```

To run the full suite:

```bash
# (optional) enter Nix dev shell first
nix develop

# run all tests
cabal test wspace-tests
```

You should see output sections like:

```text
SportsTickets (on-chain v1)
  Transfer
    valid transfer passes (owner signed, price <= cap):            OK
    transfer fails when owner not signed:                          OK
    transfer fails when price is above cap:                        OK
    transfer fails if static fields change:                        OK
    transfer fails if continuing output lacks the ticket NFT:      OK
  UseAtGate
    unused ticket before event (burn + mint USED to owner) passes: OK
    already-used ticket fails at gate:                             OK
    ticket after event time fails:                                 OK
    missing burn of original ticket fails:                         OK
    missing mint of USED souvenir fails:                           OK
    USED souvenir not sent to owner fails:                         OK
    USED souvenir under wrong policy fails:                        OK
    USED souvenir minted but not paid to owner fails:              OK

SportsTicketsPolicy (NFT minting)
  MintTicket
    organiser-signed, correct +1 mint:                             OK
    missing organiser signature fails:                             OK
    wrong amount (2 instead of 1) fails:                           OK
    extra NFTs under same policy fails:                            OK
  BurnTicket
    organiser-signed, -1 burn passes:                              OK
    burn with wrong amount fails:                                  OK
    burn without organiser signature fails:                        OK
```

To run **just** the Sports Tickets tests, you can filter with `-p`:

```bash
cabal test wspace-tests -p SportsTickets
```

Or even a single case, e.g.:

```bash
cabal test wspace-tests \
  -p '/transfer fails if continuing output lacks the ticket NFT/'
```

This tight feedback loop lets you evolve the contract while staying confident that:

* Resale rules (price caps, signatures, NFT continuity) are enforced.
* Gate usage (time, burn/mint, souvenir recipient, no double-use) is correct.
* Minting policy (organiser, per-seat minting/burning) behaves exactly as specified.

---

## 11. Glossary of Terms

### 11.1 NFT ticket

An **NFT ticket** is a *non-fungible token* that represents a specific right to attend an event.

In this contract:

* It is identified by:

  * `tdPolicyId  :: CurrencySymbol`
  * `tdTokenName :: TokenName`

* Each **seat** is modeled as a **unique NFT** under the organiser’s ticket policy.

* On-chain, the validator checks that:

  * The script input contains exactly **1 ticket NFT**.
  * The continuing script output (for resales) keeps exactly **that same NFT**.

You can think of the NFT ticket as the **digital twin** of the physical seat: whoever controls that NFT (subject to validator rules) controls the entry right.

---

### 11.2 Primary sale / face value

The **primary sale** is the **first sale** of a ticket from organiser → fan.

* `tdFaceValue :: Integer`
  stores the **primary sale price** in lovelace.

Characteristics:

* Typically = official ticket price set by the organiser.
* It’s a **reference value** used in pricing and reporting.
* The contract doesn’t force resales to equal face value, but combined with `tdMaxPrice` and off-chain logic, you can enforce policies like “resale ≤ 110% of face value”.

---

### 11.3 Resale cap (`tdMaxPrice`)

`tdMaxPrice :: Integer` is the **maximum allowed resale price** for a ticket (in lovelace).

* Used in the `Transfer newOwner price` branch.
* The redeemer declares a resale `price`, and the validator checks:

  ```haskell
  price <= tdMaxPrice dat
  ```

Purpose:

* Enforces **anti-scalping** rules on secondary market.
* You can set:

  * `tdMaxPrice = tdFaceValue` → no profit resales.
  * or some margin above – e.g. `1.10 * faceValue`.

If someone tries to sell above `tdMaxPrice`, the validator rejects the transfer.

---

### 11.4 KYC authority (`tdKycAuthority`)

`tdKycAuthority :: Maybe PubKeyHash` optionally encodes a **KYC / compliance authority**.

* `Nothing` → **no extra signature** needed; only ticket owner must sign for transfers.
* `Just kycPkh` → any `Transfer` must be signed by:

  * the current ticket owner, and
  * this `kycPkh` address (regulator / KYC provider / venue admin).

Validator logic:

```haskell
kycOk :: Bool
kycOk =
  case tdKycAuthority dat of
    Nothing      -> True
    Just authPkh -> txSignedBy ti authPkh
```

Use cases:

* High-value events or regions requiring identity checks.
* Whitelisted resale platforms where KYC provider “co-signs” legitimate transfers.

---

### 11.5 USED souvenir token (`tdUsedPolicyId` + `usedTokenName`)

When a ticket is used at the gate, the system:

* **Burns** the original ticket NFT.
* **Mints** a **USED souvenir token** to the owner.

On-chain:

* `tdUsedPolicyId :: CurrencySymbol` – policy for USED souvenirs.
* `usedTokenName :: TokenName` – derived as:

  ```haskell
  usedTokenName tn = TokenName ("USED-" <> unTokenName tn)
  ```

So for a ticket named `"TICKET-001"` you get:

* Ticket: `"TICKET-001"`
* Souvenir: `"USED-TICKET-001"`

The `UseAtGate` branch enforces that:

* Exactly **1 ticket NFT** is burned.
* Exactly **1 USED souvenir** under `tdUsedPolicyId` is minted.
* That USED token goes to the **ticket owner** (not a random address or script).

This creates a **verifiable on-chain record** that:

* The ticket was truly used to enter.
* The owner retains a non-transferable / symbolic proof of attendance if you wish (or you can allow them to trade it as a collectible).

---

### 11.6 Gate / entry scan (`UseAtGate`)

`UseAtGate` is the **gate entry** path of `TicketRedeemer`:

```haskell
data TicketRedeemer
  = Transfer PubKeyHash Integer
  | UseAtGate
```

When a gate scan happens:

* The **validator** executes the `UseAtGate` branch.
* It checks:

  * Ticket still exists in input.
  * Ticket is not already marked used (by rules).
  * Transaction’s time range is **at or before** `tdEventTime`.
  * Correct mint/burn pattern for ticket vs USED souvenir.
  * USED souvenir goes to ticket owner.
  * There is **no continuing ticket UTxO**.

Conceptually:

> A `UseAtGate` transaction means “let this attendee in, and mark their ticket as consumed, issuing a souvenir in return”.

---

### 11.7 Datum (`TicketDatum`)

A **datum** is on-chain data attached to a script UTxO.

Here:

```haskell
data TicketDatum = TicketDatum
  { tdEventId      :: BuiltinByteString
  , tdSeat         :: BuiltinByteString
  , tdOwner        :: PubKeyHash
  , tdUsed         :: Bool
  , tdFaceValue    :: Integer
  , tdMaxPrice     :: Integer
  , tdEventTime    :: POSIXTime
  , tdKycAuthority :: Maybe PubKeyHash
  , tdPolicyId     :: CurrencySymbol
  , tdTokenName    :: TokenName
  , tdUsedPolicyId :: CurrencySymbol
  }
```

It encodes the **state of a single ticket**:

* Which event (`tdEventId`).
* Which seat (`tdSeat`).
* Who owns it (`tdOwner`).
* Whether it’s used (`tdUsed`).
* Price info (`tdFaceValue`, `tdMaxPrice`).
* Timing (`tdEventTime`).
* Optional KYC authority.
* Link to the exact ticket NFT and used souvenir policy.

The validator can read this datum and decide if:

* A resale is allowed.
* A gate usage is valid.

---

### 11.8 Redeemer (`TicketRedeemer`)

A **redeemer** is the “action” provided when spending a script UTxO.

Here:

```haskell
data TicketRedeemer
  = Transfer PubKeyHash Integer
  | UseAtGate
```

* `Transfer newOwner price`

  * Means: “I want to resell/transfer this ticket to `newOwner` for `price`.”
  * Validator checks:

    * owner + optional KYC signatures,
    * `price <= tdMaxPrice`,
    * owner paid correctly,
    * ticket NFT preserved in a correct continuing output,
    * static fields unchanged.

* `UseAtGate`

  * Means: “I want to consume this ticket at the venue gate.”
  * Triggers burn+mint of ticket vs USED tokens, time checks, and no continuing ticket UTxO.

---

### 11.9 Minting policy

A **minting policy** controls *creation and destruction* of tokens under a given `CurrencySymbol`.

In this system:

* `SportsTicketsPolicy` defines a minting policy for **ticket NFTs**.

* Parameters:

  ```haskell
  data TicketMintParams = TicketMintParams
    { tmpOrganizer :: PubKeyHash
    , tmpEventId   :: BuiltinByteString
    }
  ```

* Redeemer:

  ```haskell
  data TicketMintRedeemer
    = MintTicket BuiltinByteString
    | BurnTicket BuiltinByteString
  ```

Rules:

* Only `tmpOrganizer` may sign mint/burn transactions.
* Each tx can only mint/burn **one seat token** under this policy (one entry in `flattenValue` for this `CurrencySymbol`).
* Mint path: `+1` seat token.
* Burn path: `-1` seat token.

So the minting policy ensures the **supply & uniqueness** of seat NFTs.

---

### 11.10 Validator

A **validator** is the Plutus script that decides whether a script UTxO can be spent.

Here, the ticket validator has typed form:

```haskell
mkTicketValidator :: TicketDatum -> TicketRedeemer -> ScriptContext -> Bool
```

and is compiled to a `Validator`:

```haskell
validator :: Validator
validator =
  mkValidatorScript $$(PlutusTx.compile [|| mkTicketValidatorUntyped ||])
```

Roles:

* Enforces **resale rules** (`Transfer`).
* Enforces **entry rules** (`UseAtGate`).
* Ensures ticket NFT is bound, preserved, or burned correctly.
* Enforces time windows, signatures, and static field integrity.

If it returns `False` / `error`, the transaction is invalid.

---

### 11.11 Script address

A **script address** is the Cardano address derived from the hash of a validator.

Your executable:

* Computes `plutusValidatorHash validator`.
* Derives a Bech32 address via cardano-api (`toBech32ScriptAddress`).
* Prints it out so wallets and tools know where to send ticket UTxOs.

Flow:

1. You deploy the validator (on-chain hash).
2. You compute its script address.
3. Primary sale + resales lock ticket UTxOs at that address.

Any spend from that address must pass the ticket validator.

---

### 11.12 Policy ID

A **Policy ID** is the on-chain identifier (a `CurrencySymbol`) for a minting policy.

* For tickets: `tdPolicyId` and the `CurrencySymbol` derived from `ticketPolicy params`.
* For USED souvenirs: `tdUsedPolicyId`.

Characteristics:

* All tokens minted under the same policy share the same Policy ID.
* A ticket NFT is fully identified by `(policyId, tokenName)`.
* Clients use the Policy ID to query balances and verify authenticity (e.g. “is this NFT from the official event policy?”).

---

### 11.13 Text envelope (`.plutus` file)

A **text envelope** is the standard JSON-like format used by `cardano-api` / `cardano-cli` to store scripts and keys.

Your tools:

* `sports-tickets-exe` writes `sports-tickets.plutus`.
* `sports-tickets-policy-exe` writes `sports-tickets-policy.plutus`.

Each `.plutus` file includes:

* `type` – e.g. `"PlutusScriptV2"`.
* `description` – human-readable label.
* `cborHex` – hex-encoded Plutus CBOR bytes.

Usage:

* `cardano-cli transaction build` with `--tx-in-script-file` / `--minting-script-file`.
* Wallets or dev tools can load and inspect the script metadata.

---

### 11.14 How these concepts connect (ticket lifecycle diagram)

Below is an ASCII overview of how everything fits together for a single ticket:

```text
(1) Minting: organiser creates seat NFT
---------------------------------------

Organiser wallet
   |
   |  tx with minting policy:
   |    - Policy: SportsTicketsPolicy (TicketMintParams)
   |    - Redeemer: MintTicket seatId
   |    - Signed by tmpOrganizer
   v
+-----------------------------------------------+
|  Mint 1 NFT: (ticketPolicyId, tokenName)      |
|  -> UTxO to organiser address                 |
+-----------------------------------------------+

Now: 1 NFT ticket exists for that seat.


(2) Primary sale: organiser -> first fan
----------------------------------------

Organiser sells the ticket:

  - Off-chain: they transfer NFT + some metadata
  - On-chain: send NFT to buyer (fan) address

Result:
  Buyer wallet now holds the ticket NFT.


(3) Locking to validator (optional pattern)
-------------------------------------------

For a fully on-chain flow, buyer can lock the NFT at
the SportsTickets validator address with TicketDatum:

  TicketDatum
    - tdEventId, tdSeat
    - tdOwner        = buyer PKH
    - tdUsed         = False
    - tdFaceValue    = faceValueAda
    - tdMaxPrice     = resaleCapAda
    - tdEventTime    = eventTime
    - tdKycAuthority = maybe KYC PKH
    - tdPolicyId     = ticketPolicyId
    - tdTokenName    = tokenName
    - tdUsedPolicyId = usedPolicyId


(4) Resale / Transfer (secondary market)
----------------------------------------

Buyer (current owner) wants to resell:

  Tx spends script UTxO at ticket validator with:

    Redeemer: Transfer newOwner price

  Validator checks:
    - ticket NFT bound & preserved
    - owner signed (and KYC if required)
    - price <= tdMaxPrice
    - owner paid exactly price
    - static fields unchanged
    - continuing script output:
        * 1 ticket NFT
        * same TicketDatum except tdOwner = newOwner

Result:
  New owner now controls the ticket UTxO at the validator.


(5) Gate Use (UseAtGate)
------------------------

New owner goes to the event gate:

  Tx spends script UTxO with:

    Redeemer: UseAtGate

  Validator checks:
    - ticket NFT in input
    - tdUsed == False
    - valid time range (<= tdEventTime)
    - Mint/burn pattern:
        * -1 (tdPolicyId, tdTokenName)
        * +1 (tdUsedPolicyId, "USED-" <> tokenName)
    - USED NFT paid to tdOwner
    - no continuing script output

Result:
  - Original ticket NFT is burned (no more entry rights).
  - Owner receives USED souvenir NFT in their wallet.


(6) Post-event analysis
-----------------------

Off-chain dashboards / tools can:

  - Count original ticket mints   -> capacity / total tickets.
  - Count USED souvenirs minted   -> actual attendance.
  - Inspect resale patterns       -> anti-scalping analytics.

The on-chain model ensures that:
  * each seat has exactly one ticket NFT,
  * all transfers respect price caps & rules,
  * each entry scan consumes the ticket and issues a verifiable USED souvenir.
```

This lifecycle ties together:

* **Minting policy** (who can create/burn seat NFTs),
* **Validator** (how tickets move between owners and are consumed),
* **Datums & redeemers** (state + actions),
* **Policy IDs / addresses / `.plutus` files** (deployment & CLI integration),

into one coherent **sports & entertainment ticketing system** on Cardano.