# HostMT5 Copier: free MT5 trade copier EA (source included)

A free MetaTrader 5 Expert Advisor that copies trades from one **master** account to any number of **slave** accounts running in MT5 terminals **on the same computer**. The terminals can be at different brokers.

- Lot multiplier or fixed lot, with an optional maximum lot
- Reverse mode (buy ↔ sell, SL ↔ TP)
- Copies SL/TP and later changes to them
- Symbol prefix/suffix for brokers that name symbols differently (`EURUSD` → `EURUSD.pro`)
- Optionally copies trades already open when the slave starts
- Checks four times a second

**Download:** the compiled `HostMT5Copier.ex5` is on the [Releases](../../releases) page and at [hostmt5.com/free/HostMT5Copier.ex5](https://hostmt5.com/free/HostMT5Copier.ex5). Or compile `HostMT5Copier.mq5` yourself in MetaEditor.

## Setup

1. Put `HostMT5Copier.ex5` in each terminal's `MQL5\Experts` folder (File > Open Data Folder) and refresh the Navigator.
2. On the account you trade, attach it to any chart with **Role = MASTER**.
3. On each follower account, attach it to any chart with **Role = SLAVE** and the same **Channel name**.
4. Turn on **Algo Trading** in every terminal.

Master and slaves exchange data through MT5's shared `Common\Files` folder, so all terminals must run on the same computer under the same Windows user. Use different channel names to run several independent master/slave groups.

## Inputs

| Input | Used by | Meaning |
|---|---|---|
| Role | both | MASTER or SLAVE |
| Channel name | both | Must match between a master and its slaves |
| Lot rule / value | slave | Multiplier of the master's lot, or a fixed lot |
| Maximum lot | slave | Cap per copied trade (0 = none) |
| Reverse | slave | Opposite direction; SL and TP swap |
| Copy SL/TP | slave | Copy stops and their changes |
| Copy existing | slave | Also copy positions already open on the master at start |
| Symbol prefix / suffix | slave | How this broker names symbols |
| Max slippage | slave | In points |
| Magic number | both | Marks copied trades (the master ignores them, so chains never loop) |

## Good to know

- It copies **positions**. A pending order on the master is copied once it fills.
- **Partial closes are not mirrored**: the copy closes when the master position is fully closed.
- Copies open at the slave's market price, so entry prices can differ slightly from the master's.
- Copies are matched to the master by their order comment. A broker that rewrites order comments will break the matching.
- A slave pauses if the master hasn't written for 10 seconds, for example because its terminal is closed.
- Test on demo accounts first.

## Need it 24/7, without your PC on?

This EA only works while your computer and all terminals are running. [HostMT5](https://hostmt5.com) hosts real MT5 terminals in the cloud and copies between accounts at any brokers on the server, with no EA to install. It adds balance, equity or %-risk lot scaling, symbol mapping, filters and drawdown limits, plus TradingView webhooks and EA hosting. **Free during launch** (up to 3 MT5 accounts, no card).

Guide: [Copy trades between MT5 accounts at different brokers](https://hostmt5.com/learn/mt5-copy-trading-between-brokers)

## Licence

MIT. MetaTrader is a trademark of MetaQuotes, which does not endorse HostMT5. Trading involves risk; this software comes with no warranty.
