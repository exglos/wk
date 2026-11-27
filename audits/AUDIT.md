# Witness Key technical and security audit

Scope: `src/WitnessKey.sol`\
Commit hash: `99006348c1b2d1938c5de1bdd17957fd2489fa03`\
Auditors: Naftali Murgor; jo.exglos.eth\
Audit date: 2026-11-27


## Executive summary

The audit reviewed Witness Key (WK), a cbBTC-backed protocol accounting token,
in `src/WitnessKey.sol` at commit `99006348c1b2d1938c5de1bdd17957fd2489fa03`.
The review found **no critical, high, medium or low** severity issues,
and **6 informational** findings.

Notable risks are dependency on cbBTC contract, operational immutability of registrar/oracle roles and deliberate non-ERC20 allowance incompatibility.


## System overview

Witness Key (WK) is a cbBTC-backed, zero-decimal protocol with ERC20-like interface and a fixed 1 satoshi to 1 WK unit model.
The contract implements acquire, dispose, transfer, claim, recirculate, vault inscription, and ordinal movement reporting.
It has no owner, no upgrade path, and immutable registrar/oracle roles.

### Core state

- `CBBTC`: immutable reserve token address set in the constructor.
- `totalSupply`: total WK units minted.
- `balanceOf`: WK balances.
- `recirculationPerToken`: global recirculation accumulator, scaled by `MAGNITUDE = 2 ** 64`.
- `claimedOf`: signed per-account recirculation baseline.
- `vaultRegistrar`: immutable deployer-only role for `inscribe`.
- `ordinalOracle`: immutable deployer-only role for `reportOrdinalMoved`.

### Economic flow

- `acquire(cbbtcAmount, minTokens)`: transfers cbBTC in, charges 7% after first supply exists, mints WK.
- `dispose(tokens, minCbbtc)`: burns WK, charges 7%, sends net cbBTC to disposer.
- `claim()`: sends claimable recirculation.
- `recirculate()`: converts claimable recirculation into new WK at 1:1 with no fee.
- `transfer(to, tokens)`: moves WK and the corresponding dividend baseline with no fee.
- `inscribe(vault, assetId, cbbtcAmount, ordinalNumber, inscriptionId)`: registrar-funded vault mint.
- `reportOrdinalMoved(ordinalNumber, btcTxid)`: oracle provenance report; marks associated vault swept if one exists.


## Design notes and assumptions

Design notes cover intentional behaviors and operational tradeoffs.
They are not vulnerabilities.

### CbBTC

The contract's CBBTC address must point to the expected cbBTC token.
Any pause, blacklist, fee‑on‑transfer, or rebasing change to cbBTC will directly impact WK operations.
Continuous monitoring of cbBTC health is required.

### Registrar and oracle trust assumptions

The registrar and oracle roles are treated as trusted.
- `vaultRegistrar`: must register vaults and ordinals accurately.
- `ordinalOracle`: must report ordinal movement accurately.

Both roles are immutable by design.
This removes governance and admin-key risk,
but turns deployment mistakes and key compromise into permanent conditions.
Loss or compromise of either key permanently disables new inscriptions or ordinal reports, or enables malicious provenance data.

### ERC20 compatibility decision

WK intentionally remains ERC20-like but not ERC20-compliant.
The contract exposes metadata, balances, total supply, `transfer`, and `Transfer` events.
It deliberately omits `approve`, `allowance`, and `transferFrom`.
As a result, integrations that rely on allowance-based token movement will not work with WK.
Documentation and integration materials should describe WK as a protocol accounting token
and clearly disclose this interface limitation.


## Methodology

We read the contract line by line, focusing on access control, state transitions and economic logic.\
We analyzed the core arithmetic and identified potential issues.\
We checked and ran the existing test suite.\
We wrote our own tests to cover common cases and critical potential issues.\
We ran Slither as a cross-check.


## Test coverage and validation

The Foundry test suite was run with:
```sh
forge test -vvv
```
73 tests passed across four suites, with no failure.
Tests cover the core economic flows, the provenance and access-control logic.

Implemented unit tests for:
- First-minter bootstrap behaviour.
- Subsequent distribution application.
- Dispose fee collection and minimum-size enforcement.
- Zero-value transfer rejection.
- Claim and recirculate flows.
- Duplicate ordinal registration rejection.
- Already-moved ordinal registration rejection.
- Access control on registrar and oracle.

Slither 0.11.6 was run with:
```sh
slither src/WitnessKey.sol --exclude-dependencies
```
The run reported no WitnessKey-specific high/medium severity findings.

It reported 3 informational findings:
- `pragma`: accepted - contract compiler version satisfies all dependencies.
- `solc-version`: accepted - known compiler issues do not apply to this contract.
- `naming-convention`: accepted - uppercase CBBTC is a reasonable custom style.


## Positive observations

The contract has several sound design and implementation choices:
- Contract is readable, understandable, and aligned with best practices.
- Repeated logic is grouped into internal helpers without overcomplicating.
- State is updated before external cbBTC transfers in `dispose` and `claim`.
- `acquire`, `dispose`, `claim`, `recirculate`, and `inscribe` use `nonReentrant`.
- `SafeERC20` is used for reserve transfers.
- Minimum `acquire` and `inscribe` amounts.
- `acquire` and `inscribe` use the cbBTC balance change, not the requested amount.
- Ordinal uniqueness and already-moved checks are enforced at inscription time.
- `require` checks include clear messages.


## Findings

### F-01: Immutable registrar/oracle roles create permanent operational risk

Severity: Informational\
Status: Accepted\
Location: `inscribe`, `reportOrdinalMoved`

Both privileged roles are set to `msg.sender` in the constructor and cannot be changed:
```solidity
vaultRegistrar = msg.sender;
ordinalOracle = msg.sender;
```
The roles do not directly withdraw user funds, but they are central to provenance integrity.
A compromised oracle can falsely mark registered ordinals as moved.
A compromised or mistaken registrar can register incorrect vaults.
A lost key permanently disables new inscriptions and ordinal reporting.

Possible Impact:
- Permanent provenance corruption or operational dead-end.
- No recovery path if deployer key is lost or compromised.

Recommendation:
- Document the irreversible operational tradeoff.
- Follow best practices for securing and managing deployer keys.

### F-02: First acquirer/inscriber receives the full distribution (bootstrap)

Severity: Informational\
Status: Accepted\
Location: `acquire`, `inscribe`

When `totalSupply == 0`, the first acquirer/inscriber receives the full initial distribution.
This is expected behavior for the protocol’s bootstrap phase.

Impact:
- First user receives 100% of deposited cbBTC as tokens.
- Slightly contradicts the high-level “7% flows to all witness keys” statement for the bootstrap case.

Recommendation:
- Document the bootstrap exception.
- Plan and document the first post-deployment transaction.

### F-03: Per-transaction max acquire is not a position or rate limit

Severity: Informational\
Status: Accepted\
Location: `acquire`

`MAX_ACQUIRE` limits one call to 1,000,000 sats, but any user can call `acquire` repeatedly.

So this works fine:
```
Alice → acquire(1,000,000) → success
Alice → acquire(1,000,000) → success
Alice → acquire(1,000,000) → success
```

Impact:
- The limit is a per-call bound, not an anti-whale, position or rate limit.

Recommendation:
- Document it as a per-call bound.

### F-04: Unsigned-to-signed cast relies on a proven bound

Severity: Informational\
Status: Accepted\
Location: `_signedAdd`, `_signedSub`

The explicit conversion from `uint256` to `int256` does not revert on overflow.
```
function _signedAdd(int256 a, uint256 b) internal pure returns (int256) { return a + int256(b); }
function _signedSub(int256 a, uint256 b) internal pure returns (int256) { return a - int256(b); }
```
Every call to both helpers passes `b` value divided by `MAGNITUDE`.
The quotient is at most (2^256 - 1) / 2^64 < 2^192, which is below 2^255.
The cast therefore cannot change the sign, and the conversion is safe.

Impact:
- None in the current implementation.

Recommendation:
- Document the bound.

### F-05: Claim and recirculate may leave one unit of rounding dust

Severity: Informational\
Status: Open\
Location: `recirculationOf`

Rounding in calculations can leave `recirculationOf` returning 1 unit after a claim or recirculate,
when the expected remaining balance should be 0.

Impact:
- 1 unit may confuse users or interfaces that expect the claimable balance to be zero.

Recommendation:
- Document the rounding behaviour.

### F-06: Vault registered event field is unclear

Severity: Informational\
Status: Open\
Location: `VaultRegistered`

The `oktEmbedded` field does not clearly describe the amount of WK minted.
There is no effect on funds or logic.

Impact:
- Integrators may misread the field.

Recommendation:
- Rename the field.


## Deployment checklist

### Role key management

Handle the deployer key with secure operational practices,
including a hardened signing environment, physically separated backups,
and a recovery/succession plan.
If either key is lost, new inscriptions and/or ordinal reports may become permanently unavailable.
If either key is compromised, provenance records can be corrupted, even though user funds cannot be directly withdrawn by the role.

### Deployment Steps

- Set the constructor argument to the cbBTC address for the target chain
(Base mainnet cbBTC: `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`).
- Deploy the contract.
- Execute the bootstrap `acquire`/`inscribe` with the intended party to receive the initial distribution.
- Verify the source on the target network explorer.


## Limitations

Testing and analysis reduce risk but cannot guarantee that every issue was found.


## Conclusion

The reviewed implementation is broadly coherent and suitable for deployment.

To reduce risk and maintain security and reliability over time, we recommend the following:
- **Monitor cbBTC** to confirm it behaves as expected and stays on-peg.
- **Document key moments** clearly and transparently.
- **Educate users** on the protocol's design.
- **Harden the audit** as the system grows.
- **Launch a bug bounty** to engage community and improve security.
