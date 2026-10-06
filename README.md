# Edge Hunter

`edge_hunter.bat` - double-click on Windows. Self-contained (downloads its own portable Python, reuses `data_cache`
from `strategy_lab.bat` / `run_backtest.bat` if they sit in the same folder).

It searches for an options strategy with a **neural network** and a **rule search**, on every CPU core, and keeps going
until a strategy is **confirmed on a sealed test period** (the newest 12 months, never seen by the search), or you stop it.

* Progress dashboard (dark/light, graph per attempt): `hunt_results/report.html` (opens automatically).
* Stop: Ctrl+C in the window, or create `STOP.txt` next to the .bat. Progress is saved; run again to resume.
* Settings are at the top of the .bat. Every trade is an in-the-money option priced with Black-Scholes at entry and exit,
  so **time decay**, half-spread and fees are charged on every trade.
* Check the machinery on synthetic data first: `edge_hunter.bat --selftest edge` (an edge is planted - it should find it)
  and `edge_hunter.bat --selftest null` (pure noise - it must never confirm anything).

If the data holds no real edge it will run forever. That is by design: only a sealed-test pass ends the hunt.

---

# Halt Hunter

`halt_hunter.bat` - same machinery (neural net + rule search on every core, sealed-test confirmation, dashboard), but for
**Nasdaq LULD volatility halts**: it buys shares the moment a halt ends (or, as a separate hunt, sells short).

* Halts come from Databento's trading-status feed for all Nasdaq symbols; 1-minute bars are downloaded only for halted
  stocks and cached in `data_cache`. Needs your key in `databento_key.txt` the first time; stops if the estimated cost
  goes over `MAX_COST`.
* Shares, not options: every fill pays slippage (at least `SLIP_BPS`, or a share of that minute's own range) plus per-share fees.
* `SIDE=long` or `short` at the top of the .bat (or `halt_hunter.bat --side short`). Each side has its own results folder
  (`halt_results_long`, `halt_results_short`) and its own sealed-test error budget.
* Stop: Ctrl+C, or create `STOP_HALTS.txt`. Self-test: `halt_hunter.bat --selftest edge` / `--selftest null`.
