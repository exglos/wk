# Witness Key technical and security audit

Scope: `src/WitnessKey.sol`\
Commit hash: `99006348c1b2d1938c5de1bdd17957fd2489fa03`\
Auditors: Naftali Murgor; jo.exglos.eth\
Audit date: 2026-11-25


## Executive summary

The audit reviewed Witness Key (WK), a cbBTC-backed protocol accounting token,
in `src/WitnessKey.sol` at commit `99006348c1b2d1938c5de1bdd17957fd2489fa03`.
**No critical, high-severity or medium issues were found.**
The audit identified **one low-severity finding**,
acknowledged with no change required.
and **four informational findings**,
accepted by design and retained to document the tradeoff.

Notable risks are dependency on cbBTC contract, operational immutability of registrar/oracle roles and deliberate non-ERC20 allowance incompatibility.


## System overview

Witness Key (WK) is a cbBTC-backed, zero-decimal protocol with ERC20-like interface and a fixed 1 satoshi to 1 WK unit model.
The contract implements acquire, dispose, transfer, claim, recirculate, vault inscription, and ordinal movement reporting.
It has no owner, no upgrade path, and immutable registrar/oracle roles.

### Core state

- `CBBTC`: immutable reserve token address set in the constructor.
- `totalSupply`: total WK units minted.
- `balanceOf`: WK balances.
- `recirculationPerToken`: global dividend accumulator using `MAGNITUDE = 2 ** 64`.
- `claimedOf`: signed per-account dividend baseline.
- `vaultRegistrar`: immutable deployer-only role for `inscribe`.
- `ordinalOracle`: immutable deployer-only role for `reportOrdinalMoved`.

### Economic flow

- `acquire(cbbtcAmount, minTokens)`: transfers cbBTC in, charges 7% after first supply exists, mints WK.
- `dispose(tokens, minCbbtc)`: burns WK, charges 7%, sends net cbBTC to disposer.
- `claim()`: sends claimable recirculation (dividends).
- `recirculate()`: converts claimable recirculation into new WK at 1:1 with no fee.
- `transfer(to, tokens)`: moves WK and the corresponding dividend baseline with no fee.
- `inscribe(vault, assetId, cbbtcAmount, ordinalNumber, inscriptionId)`: registrar-funded vault mint.
- `reportOrdinalMoved(ordinalNumber, btcTxid)`: oracle provenance report; marks associated vault swept if one exists.


## Design notes and assumptions

### cbBTC

CbBTC contract address must be the expected reserve token.
The review assumes cbBTC behaves as expected, without transfer fees, pausing, or blacklist restrictions that affect the contract.
The protocol’s safety depends on cbBTC behaving as expected.

### Registrar and oracle trust assumptions

The registrar and oracle roles are treated as trusted.
- `vaultRegistrar` must register vaults and ordinals accurately.
- `ordinalOracle` must report ordinal movement accurately.
The contract is intentionally immutable. This reduces governance/admin risk but turns deployment mistakes and key compromise into permanent conditions.

### ERC20 compatibility decision

WK intentionally remains ERC20-like but not ERC20-compliant.
The contract exposes metadata, balances, total supply, `transfer`, and `Transfer` events,
but it does not implement `approve`, `allowance`, or `transferFrom`.
As a result, integrations that rely on allowance-based token movement will not work with WK.
Documentation and integration materials should identify WK as a protocol accounting token and clearly disclose this interface limitation.


## Methodology

We read the contract line by line, focusing on access control, state transitions and economic logic.
We analyzed the core arithmetic and identified possible issues.
We checked and ran the existing test suite.
We wrote our own tests to cover common cases and critical potential issues.
We ran Slither as a cross-check.


## Test coverage and validation

The Foundry test suite was run with:
```sh
forge test -vvv
```
Included coverage:
- Core economic tests (acquire, dispose, claim, recirculate, transfer)
- Audit/provenance tests (ordinal uniqueness, already-moved rejection, access control)
- Minimum-amount and zero-transfer guards

Implemented unit tests for:
- First-minter bootstrap behaviour.
- Subsequent distribution application.
- Dispose fee collection and minimum-size enforcement.
- Zero-value transfer rejection.
- Duplicate ordinal registration rejection.
- Already-moved ordinal registration rejection.
- Access control on registrar and oracle.
- Claim and recirculate flows.

Static analysis status:
- Slither 0.11.6 run against `src/WitnessKey.sol`.
- Slither reported no WitnessKey-specific high/medium fund-flow issue after remediation.
- Informational output: OpenZeppelin dependency assembly, mixed pragma, Solidity-version warnings, and `CBBTC` naming-convention style.
- Slither was the static-analysis tool completed.


## Positive observations

- State is updated before external cbBTC transfers in `dispose` and `claim`.
- `acquire`, `dispose`, `claim`, `recirculate`, and `inscribe` use `nonReentrant`.
- `SafeERC20` is used for reserve transfers.
- Dividend accounting uses signed baselines and handles negative values.
- `dispose` prevents burning the entire global supply.
- `minTokens` / `minCbbtc` give users basic slippage protection.
- Ordinal uniqueness and already-moved checks are enforced at inscription time.


## Findings

### F-01: Immutable registrar/oracle roles create permanent operational risk

Severity: Informational\
Status: Accepted\
Location: constructor, `onlyRegistrar`, `onlyOracle`

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
- Document the irreversible operational tradeoff and deployment key ceremony.

### F-02: First acquirer/inscriber receives the full distribution (bootstrap)

Severity: Informational
Status: Documented (by design)
Location: `acquire`, `inscribe`

When `totalSupply == 0` the measured distribution is added to the first minter’s tokens instead of being distributed.

Impact:
- First user receives 100% of deposited cbBTC as tokens.
- Slightly contradicts the high-level “7% flows to all witness keys” statement for the bootstrap case.

Recommendation:
- Document, plan

### F-03: Per-transaction max acquire is not a position or rate limit

Severity: Informational
Status: Open by design
Location: `acquire`, `MAX_ACQUIRE`

`MAX_ACQUIRE` limits one call to 1,000,000 sats, but any user can call `acquire` repeatedly.

So this works fine:

```ext
Alice → acquire(1,000,000) → success
Alice → acquire(1,000,000) → success
Alice → acquire(1,000,000) → success
```

Impact:
- This is a UX/slippage bound, not an anti-whale or rate-limit control.

Recommendation:
- Document it as a per-call bound.

### F-04: Cast overflow not checked

Severity: Informational
Status:
Location:

int256(b) overflow is not checked
```
function _signedAdd(int256 a, uint256 b) internal pure returns (int256) { return a + int256(b); }
function _signedSub(int256 a, uint256 b) internal pure returns (int256) { return a - int256(b); }
```
The quotient is at most (2^256 - 1) / 2^64 < 2^192, which is far below 2^255.
The cast therefore cannot change the sign, and the conversion is safe.

Recommendation:
- Test, document.

### F-05: Rounding mismatch in claim() and recirculate() leaves residual claimable dust

recirculationOf returns 1 unit after claim or recirculation that should leave 0.

Impact:
- Holders can see a non-zero claimable balance immediately after recirculating. The amount is at most 1 unit per operation, so there is no fund loss, but it affects user-facing balances and can cause confusion in interfaces.


## Deployment checklist

### Network and constructor

- Base mainnet cbBTC: `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` (verify before use).
- Constructor argument: the `cbBTC` address for the target network.
- Deployer permanently becomes both `vaultRegistrar` and `ordinalOracle`.

### Role key management

- Use the exact multisig or hardened operational key intended to hold both roles.
- If either key is lost, new inscriptions and/or ordinal reports may become permanently unavailable.
- If either key is compromised, provenance records can be corrupted even though user funds cannot be directly withdrawn by the role.

### Deployment Steps

- Run `forge test -vvv`.
- Run `forge coverage` (optional).
- Run static analysis with Slither.
- Verify source on the target network explorer.
- Publish integration notes stating WK is non-ERC20-compliant.
- Index `VaultRegistered`, `VaultSwept`, and `OrdinalMoved` events off-chain.


## Limitations

Testing and analysis reduce risk but cannot guarantee that every issue was found.


## Conclusion

The reviewed implementation is broadly coherent.
To mitigate potential risks and ensure continued security and reliability, we recommend the following:
- CbBTC monitoring: Monitor cbBTC is hold its value and acts as expected.
- Gradual Hardening: As usage of the system increases, consider implementing additional security measures.
- Continuous Monitoring: Regularly monitor the system for any signs of potential vulnerabilities or operational issues.
- Documentation: Ensure comprehensive documentation exists to clearly explain the implications of immutable roles and the operational procedures in place to manage them.
- User Education: Provide clear guidance and education to users regarding the implications of immutable roles and the lack of recovery mechanisms.
- Risk Assessment: Periodically reassess the risks associated with immutable roles and adjust the security posture accordingly.
