# Izzianity-
Love

## App usage rewards

`/smart_contracts/AppUsageRewards.sol` implements rewards for contributors based on
reported app usage. It does not fund app development costs directly. The contract
distributes an ERC-20 reward pool among each app's registered contributors according
to fixed basis-point shares.

The owner registers apps and their contributor wallet addresses, authorizes usage
reporters, and can fund the pool. Contributors can link a payout wallet by calling
`setPayoutWallet` from their registered contributor address; until then, rewards go
to that address. Each authorized reporter submits a unique batch ID and reward
amount, which are permanently recorded and paid from funded balances. There is no
administrator withdrawal function.

Usage itself is reported by an authorized account; the contract does not independently
verify app downloads, subscriptions, or other off-chain usage metrics. Reporter
authorization and app registration are therefore trust decisions, and emitted events
provide an on-chain audit trail.

The contract is not deployed by this repository. Choose and audit the target chain,
the ERC-20 token contract, usage-measurement rules, and reporter governance before
deployment. Token amounts use that token's smallest unit. The Foundry configuration
uses Solidity 0.8.24.

The payment-flow tests are in `smart_contracts/test/AppUsageRewards.t.sol` and can
be run with `forge test`.
