# Reverse Split Token

A custom ERC-20 token implementing an automated **Reverse Split Protocol (RSP)** — a deterministic supply reduction mechanism.

### Overview

This contract introduces a unique deflationary system that automatically reduces the total token supply over time through a series of reverse splits. The mechanism is designed to run for a fixed period, after which the supply becomes permanently capped and all trading restrictions are lifted.

### Core Mechanism – Reverse Split Protocol (RSP)

- **Total number of rebases**: 84
- **Reduction per rebase**: 20% of the current total supply
- **Rebase frequency**: Every 4 hours
- **Full cycle duration**: 14 days
- **Final supply**: Exactly 777,777,777 tokens

**How the rebase works:**
1. Every 4 hours the contract reduces the total supply by 20%.
2. The reduction is achieved by adjusting an internal `partsPerToken` multiplier (similar to elastic supply tokens).
3. After each rebase, the liquidity pair is automatically synced to maintain accurate pricing.
4. Rebases can occur automatically during sells or can be triggered manually (`manualRebase()`).
5. Once the 14-day cycle ends (or the 84th rebase is reached):
   - Supply is permanently set to **777,777,777** tokens
   - Buy and sell taxes are set to **0%**
   - All transaction and wallet limits are permanently removed

### Tokenomics & Trading Parameters

- **Initial supply**: 18,236,939,125,700,000 tokens
- **Decimals**: 9
- **Buy tax** (during cycle): 20%
- **Sell tax** (during cycle): 80%
- **Max transaction** (during limits): 2% of current supply
- **Max wallet** (during limits): 2% of current supply

After the final rebase all taxes and limits are disabled automatically.

### Contract Features

- **Automatic tax collection & swap** — Taxes are accumulated in the contract and automatically converted to ETH on sells when threshold is reached.
- **Anti-bot protection** — Owner can blacklist addresses.
- **Whitelisting system** — Contract, router, and selected addresses can be exempted from taxes and limits.
- **Trading control** — Owner must call `enableTrading()` to activate public trading.
- **Limit removal** — Limits can be removed manually (`removeLimits()`) or automatically at the end of the RSP cycle.
- **Rebase control** — Owner can start the rebase cycle with `startRebaseCycles()`.

### Technical Implementation

- Uses the **parts-based system** (similar to Olympus-style rebasing) to allow smooth supply reduction without breaking ERC-20 compatibility.
- All rebases are deterministic and fully transparent on-chain.
- Tax swap uses `swapExactTokensForETHSupportingFeeOnTransferTokens` for maximum compatibility.
- Contract is Ownable with standard renounce/transfer ownership functions.

### Functions Overview

| Function                    | Description                                      | Access     |
|----------------------------|--------------------------------------------------|------------|
| `startRebaseCycles()`      | Starts the 14-day RSP cycle                      | Owner only |
| `manualRebase()`           | Triggers rebase if conditions are met            | Public     |
| `enableTrading()`          | Activates public trading                         | Owner only |
| `removeLimits()`           | Permanently removes tx/wallet limits             | Owner only |
| `rebase()`                 | Internal function performing 20% supply reduction| Internal   |
| `swapBack()`               | Swaps accumulated taxes to ETH                   | Public     |

### Security Considerations

- Blacklist system protects against known malicious actors
- All sensitive functions are protected by `onlyOwner` modifier
- Reentrancy protection on tax swap via `swapping` modifier
- Limits and taxes are designed to be removed after the RSP cycle

### License

This project is licensed under the **MIT License**.

---

**Note:** This is an experimental token mechanic. The Reverse Split Protocol creates a strong deflationary pressure during the first 14 days. Users should fully understand the mechanics before interacting with the contract.

Always verify the deployed contract address on Etherscan before any transaction.
