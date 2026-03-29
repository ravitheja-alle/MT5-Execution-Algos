# MT5-Execution-Algos

# Institutional Risk-Adjusted Momentum EA (MT5 / MQL5)

##The Problem:
Retail algorithmic trading fails due to static lot sizing and ignorance of market regimes. EAs that use fixed volumes or point-based math inevitably suffer catastrophic drawdowns due to CFD spread widening, slippage during US macro news, and weekend price gaps.

##The Execution Architecture:
This Expert Advisor is built in MQL5 to execute a high-probability momentum strategy with strict, institutional-grade risk constraints. It completely removes the vulnerability of standard retail EAs by enforcing a hard, mathematical risk ceiling.

##Key architectural features include:

**Dynamic Contract-Size Risk Sizing:** Calculates position sizes dynamically using raw SYMBOL_TRADE_CONTRACT_SIZE math, strictly capping maximum exposure to 1.0% per trade, regardless of the entry price or stop-loss distance.

**Spread/Slippage Penalty Matrix:** Artificially widens the calculated risk distance by 2x the live spread, ensuring the requested lot size absorbs sudden liquidity vacuums.

**Session & Regime Filters:** Hardcoded blocks against Wednesday triple-swap chop, Friday weekend holding gaps, and the 15:00-16:00 US macro news window.

**Volume-Weighted Confluence:** Replaces lagging indicators (like ADX) with a custom Relative Volume (RVOL) array combined with a session-anchored VWAP to execute strictly on institutional footprint.

**Ratchet Trailing Logic:** Secures capital via a unidirectional, ATR-based trailing stop that only moves to lock in profit, never widening the structural risk.

###Use Case:
Attach to the M15 chart of high-momentum assets (XAUUSD, US30, USTEC). The algorithm is designed for capital preservation first, yielding highly selective, asymmetrical breakout entries.

**Custom Algorithmic Development:**
I build robust MQL5 execution architecture, risk-management protocols, and automated quantitative systems. If you need a developer who prioritizes mathematical survival and precise execution over curve-fitted retail logic, send me a Direct Message with your project parameters.

###Report: 

<img width="3130" height="656" alt="image" src="https://github.com/user-attachments/assets/195e29f1-49d6-4d8c-b34a-07801f16f21b" />

<img width="2082" height="642" alt="image" src="https://github.com/user-attachments/assets/fae605c8-0c51-4822-8efd-3f746151758c" />

