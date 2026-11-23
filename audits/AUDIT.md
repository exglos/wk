# Witness Key Technical and Security Audit

Scope: `src/WitnessKey.sol`\
Commit hash: `99006348c1b2d1938c5de1bdd17957fd2489fa03`\
Auditors: Naftali Murgor; jo.exglos.eth\
Audit date: 2026-11-23


## Executive Summary

The audit reviewed Witness Key (WK), a cbBTC-backed protocol accounting token,
in `src/WitnessKey.sol` at commit `99006348c1b2d1938c5de1bdd17957fd2489fa03`.
**No critical or high-severity issues were found.**
The audit identified **one medium-severity finding (M-01)**,
accepted by design and retained to document the tradeoff,
and **one low-severity finding (L-01)**, acknowledged with no change required.
Five design notes document intentional behaviors and operational tradeoffs.

The protocol’s safety depends on cbBTC behaving as expected.
Key design tradeoffs include immutable registrar and oracle roles
and deliberate incompatibility with standard ERC20 allowance behavior.
WK should be presented as a protocol accounting token, not as a standard ERC20.


## Review Methodology and Limitations

We read the contract line by line, focusing on access control, state transitions and economic logic.
We analyzed the core arithmetic and identified possible issues.
We checked and ran the existing test suite.
We wrote our own tests to cover common cases and critical potential issues.
We ran Slither 0.11.6 as a cross-check.

The review assumes cbBTC behaves as expected, without transfer fees, pausing, or blacklist restrictions that affect the contract.
The registrar and oracle roles are treated as trusted.
Testing and analysis reduce risk but cannot guarantee that every issue was found.
