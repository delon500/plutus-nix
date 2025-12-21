# Public Fund Release Smart Contract (Anti-Corruption)

This repo contains Delon Wenyeve’s **Public Fund Release** Plutus smart contract project (n-of-m approvals before release; refund after deadline if approvals are insufficient).

Repo branch (source of truth):
- `feat/EBU-public-fund-release`

## Project layout

Key files (inside the `wspace` workspace):

- On-chain validator: `code/wspace/src/PublicFundReleaseContract.hs`
- Off-chain endpoints: `code/wspace/src/PublicFundReleaseEndpoints.hs`
- Emulator / end-to-end tests: `code/wspace/tests/PublicFundReleaseEmulatorSpec.hs`
- Test entry point: `code/wspace/tests/Spec.hs`

## Prerequisites

You need a working **plutus-nix** dev environment (GHC/Cabal + dependencies) that can build the `wspace` workspace.

> Tip: If you already build other contracts in `plutus-nix/code/wspace`, you’re good to go.

## How to run the tests

1) Clone the repo and checkout the correct branch:

```bash
git clone https://github.com/delon500/plutus-nix.git
cd plutus-nix
git checkout feat/EBU-public-fund-release
```

2) Move into the `wspace` workspace:

```bash
cd code/wspace
```

3) Run only the PublicFundRelease tests (on-chain tests + plutus-simple-model tests):

```bash
cabal test wspace-tests --test-show-details=direct   --test-option=-p --test-option="/PublicFundRelease/"
```

If everything is set up correctly, you should see the PublicFundRelease test group(s) pass.

## Troubleshooting

- **Cabal can’t find dependencies / compiler**: Ensure you entered your plutus-nix development shell/environment (the same one you use to build other `wspace` projects).
- **Tests not found**: Confirm you are inside `code/wspace` and that you checked out `feat/EBU-public-fund-release`.

## What this command runs

The `-p "/PublicFundRelease/"` filter tells Cabal to run only tests whose names match **PublicFundRelease**, which includes:
- validator rule tests (approve/release/refund constraints)
- emulator / end-to-end lifecycle tests (deposit → approve → approve → release, and failure/refund scenarios)
