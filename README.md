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
