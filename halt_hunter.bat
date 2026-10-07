@echo off & goto :batch
r"""
:batch
setlocal EnableExtensions
cd /d "%~dp0"
title Halt Hunter - buy/short at the unhalt, neural network + rule search, runs until an edge is confirmed

REM ================== SETTINGS (edit these) ==================
REM Databento key: needed the first time, to download the list of halts and the 1-minute bars around each one.
REM Put your key alone on the first line of databento_key.txt next to this file (it is never stored in this file).
REM Everything downloaded is cached in data_cache, so later runs need no key.
if not defined DATABENTO_API_KEY if exist "%~dp0databento_key.txt" set /p DATABENTO_API_KEY=<"%~dp0databento_key.txt"

REM long  = BUY shares the moment an LULD halt ends.      short = SELL SHORT shares the moment it ends.
REM They are two separate hunts with separate results (halt_results_long / halt_results_short).
REM You can also start the other one with:   halt_hunter.bat --side short
set "SIDE=long"

set "FIRST_YEAR=2021"
set "END=2026-10-01"

REM The neural net is tested year by year from here on: each test year is traded by a net that was
REM trained ONLY on earlier years. Needs 2+ years of halts before it.
set "FIRST_TEST_YEAR=2023"

REM The newest N months are SEALED: the search never sees them. A strategy only counts as an edge
REM if it also makes money there. More months = easier to confirm a real edge (but less data to search).
set "LOCKBOX_MONTHS=12"

REM Chance you are willing to accept of EVER being fooled by luck, over the whole run (however long).
set "ALPHA=0.05"

REM CPU workers: 0 = one per logical core (uses all your CPU, at below-normal priority so Windows stays usable)
set "WORKERS=0"
REM Memory budget in GB (the hunter needs far less than this; it only caps the number of workers)
set "MEM_GB=14"
REM Stop by itself after this many hours (0 = never: keep hunting until an edge is confirmed or you stop it)
set "MAX_HOURS=0"
set "SEED=7"

REM Halts come from Databento's status feed (regular hours only), then 1-minute bars only for halted stocks.
REM The first run downloads this ONE TIME (it is saved in data_cache, so later runs cost nothing). Before it starts it
REM prints roughly what that will cost on your Databento account and waits 15 seconds - press Ctrl+C to cancel.
REM More years of history cost more (about the same per year): a later FIRST_YEAR / FIRST_TEST_YEAR is cheaper.
REM To only see the estimate:   halt_hunter.bat --estimate
REM MAX_COST: 0 = no limit. If you put a number here (US dollars) it refuses to start a download estimated above it.
set "MAX_COST=0"

REM Trades are SHARES (not options), sized to BUDGET dollars. Halted stocks reopen with wide, jumpy prices, so every
REM fill pays slippage: at least SLIP_BPS (hundredths of a percent of price), or SLIP_RNG x that minute's own
REM high-low range if that is bigger, plus FEE_SHARE dollars per share each way.
set "BUDGET=1000"
set "SLIP_BPS=40"
set "SLIP_RNG=0.15"
set "FEE_SHARE=0.004"
REM Ignore halted stocks priced outside this range
set "MIN_PRICE=0.5"
set "MAX_PRICE=200"
REM Costs are multiplied by this for the "still profitable if costs are higher?" test
set "STRESS=1.5"
REM ===========================================================

REM Fully self-contained: uses (or downloads) its own portable Python in .\py
REM If edge_hunter.bat / strategy_lab.bat is in the same folder, this reuses its Python and data.
set "PYVER=3.12.10"
set "PYDIR=%~dp0py"
set "PY=%PYDIR%\python.exe"

if exist "%PY%" goto :have_python
echo [setup 1/4] Downloading portable Python %PYVER% ...
call :dl "https://www.python.org/ftp/python/%PYVER%/python-%PYVER%-embed-amd64.zip" "%TEMP%\bt_py_embed.zip"
if errorlevel 1 goto :fail
if not exist "%PYDIR%" mkdir "%PYDIR%"
echo [setup 2/4] Extracting Python ...
tar -xf "%TEMP%\bt_py_embed.zip" -C "%PYDIR%" >nul 2>nul
if not exist "%PY%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%TEMP%\bt_py_embed.zip' -DestinationPath '%PYDIR%' -Force"
if not exist "%PY%" goto :fail
> "%PYDIR%\python312._pth" (
    echo python312.zip
    echo .
    echo Lib\site-packages
    echo import site
)
del "%TEMP%\bt_py_embed.zip" >nul 2>nul

:have_python
if exist "%PYDIR%\Lib\site-packages\pip" goto :have_pip
echo [setup 3/4] Installing pip ...
call :dl "https://bootstrap.pypa.io/get-pip.py" "%TEMP%\bt_get_pip.py"
if errorlevel 1 goto :fail
"%PY%" "%TEMP%\bt_get_pip.py" --no-warn-script-location --disable-pip-version-check -q
if errorlevel 1 goto :fail
del "%TEMP%\bt_get_pip.py" >nul 2>nul

:have_pip
if exist "%PYDIR%\.deps_ok" goto :run
echo [setup 4/4] Installing databento, pandas, numpy (first run only) ...
"%PY%" -m pip install --no-warn-script-location --disable-pip-version-check -q databento pandas numpy
if errorlevel 1 goto :fail
echo ok> "%PYDIR%\.deps_ok"
echo Setup complete.

:run
echo.
echo ############################################################
echo   HALT HUNTER  -  Nasdaq LULD halts  -  %SIDE%  -  %FIRST_YEAR% to %END%
echo   Neural net + rule search on every core. It keeps going until an edge
echo   is CONFIRMED on the sealed newest %LOCKBOX_MONTHS% months of halts.
echo   Watch progress in the browser page it opens (halt_results_%SIDE%\report.html).
echo   To stop: press Ctrl+C here, or create a file named STOP_HALTS.txt in this folder.
echo   Progress is saved - run this file again to carry on.
echo ############################################################
set "CRASHES=0"

:hunt
"%PY%" -x "%~f0" --side %SIDE% --first-year %FIRST_YEAR% --end %END% --first-test-year %FIRST_TEST_YEAR% --lockbox-months %LOCKBOX_MONTHS% --alpha %ALPHA% --workers %WORKERS% --mem-gb %MEM_GB% --max-hours %MAX_HOURS% --seed %SEED% --budget %BUDGET% --slip-bps %SLIP_BPS% --slip-rng %SLIP_RNG% --fee-share %FEE_SHARE% --min-price %MIN_PRICE% --max-price %MAX_PRICE% --stress %STRESS% --max-cost %MAX_COST% %*
set "RC=%errorlevel%"
if "%RC%"=="0" goto :found
if "%RC%"=="3" goto :stopped
if "%RC%"=="5" goto :crashed
if "%RC%"=="6" goto :info
goto :failed

:found
echo.
echo ============================================================
echo   EDGE CONFIRMED - see the halt_results_long or halt_results_short folder (report.html)
echo ============================================================
pause
exit /b 0

:stopped
echo.
echo Hunt stopped. Progress is saved - run this file again to carry on.
pause
exit /b 0

:info
echo.
echo Estimate only - nothing was downloaded or spent. Edit MAX_COST / FIRST_YEAR at the top of this file if needed,
echo then run it normally.
pause
exit /b 0

:crashed
set /a CRASHES+=1
if %CRASHES% GEQ 5 goto :failed
echo.
echo *** The hunt hit an unexpected error (see above). Restarting in 15 seconds - progress is saved. [%CRASHES% of 5]
timeout /t 15 /nobreak >nul
goto :hunt

:failed
echo.
echo *** The hunt stopped with an error - see the message above.
pause
exit /b 1

:dl
curl.exe -L --fail --retry 3 -s -S -o "%~2" "%~1" 2>nul
if not errorlevel 1 exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%~2'"
if exist "%~2" exit /b 0
exit /b 1

:fail
echo.
echo *** Setup failed. Check your internet connection (python.org and pypi.org
echo *** must be reachable), then delete the "py" folder and run this again.
pause
exit /b 1
"""
# ---------------- Halt Hunter (Python half, run by the batch section above) ----------------
"""
HALT HUNTER - searches for an edge in buying (or shorting) Nasdaq stocks the moment an LULD volatility halt ends,
with a neural network and a rule search on every CPU core, and keeps going until a strategy survives a sealed test.

  * Halts come from Databento's trading-status feed (all Nasdaq symbols); 1-minute bars are pulled only for halted stocks.
  * Trades are in SHARES (not options): bought (or sold short, as a separate hunt) at the first print after the unhalt.
    Every fill pays slippage (at least SLIP_BPS, or a share of that minute's own range) plus per-share fees.
  * The newest LOCKBOX_MONTHS are sealed: the search and the nets never see them. A candidate gets one look, after clearing
    tough gates (beat the scrambled-data luck benchmark, survive neighbours and 1.5x costs, power check), and every look
    spends part of an error budget, so the chance of EVER confirming a fake edge stays below ALPHA however long it runs.
"""
import os
import subprocess
import sys

for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS",
           "VECLIB_MAXIMUM_THREADS"):
    os.environ[_v] = "1"          # we parallelise with processes, not BLAS threads

ENGINE_TAG = "# ---------------- Halt Hunter (Python half"
if __name__ == "__main__" and str(__file__).lower().endswith(".bat"):
    # Running as the .bat itself: spawned worker processes cannot re-import a .bat, so write the
    # Python half to halt_engine.py next to it and run that instead.
    _path = os.path.abspath(__file__)
    with open(_path, "r", encoding="utf-8") as _f:
        _src = _f.read().replace("\r\n", "\n")
    _body = _src[_src.index(ENGINE_TAG):]
    _eng = os.path.join(os.path.dirname(_path), "halt_engine.py")
    _old = None
    if os.path.exists(_eng):
        with open(_eng, "r", encoding="utf-8") as _f:
            _old = _f.read()
    if _old != _body:
        with open(_eng, "w", encoding="utf-8", newline="\n") as _f:
            _f.write(_body)
    try:
        sys.exit(subprocess.call([sys.executable, _eng] + sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(3)

import argparse
import hashlib
import html
import json
import math
import multiprocessing as mp
import pickle
import signal
import time
import traceback
from pathlib import Path
from statistics import NormalDist
from types import SimpleNamespace

import numpy as np
import pandas as pd

TZ = "America/New_York"
NORM = NormalDist()
MIN_DAY = 390
YEAR_MIN = 252 * MIN_DAY
NSLOT = 78
EV_VERSION = 1
LEVELS = ["PMH", "PML", "PDH", "PDL", "PDC", "ORH", "ORL", "VWAP", "EMA9"]
LEVEL_TEXT = {
    "PMH": "the pre-market high", "PML": "the pre-market low", "PDH": "yesterday's high",
    "PDL": "yesterday's low", "PDC": "yesterday's close (the gap-fill line)",
    "ORH": "the 15-minute opening-range high", "ORL": "the 15-minute opening-range low",
    "VWAP": "VWAP", "EMA9": "the 5-minute 9 EMA", "ANY": "any key level",
    "PM_ANY": "the pre-market high or low", "BAR": "a large 5-minute candle (no level needed)"}
DATASET_START = {"XNAS.ITCH": "2018-05-01"}
REASONS = np.array(["close/time", "stop", "target"])
EXIT_OK, EXIT_STOP, EXIT_CRASH = 0, 3, 5     # exit codes: 0 edge found, 3 stopped, 5 crash (the .bat restarts it)


def log(msg):
    print(msg, flush=True)


def fmt_td(sec):
    sec = int(sec)
    return f"{sec // 3600:d}:{sec % 3600 // 60:02d}:{sec % 60:02d}"


# ================================ DATA ======================================
import threading
import time

# Databento status feed: LULD pauses are StatusReason.LULD_PAUSE (50) with action HALT (8) or PAUSE (9);
# the unhalt is the next record with action TRADING (7).
LULD_REASON, ACT_HALT, ACT_PAUSE, ACT_TRADING = 50, 8, 9, 7
ACTION_NAMES = {"HALT": 8, "PAUSE": 9, "TRADING": 7, "QUOTING": 3, "CROSS": 4, "PRE_CROSS": 2, "PRE_OPEN": 1}
REASON_NAMES = {"LULD_PAUSE": 50, "NEWS_PENDING": 30, "NEWS_RELEASED": 31, "NONE": 0}
LEN_PATH = 96            # minutes of 1-minute bars kept after every unhalt
GRID_PRE = 90            # minutes before the 9:30 open kept for features
GRID = GRID_PRE + 390 + LEN_PATH + 8
MIN_PRE_BARS = 6
EXIT_INFO = 6            # exit code: --estimate only, nothing downloaded
# The status feed is asked ONLY for 09:33-16:00 New York time. Outside that window Databento sends a state-change record for
# every one of ~11,000 symbols at 4:00, 9:30 and 16:00 etc, which would cost 100x more and contains no LULD halts.
STATUS_FROM, STATUS_TO = "09:33", "16:00"


class CostCap(Exception):
    pass


class Budget:
    """What this run has spent / will spend on Databento. Cached data is free, so only NEW downloads count."""
    lock = threading.Lock()
    spent = 0.0

    @classmethod
    def charge(cls, amount, cap):
        with cls.lock:
            if cap and cls.spent + amount > cap:
                raise CostCap(f"the next download would take this run to about ${cls.spent + amount:.2f}, over MAX_COST ${cap:.2f}")
            cls.spent += amount


def halt_days(args):
    """Every weekday in the range (market holidays just return no data)."""
    start = pd.Timestamp(f"{args.first_year}-01-01")
    floor = DATASET_START.get(args.dataset)
    if floor is not None:
        start = max(start, pd.Timestamp(floor))
    return [d.strftime("%Y-%m-%d") for d in pd.bdate_range(start, pd.Timestamp(args.end) - pd.Timedelta(days=1))]


def status_cache(day, dataset):
    return Path("data_cache") / "halt_status" / f"{dataset.replace('.', '_')}_{day}.pkl"


def bars_cache(day, dataset):
    return Path("data_cache") / "halt_bars" / f"{dataset.replace('.', '_')}_{day}.pkl"


def ny_utc(day, hhmm):
    return pd.Timestamp(f"{day} {hhmm}", tz=TZ).tz_convert("UTC")


def _atomic_pickle(obj, path):
    """Write-then-rename, so a crash or Ctrl+C can never leave a half-written cache file behind."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp{os.getpid()}_{threading.get_ident()}")
    pd.to_pickle(obj, tmp)
    os.replace(tmp, path)


def status_params(day, args):
    return dict(dataset=args.dataset, symbols="ALL_SYMBOLS", schema="status", start=ny_utc(day, STATUS_FROM), end=ny_utc(day, STATUS_TO))


def bars_params(day, symbols, args):
    """Today's bars from 09:00, plus the last hour of the previous session (for the prior close)."""
    prev = (pd.Timestamp(day) - pd.offsets.BDay(1)).strftime("%Y-%m-%d")
    syms = sorted(symbols)
    a = dict(dataset=args.dataset, symbols=syms, schema="ohlcv-1m", start=ny_utc(day, "09:00"), end=ny_utc(day, "16:00"))
    b = dict(dataset=args.dataset, symbols=syms, schema="ohlcv-1m", start=ny_utc(prev, "15:00"), end=ny_utc(prev, "16:00"))
    return a, b


def _enum_val(v, names):
    if isinstance(v, (bytes, bytearray)):
        v = v.decode(errors="ignore")
    if hasattr(v, "value") and not isinstance(v, (int, float, str)):
        v = v.value
    if isinstance(v, (int, np.integer, float, np.floating)):
        return float(v)
    if isinstance(v, str):
        s = v.strip().upper().replace(" ", "_")
        if s.lstrip("-").isdigit():
            return float(s)
        return float(names.get(s, np.nan))
    return np.nan


def _col_num(s, names):
    if pd.api.types.is_numeric_dtype(s):
        return pd.to_numeric(s, errors="coerce").astype(float)
    return s.map(lambda v: _enum_val(v, names)).astype(float)


def extract_halts(df):
    """From a raw status DataFrame: one row per LULD pause -> (symbol, halt time, unhalt time)."""
    if df is None or len(df) == 0:
        empty = pd.to_datetime(pd.Series([], dtype="object"), utc=True).dt.tz_convert(TZ)
        return pd.DataFrame({"sym": pd.Series([], dtype=str), "halt_ts": empty, "resume_ts": empty}), {}
    d = df.reset_index()
    tcol = "ts_event" if "ts_event" in d.columns else d.columns[0]
    ts = pd.to_datetime(d[tcol], utc=True)
    sym = d["symbol"].astype(str) if "symbol" in d.columns else d["instrument_id"].astype(str)
    act, rea = _col_num(d["action"], ACTION_NAMES), _col_num(d["reason"], REASON_NAMES)
    notr = d["is_trading"].map(lambda v: v in ("N", 78, b"N")) if "is_trading" in d.columns else pd.Series(False, index=d.index)
    start = (rea == LULD_REASON) & (act.isin([ACT_HALT, ACT_PAUSE]) | notr)
    resume = act == ACT_TRADING
    diag = {}
    m = (rea == LULD_REASON) | act.isin([ACT_HALT, ACT_PAUSE])
    for (a, r), n in pd.DataFrame({"a": act[m], "r": rea[m]}).value_counts().head(12).items():
        diag[f"action={a:.0f} reason={r:.0f}"] = int(n)
    t = pd.DataFrame({"sym": sym.values, "ts": ts.values, "start": start.values, "resume": resume.values})
    t = t[t.start | t.resume]
    t = t[t.sym.isin(set(t.sym[t.start]))].sort_values(["sym", "ts"], kind="stable")
    rows = []
    for s, g in t.groupby("sym", sort=False):
        ts_, st, rs = g.ts.values, g.start.values, g.resume.values
        i, n = 0, len(g)
        while i < n:
            if st[i]:
                j, orphan = i + 1, False
                while j < n and not rs[j]:          # extended pause: further LULD records before the unhalt
                    if st[j] and ts_[j] - ts_[i] > np.timedelta64(20, "m"):
                        orphan = True               # 20+ minutes later: the first record never resumed; start over here
                        break
                    j += 1
                if orphan:
                    i = j
                    continue
                if j < n:
                    rows.append((s, ts_[i], ts_[j]))
                i = j + 1
            else:
                i += 1
    out = pd.DataFrame(rows, columns=["sym", "halt_ts", "resume_ts"])
    for c in ("halt_ts", "resume_ts"):
        out[c] = pd.to_datetime(out[c], utc=True).dt.tz_convert(TZ)
    return out, diag


def _sample(items, k):
    if len(items) <= k:
        return list(items)
    return [items[int(i)] for i in np.linspace(0, len(items) - 1, k).round()]


def _lock_year(args):
    return (pd.Timestamp(args.end) - pd.DateOffset(months=args.lockbox_months)).year


def _yearly(items, cost_fn):
    """{year: (number of new days, estimated cost per day)} from up to 3 evenly spaced sample days of EACH year,
    because the data volume (and so the price) differs a lot from year to year."""
    by = {}
    for d in items:
        by.setdefault(d[:4], []).append(d)
    return {y: (len(ds), float(np.mean([cost_fn(d) for d in _sample(ds, 3)]))) for y, ds in by.items()}


def _total(yearly):
    return sum(n * c for n, c in yearly.values())


def _from_year(yearly, y):
    return sum(n * c for yy, (n, c) in yearly.items() if yy >= y)


def _advice(yearly, args, already=0.0):
    """The earliest FIRST_YEAR that fits inside MAX_COST and still leaves the neural net a year to learn from."""
    room = args.max_cost - already
    for y in sorted(yearly):
        fty = max(args.first_test_year, int(y) + 1)
        if _from_year(yearly, y) <= room and fty <= _lock_year(args):
            return f"FIRST_YEAR={y} with FIRST_TEST_YEAR={fty} would cost about ${_from_year(yearly, y):.2f}"
    return "no start year fits inside MAX_COST"


def _grace(est, what, args, seconds=15):
    """No hard stop: say plainly what this will cost and give a few seconds to cancel (Ctrl+C) before it starts."""
    if est < 1.0 or args.yes:
        return
    log(f"\n  NOTE: downloading {what} will cost about ${est:.2f} on your Databento account. One time only: it is saved in")
    log(f"  data_cache afterwards, so later runs cost nothing. Press Ctrl+C within {seconds} seconds to cancel; otherwise it starts.")
    log("  (A cheaper run: set a later FIRST_YEAR / FIRST_TEST_YEAR at the top of the .bat. To skip this pause: add --yes.)")
    for _ in range(seconds):
        time.sleep(1)
    log("  starting ...")


def _fail_budget(msg, yearly, args, already=0.0):
    sys.exit(f"ERROR: {msg}\n       Nothing more was spent. Either raise MAX_COST in the .bat (or set it to 0 for no limit),\n"
             f"       or use a later start year: {_advice(yearly, args, already)}. Run with --estimate to see the cost without downloading.")


def _report_estimate(label, yearly, args, extra=""):
    n = sum(v[0] for v in yearly.values())
    limit = f"MAX_COST is ${args.max_cost:.2f}" if args.max_cost else "no spending limit set"
    log(f"  Estimated Databento cost for {label} ({n:,} new days): ${_total(yearly):.2f}   ({limit}). {extra}")
    log("    by year: " + "   ".join(f"{y}: ${c * k:.2f}" for y, (k, c) in sorted(yearly.items())))
    if len(yearly) > 1 and _total(yearly) >= 1.0:
        opts = []
        for y in sorted(yearly)[1:]:
            fty = max(args.first_test_year, int(y) + 1)
            if fty <= _lock_year(args):
                opts.append(f"FIRST_YEAR={y} (FIRST_TEST_YEAR={fty}): ${_from_year(yearly, y):.2f}")
        if opts:
            log("    cheaper starts: " + "   ".join(opts))


def load_halts(args):
    """One cached file per trading day, holding that day's LULD halts. Only missing days are downloaded."""
    days = halt_days(args)
    todo = [d for d in days if not status_cache(d, args.dataset).exists()]
    if todo:
        key = os.environ.get("DATABENTO_API_KEY")
        if not key:
            sys.exit(f"ERROR: {len(todo):,} days of halt data are not in data_cache yet and there is no Databento key.\n"
                     f"       Put your key alone on the first line of databento_key.txt next to this file.")
        import databento as db
        client = db.Historical(key)
        yearly = _yearly(todo, lambda d: client.metadata.get_cost(**status_params(d, args)))
        _report_estimate("the halt list (status feed, regular hours only)", yearly, args,
                         "1-minute bars for the halted stocks are estimated after the halts are known.")
        if args.estimate:
            log("  --estimate: nothing was downloaded or spent.")
            sys.exit(EXIT_INFO)
        if args.max_cost and _total(yearly) > args.max_cost:
            _fail_budget(f"the halt list alone is estimated at ${_total(yearly):.2f}, over MAX_COST ${args.max_cost:.2f}.", yearly, args)
        _grace(_total(yearly), "the halt list", args)
        from concurrent.futures import ThreadPoolExecutor, as_completed
        log(f"  downloading the halt list for {len(todo):,} days (first run only; cached afterwards) ...")
        errors = []

        def job(day):
            c = db.Historical(key)
            p = status_params(day, args)
            Budget.charge(c.metadata.get_cost(**p), args.max_cost)
            df = c.timeseries.get_range(**p).to_df()
            try:
                h, dg = extract_halts(df)
            except Exception:
                _atomic_pickle(df, Path("data_cache") / "halt_status_failed" / f"{day}.pkl")   # keep what was paid for
                raise
            _atomic_pickle((h, dg), status_cache(day, args.dataset))

        # the first few days run one at a time: if something is systematically wrong, find out after 3 downloads, not 1,500
        canary = todo[:3]
        for day in canary:
            try:
                job(day)
            except CostCap as e:
                _fail_budget(str(e), yearly, args)
            except Exception as e:
                sys.exit(f"ERROR: the first test download ({day}) failed: {type(e).__name__}: {e}\n"
                         f"       Stopped after spending very little. If this keeps happening, tell me this message.")
        rest = todo[3:]
        with ThreadPoolExecutor(max_workers=4) as ex:
            futs = {ex.submit(job, d): d for d in rest}
            done = len(canary)
            try:
                for fu in as_completed(futs):
                    try:
                        fu.result()
                    except CostCap as e:
                        ex.shutdown(wait=True, cancel_futures=True)
                        _fail_budget(str(e), yearly, args)
                    except Exception as e:                      # e.g. a day outside the feed's coverage
                        errors.append((futs[fu], f"{type(e).__name__}: {e}"))
                    done += 1
                    if done % 100 == 0 or done == len(todo):
                        log(f"    {done:,} / {len(todo):,} days  (spent about ${Budget.spent:.2f})")
            except KeyboardInterrupt:
                ex.shutdown(wait=False, cancel_futures=True)
                raise
        if errors and len(errors) > 0.25 * len(todo):
            sys.exit(f"ERROR: {len(errors)} of {len(todo)} days failed to download. First error ({errors[0][0]}): {errors[0][1]}")
        if errors:
            log(f"  {len(errors)} day(s) could not be downloaded and are skipped this time (they are retried automatically "
                f"the next time you run this). First: {errors[0][0]}: {errors[0][1][:140]}")
    frames, diag_all = [], {}
    for d in days:
        f = status_cache(d, args.dataset)
        if f.exists():
            h, dg = pd.read_pickle(f)
            if len(h):
                frames.append(h)
            for k, v in dg.items():
                diag_all[k] = diag_all.get(k, 0) + v
    halts = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(columns=["sym", "halt_ts", "resume_ts"])
    if halts.empty:
        sys.exit("ERROR: no LULD halts were found in the status feed. Status records with a pause/halt action were: "
                 f"{diag_all or 'none'}.\n       If you see an action/reason pair above that is the LULD pause, tell me the numbers.")
    dur = (halts.resume_ts - halts.halt_ts).dt.total_seconds() / 60.0
    halts = halts[(dur >= 1) & (dur <= 120)].copy()
    mod = halts.halt_ts.dt.hour * 60 + halts.halt_ts.dt.minute
    rmod = halts.resume_ts.dt.hour * 60 + halts.resume_ts.dt.minute
    halts = halts[(mod >= 9 * 60 + 35) & (rmod <= 15 * 60 + 55)].copy()      # regular-hours LULD pauses only
    halts["day"] = halts.halt_ts.dt.strftime("%Y-%m-%d")
    log(f"  {len(halts):,} LULD halts found ({halts.day.nunique():,} days, {halts.sym.nunique():,} symbols). "
        f"Status records used: {diag_all}")
    return halts.sort_values("halt_ts").reset_index(drop=True)


def _fetch_bars(client, day, symbols, args):
    a, b = bars_params(day, symbols, args)
    out = {}
    frames = []
    for p in (b, a):
        Budget.charge(client.metadata.get_cost(**p), args.max_cost)
        df = client.timeseries.get_range(**p).to_df()
        if len(df):
            frames.append(df)
    if frames:
        df = pd.concat(frames)
        df.index = pd.DatetimeIndex(pd.to_datetime(df.index, utc=True)).tz_convert(TZ)
        for s, g in df.groupby("symbol"):
            out[str(s)] = g[["open", "high", "low", "close", "volume"]].astype(float).sort_index()
    return out


def load_all_bars(halts, args):
    """1-minute bars around the halts of every halt day (cached per day); downloads only what is missing."""
    todo = [(day, set(g.sym)) for day, g in halts.groupby("day") if not bars_cache(day, args.dataset).exists()]
    if not todo:
        return
    key = os.environ.get("DATABENTO_API_KEY")
    if not key:
        sys.exit(f"ERROR: {len(todo)} days of halt bars are missing from data_cache and there is no Databento key.\n"
                 f"       Put your key alone on the first line of databento_key.txt next to this file.")
    import databento as db
    client = db.Historical(key)
    syms_of = dict(todo)
    days = [d for d, _ in todo]
    yearly = _yearly(days, lambda d: sum(client.metadata.get_cost(**p) for p in bars_params(d, syms_of[d], args)))
    per_day = _total(yearly) / max(len(todo), 1)
    _report_estimate("the 1-minute bars around the halts", yearly, args)
    if args.estimate:
        log("  --estimate: nothing was downloaded or spent.")
        sys.exit(EXIT_INFO)
    if args.max_cost and Budget.spent + _total(yearly) > args.max_cost:
        _fail_budget(f"the halt bars are estimated at ${_total(yearly):.2f} more (already spent ${Budget.spent:.2f}), over MAX_COST "
                     f"${args.max_cost:.2f}.", yearly, args, Budget.spent)
    _grace(_total(yearly), "the 1-minute bars around the halts", args)
    from concurrent.futures import ThreadPoolExecutor, as_completed
    log(f"  downloading 1-minute bars for {len(todo):,} halt days (first run only; cached afterwards) ...")
    errors = []

    def job(item):
        day, syms = item
        _atomic_pickle(_fetch_bars(db.Historical(key), day, syms, args), bars_cache(day, args.dataset))

    with ThreadPoolExecutor(max_workers=4) as ex:
        futs = {ex.submit(job, it): it[0] for it in todo}
        done = 0
        try:
            for fu in as_completed(futs):
                try:
                    fu.result()
                except CostCap as e:
                    ex.shutdown(wait=True, cancel_futures=True)
                    _fail_budget(str(e), yearly, args, Budget.spent)
                except Exception as e:
                    errors.append((futs[fu], f"{type(e).__name__}: {e}"))
                done += 1
                if done % 100 == 0 or done == len(todo):
                    log(f"    {done:,} / {len(todo):,} days  (spent about ${Budget.spent:.2f})")
        except KeyboardInterrupt:
            ex.shutdown(wait=False, cancel_futures=True)
            raise
    if errors and len(errors) > 0.25 * len(todo):
        sys.exit(f"ERROR: {len(errors)} of {len(todo)} bar downloads failed. First error ({errors[0][0]}): {errors[0][1]}")
    if errors:
        log(f"  {len(errors)} halt day(s) could not be downloaded and are skipped this time (retried the next run). "
            f"First: {errors[0][0]}: {errors[0][1][:140]}")


# ============================ EVENT BUILDING ================================
H_COLS = ("daykey", "date", "sym", "emin", "price", "hdir", "ret5", "ret15", "ret30", "dayret", "gap", "dur", "nth",
          "rvol", "dvol5", "rng5", "dow", "nb", "tid")
PATH_COLS = ("PO", "PH", "PL", "PC", "has")
EV_ALL = H_COLS + PATH_COLS


def _ffill(a):
    idx = np.where(np.isfinite(a), np.arange(len(a)), -1)
    np.maximum.accumulate(idx, out=idx)
    out = np.where(idx >= 0, a[np.maximum(idx, 0)], np.nan)
    return out


def events_for_symbol_day(b, day, halts, args, tick_id, daykey):
    """Features known at the moment of each unhalt, and the 1-minute price path that follows it."""
    d0 = pd.Timestamp(f"{day} 09:30", tz=TZ)
    mi = np.floor((b.index - d0).total_seconds().values / 60.0).astype(int)
    ok = (mi >= -GRID_PRE) & (mi < GRID - GRID_PRE)
    o, h, l, c, v = (np.full(GRID, np.nan) for _ in range(5))
    g = mi[ok] + GRID_PRE
    for arr, col in ((o, "open"), (h, "high"), (l, "low"), (c, "close")):
        arr[g] = b[col].values[ok]
    v[g] = b["volume"].values[ok]
    cf = _ffill(c)
    rth_prev = b[(b.index < d0.replace(hour=4, minute=0)) & (b.index.hour * 60 + b.index.minute >= 570) &
                 (b.index.hour * 60 + b.index.minute < 960)]
    prev_close = float(rth_prev["close"].iloc[-1]) if len(rth_prev) else np.nan
    oi = np.nonzero(np.isfinite(o[GRID_PRE:GRID_PRE + 390]))[0]
    day_open = float(o[GRID_PRE + oi[0]]) if len(oi) else np.nan
    rows = []
    for nth, (_, hr) in enumerate(halts.sort_values("halt_ts").iterrows(), 1):
        th = int((hr.halt_ts - d0).total_seconds() // 60)
        tr = int((hr.resume_ts - d0).total_seconds() // 60)
        if th < 5 or tr > 385 or tr <= th:
            continue
        if np.isfinite(c[GRID_PRE - 30:GRID_PRE + th + 1]).sum() < MIN_PRE_BARS:
            continue
        p = cf[GRID_PRE + th]                      # last price before the halt, including the minute the halt began
        if not (np.isfinite(p) and args.min_price <= p <= args.max_price):
            continue
        at = lambda m: cf[GRID_PRE + m]
        r5, r15, r30 = p / at(th - 5) - 1, p / at(th - 15) - 1, p / at(th - 30) - 1
        if not all(np.isfinite([r5, r15, r30])):
            continue
        v5 = float(np.nansum(v[GRID_PRE + th - 4:GRID_PRE + th + 1]))
        lo_m = max(th - 64, -30)                   # bars are downloaded from 09:00 only; never average over minutes we never asked for
        span = th - 4 - lo_m
        base = float(np.nansum(v[GRID_PRE + lo_m:GRID_PRE + th - 4])) / (span / 5.0) if span >= 10 else np.nan
        rvol = v5 / (base + 1.0) if np.isfinite(base) else 1.0
        hi5, lo5 = h[GRID_PRE + th - 4:GRID_PRE + th + 1], l[GRID_PRE + th - 4:GRID_PRE + th + 1]
        rng5 = (np.nanmax(hi5) - np.nanmin(lo5)) / p if np.isfinite(hi5).any() else 0.0
        path = slice(GRID_PRE + tr, GRID_PRE + tr + LEN_PATH)
        has = np.isfinite(c[path])
        cfp = cf[path]
        fill = np.where(np.isfinite(cfp), cfp, p)
        P = [np.where(np.isfinite(x[path]), x[path], fill) for x in (o, h, l, c)]
        hdir = 1 if r5 > 0 else (-1 if r5 < 0 else (1 if r15 >= 0 else -1))
        rows.append(dict(
            daykey=daykey, date=int(pd.Timestamp(day).strftime("%Y%m%d")), sym=0, emin=tr, price=p, hdir=hdir,
            ret5=r5, ret15=r15, ret30=r30,
            dayret=p / day_open - 1 if np.isfinite(day_open) else 0.0,
            gap=day_open / prev_close - 1 if (np.isfinite(day_open) and np.isfinite(prev_close)) else 0.0,
            dur=(hr.resume_ts - hr.halt_ts).total_seconds() / 60.0, nth=nth, rvol=rvol,
            dvol5=math.log10(1.0 + v5 * p), rng5=rng5, dow=pd.Timestamp(day).weekday(),
            nb=max(1, min(LEN_PATH, 390 - tr)), tid=tick_id, P=P, has=has))
    return rows


def build_halt_events(halts, args):
    cols = {k: [] for k in H_COLS}
    paths = {k: [] for k in PATH_COLS}
    ticks, tid, dkeys, missing = {}, 0, {}, 0
    for day, g in halts.groupby("day"):
        bf = bars_cache(day, args.dataset)
        if not bf.exists():
            missing += 1
            continue
        bars = pd.read_pickle(bf)
        for s, gg in g.groupby("sym"):
            b = bars.get(s)
            if b is None or len(b) < 10:
                continue
            if s not in ticks:
                ticks[s] = len(ticks)
            dk = dkeys.setdefault((s, day), len(dkeys) + 1)
            for r in events_for_symbol_day(b, day, gg, args, ticks[s], dk):
                for k in H_COLS:
                    cols[k].append(r[k])
                for k, a in zip(("PO", "PH", "PL", "PC"), r["P"]):
                    paths[k].append(a.astype(np.float32))
                paths["has"].append(r["has"].astype(np.uint8))
    if missing:
        log(f"  ({missing} halt day(s) had no bars downloaded and are left out; run again to retry them)")
    if not cols["date"]:
        sys.exit("ERROR: no usable halt events were built (no bars around the halts?).")
    out = {k: np.array(v) for k, v in cols.items()}
    out.update({k: np.vstack(v) for k, v in paths.items()})
    for k in ("daykey", "date", "sym", "emin", "hdir", "nth", "dow", "nb", "tid"):
        out[k] = out[k].astype(np.int64)
    order = np.lexsort((out["emin"], out["date"]))             # chronological
    out = {k: v[order] for k, v in out.items()}
    return out, list(ticks)


def as_events(d):
    ev = SimpleNamespace(**d)
    ev.year = ev.date // 10000
    ev.E = len(ev.daykey)
    ev.cache = {}
    return ev


def take_events(d, mask):
    return {k: v[mask] for k, v in d.items()}


def save_events(dirp, seg, d):
    for k, v in d.items():
        np.save(dirp / f"{seg}_{k}.npy", v)


def load_events(dirp, seg, mmap=True):
    d = {}
    for k in EV_ALL:
        d[k] = np.load(dirp / f"{seg}_{k}.npy", mmap_mode="r" if (mmap and k in PATH_COLS) else None)
    return as_events(d)


def concat_events(a, b):
    return as_events({k: np.concatenate([np.asarray(getattr(a, k)), np.asarray(getattr(b, k))]) for k in EV_ALL})


def make_dayinfo(ev):
    dates = np.unique(ev.date)
    blk_d = (dates // 10000) * 2 + (((dates // 100) % 100) > 6)
    ub = np.unique(blk_d)
    return SimpleNamespace(dates=dates, didx=np.searchsorted(dates, ev.date), D=len(dates),
                           bod=np.searchsorted(ub, blk_d), B=len(ub), blocks=ub)


# ============================== SIMULATION ==================================
def simulate_halt(ev, idx, side, delay, tp, sl, hold, args):
    """Shares bought (side +1) or sold short (side -1) at the unhalt. Entry = open of the 1-minute bar `delay` minutes after
    the first print; exit at +tp%, at -sl% (if the bar opens through the stop, the fill is the worse open), after `hold`
    minutes, or at the close. Slippage = the larger of a flat amount and a share of that bar's own range."""
    n, e = idx.size, int(delay)
    O, H, L, C = (np.asarray(getattr(ev, k)[idx])[:, e:].astype(float) for k in ("PO", "PH", "PL", "PC"))
    Lp = O.shape[1]
    call = side > 0
    entry_raw = O[:, 0]
    e2 = entry_raw[:, None]
    fav = np.where(call[:, None], H - e2, e2 - L)
    adv = np.where(call[:, None], e2 - L, H - e2)
    last = np.minimum(np.maximum(ev.nb[idx] - e, 1), int(hold) if hold else Lp) - 1
    valid = np.arange(Lp)[None, :] <= last[:, None]
    tp_abs = tp / 100.0 * entry_raw if tp else np.full(n, np.inf)
    sl_abs = sl / 100.0 * entry_raw if sl else np.full(n, np.inf)
    tp_hit, sl_hit = valid & (fav >= tp_abs[:, None]), valid & (adv >= sl_abs[:, None])
    big = Lp + 5
    ftp = np.where(tp_hit.any(1), tp_hit.argmax(1), big)
    fsl = np.where(sl_hit.any(1), sl_hit.argmax(1), big)
    ex = np.minimum(np.minimum(ftp, fsl), last)
    stop, take = (fsl < big) & (fsl <= ftp), (ftp < big) & (ftp < fsl)
    ar = np.arange(n)
    lvl_sl = entry_raw - side * sl_abs
    open_x = O[ar, ex]
    stop_fill = np.where(call, np.minimum(lvl_sl, open_x), np.maximum(lvl_sl, open_x))
    exit_raw = np.where(take, entry_raw + side * tp_abs, np.where(stop, stop_fill, C[ar, ex]))
    s_in = np.maximum(args.slip_bps / 1e4, args.slip_rng * (H[:, 0] - L[:, 0]) / entry_raw)
    s_out = np.maximum(args.slip_bps / 1e4, args.slip_rng * (H[ar, ex] - L[ar, ex]) / np.maximum(exit_raw, 1e-9))
    entry_px, exit_px = entry_raw * (1 + side * s_in), exit_raw * (1 - side * s_out)
    shares = args.budget / entry_px
    fees = shares * args.fee_share * 2
    pnl = shares * side * (exit_px - entry_px) - fees
    return dict(pnl=pnl, ex_min=ev.emin[idx] + e + ex + 1, hold=e + ex + 1, reason=np.where(stop, 1, np.where(take, 2, 0)),
                decay=np.zeros(n), spread=shares * (s_in * entry_raw + s_out * exit_raw), fees=fees,
                dirok=(side * (exit_raw - entry_raw) > 0).astype(float))


def simulate_chunked(ev, idx, side, *a, chunk=20000):
    if idx.size <= chunk:
        return simulate_halt(ev, idx, side, *a)
    parts = [simulate_halt(ev, idx[s:s + chunk], side[s:s + chunk], *a) for s in range(0, idx.size, chunk)]
    return {k: np.concatenate([p[k] for p in parts]) for k in parts[0]}


def seq_select(dk, emin, exm, maxday):
    """Walk forward in time, symbol-day by symbol-day: take a setup whenever we are flat (the previous trade has exited),
    up to maxday trades per symbol per day. Inputs must be sorted by (day key, entry minute)."""
    keep = np.zeros(len(dk), bool)
    cur, free, cnt = None, 0, 0
    for i in range(len(dk)):
        if dk[i] != cur:
            cur, free, cnt = dk[i], 0, 0
        if cnt < maxday and emin[i] >= free:
            keep[i] = True
            cnt += 1
            free = exm[i]
    return np.nonzero(keep)[0]


def stress_args(args):
    d = dict(vars(args))
    for k in ("slip_bps", "slip_rng", "fee_share"):
        d[k] = getattr(args, k) * args.stress
    return SimpleNamespace(**d)


# ============================ STATISTICS HELPERS ============================
def _betacf(a, b, x):
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1e-300 if abs(d) < 1e-300 else d
    d = 1.0 / d
    h = d
    for m in range(1, 300):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1e-300 if abs(d) < 1e-300 else d
        c = 1.0 + aa / c
        c = 1e-300 if abs(c) < 1e-300 else c
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1e-300 if abs(d) < 1e-300 else d
        c = 1.0 + aa / c
        c = 1e-300 if abs(c) < 1e-300 else c
        d = 1.0 / d
        de = d * c
        h *= de
        if abs(de - 1.0) < 3e-14:
            break
    return h


def _betai(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    bt = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def t_sf(t, df):
    """P(T > t) for a Student-t with df degrees of freedom (one-sided p-value)."""
    if df < 1:
        return 1.0
    p = 0.5 * _betai(df / 2.0, 0.5, df / (df + t * t))
    return p if t > 0 else 1.0 - p


def boot_p(x, t_obs, rng, n=100000):
    """One-sided bootstrap p-value that the mean of x is > 0 (centred bootstrap of the t-statistic)."""
    x = np.asarray(x, float)
    m = len(x)
    if m < 3:
        return 1.0
    xc = x - x.mean()
    cnt = done = 0
    while done < n:
        k = min(5000, n - done)
        draw = xc[rng.integers(0, m, size=(k, m))]
        sd = draw.std(1, ddof=1)
        tb = draw.mean(1) / (sd / math.sqrt(m) + 1e-12)
        cnt += int((tb >= t_obs).sum())
        done += k
    return (cnt + 1.0) / (n + 1.0)


def day_stats(dates, pnl):
    """Trades on the same day (SPY and QQQ move together) are summed into ONE observation, so the
    t-statistic is not inflated by counting correlated trades twice."""
    pnl = np.asarray(pnl, float)
    if len(pnl) == 0:
        return dict(n_days=0, n_trades=0, total=0.0, mean_day=0.0, t=0.0, win=0.0, dp=np.zeros(0), days=np.zeros(0, int))
    u, inv = np.unique(np.asarray(dates), return_inverse=True)
    dp = np.bincount(inv.ravel(), weights=pnl)
    n = len(dp)
    sd = dp.std(ddof=1) if n > 1 else 0.0
    t = float(dp.mean() / (sd / math.sqrt(n))) if sd > 0 else 0.0
    return dict(n_days=n, n_trades=len(pnl), total=float(pnl.sum()), mean_day=float(dp.mean()), t=t,
                win=float((pnl > 0).mean() * 100), dp=dp, days=u)


def make_curve(date, pnl, npts=160):
    """Cumulative P&L by day, thinned to at most npts points: [[yyyymmdd, cumulative $], ...]"""
    if len(pnl) == 0:
        return []
    u, inv = np.unique(np.asarray(date), return_inverse=True)
    cum = np.cumsum(np.bincount(inv.ravel(), weights=np.asarray(pnl, float)))
    sel = np.unique(np.linspace(0, len(u) - 1, min(npts, len(u))).round().astype(int))
    return [[int(u[i]), round(float(cum[i]), 1)] for i in sel]


def oos_summary(date, sym, pnl, pnl_s, n_sym, min_block_days=5):
    """Summary of an out-of-sample trade record, used by the gates."""
    ds, dss = day_stats(date, pnl), day_stats(date, pnl_s)
    blk = (date // 10000) * 2 + (((date // 100) % 100) > 6) if len(date) else np.zeros(0, int)
    pos = tot = 0
    for b in np.unique(blk):
        m = blk == b
        if len(np.unique(date[m])) >= min_block_days:
            tot += 1
            pos += int(pnl[m].sum() > 0)
    sym_ok = all(pnl[sym == s].sum() > 0 for s in range(n_sym) if (sym == s).sum() >= 20)
    return dict(n_days=ds["n_days"], n_trades=ds["n_trades"], total=ds["total"], t=ds["t"], win=ds["win"],
                mean_day=ds["mean_day"], pos_blocks=pos, n_blocks=tot, sym_ok=bool(sym_ok),
                stress_total=float(np.sum(pnl_s)), stress_t=dss["t"])


def hhmm(minutes_since_open):
    m = 570 + int(minutes_since_open)
    return f"{m // 60:02d}:{m % 60:02d}"


def money(v, plus=False):
    if v is None or (isinstance(v, float) and (math.isnan(v) or math.isinf(v))):
        return "-"
    s = f"${abs(v):,.0f}"
    return "-" + s if v < 0 else (("+" + s) if plus and v > 0 else s)


def pct(v):
    return "-" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.0f}%"


# ============================= RULE SEARCH ==================================
GENES = {
    "hdir": ["any", "up", "down"],                 # was the stock halted on a spike UP or a drop DOWN?
    "dur": ["any", "std", "ext"],                  # standard 5-minute pause vs an extended one
    "pmin": [0.5, 2.0, 5.0, 10.0],
    "pmax": [5.0, 10.0, 25.0, 1e9],
    "t0": [0, 15, 30, 60, 120],                    # unhalt time window, minutes after the 9:30 open
    "t1": [60, 120, 240, 330, 390],
    "pre": [0.0, 3.0, 6.0, 10.0],                  # min size (%) of the 15-minute run into the halt
    "rvol": [0.0, 2.0, 5.0],                       # min volume surge before the halt
    "nth": ["any", "first", "repeat"],             # first halt of the day for this stock, or a repeat
    "delay": [0, 1, 2, 3],                         # minutes to wait after the first print before buying
    "confirm": ["none", "with", "against"],        # the bar just before entry must move with / against us
    "tp": [1.0, 2.0, 3.0, 5.0, 8.0, 12.0],         # take profit, % of entry
    "sl": [0.0, 1.0, 2.0, 3.0, 5.0],               # stop loss, % of entry (0 = none)
    "hold": [1, 2, 3, 5, 10, 15, 30, 60],          # max minutes held
    "maxday": [1, 2],
}
GENE_NAMES = list(GENES)


def valid_cfg(c):
    return c["t1"] > c["t0"] and c["pmax"] > c["pmin"] and (c["confirm"] == "none" or c["delay"] >= 1)


def pick(rng, gene):
    ch = GENES[gene]
    return ch[int(rng.integers(len(ch)))]


def random_cfg(rng):
    while True:
        c = {g: pick(rng, g) for g in GENE_NAMES}
        if valid_cfg(c):
            return c


def mutate(cfg, rng):
    while True:
        c = dict(cfg)
        for g in rng.choice(GENE_NAMES, size=int(rng.integers(1, 3)), replace=False):
            c[g] = pick(rng, g)
        if valid_cfg(c):
            return c


def neighbors(cfg):
    out = []
    for g in GENE_NAMES:
        for v in GENES[g]:
            if v != cfg[g]:
                c = dict(cfg)
                c[g] = v
                if valid_cfg(c):
                    out.append(c)
    return out


def cfg_key(c):
    return tuple(c[g] for g in GENE_NAMES)


def cfg_from_key(k):
    return dict(zip(GENE_NAMES, k))


def cfg_hash(c):
    return int(hashlib.md5(repr(cfg_key(c)).encode()).hexdigest()[:15], 16)


def cfg_dist(a, b):
    return sum(a[g] != b[g] for g in GENE_NAMES)


def cfg_mask(ev, c, side_val):
    m = (ev.emin >= c["t0"]) & (ev.emin <= c["t1"]) & (ev.price >= c["pmin"]) & (ev.price < c["pmax"])
    m &= np.asarray(ev.has[:, c["delay"]]) > 0                     # there was a trade to buy at
    m &= ev.nb - c["delay"] >= 1
    if c["hdir"] != "any":
        m &= ev.hdir == (1 if c["hdir"] == "up" else -1)
    if c["dur"] == "std":
        m &= ev.dur <= 5.5
    elif c["dur"] == "ext":
        m &= ev.dur > 5.5
    if c["pre"]:
        m &= np.abs(ev.ret15) * 100 >= c["pre"]
    if c["rvol"]:
        m &= ev.rvol >= c["rvol"]
    if c["nth"] == "first":
        m &= ev.nth == 1
    elif c["nth"] == "repeat":
        m &= ev.nth >= 2
    if c["confirm"] != "none":
        k = c["delay"] - 1
        move = np.asarray(ev.PC[:, k]) - np.asarray(ev.PO[:, k])
        m &= (side_val * move > 0) if c["confirm"] == "with" else (side_val * move < 0)
    return m


def cfg_sim(ev, c, idx, side, args):
    return simulate_chunked(ev, idx, side, c["delay"], c["tp"], c["sl"], c["hold"], args)


def run_cfg(ev, c, args):
    """One trade per halt: the first qualifying unhalt per symbol per day (maxday=1), or several one after another."""
    idx = np.nonzero(cfg_mask(ev, c, args.side_val))[0]
    if idx.size == 0:
        return None
    side = np.full(idx.size, float(args.side_val))
    if c["maxday"] == 1:
        _, first = np.unique(ev.daykey[idx], return_index=True)
        idx = idx[np.sort(first)]
        side = side[:idx.size]
        return idx, side, cfg_sim(ev, c, idx, side, args)
    res = cfg_sim(ev, c, idx, side, args)
    o = np.lexsort((ev.emin[idx], ev.daykey[idx]))              # seq_select needs (stock-day, time) order, not market-wide time order
    keep = np.sort(o[seq_select(ev.daykey[idx][o], ev.emin[idx][o], res["ex_min"][o], c["maxday"])])
    return idx[keep], side[keep], {k: v[keep] for k, v in res.items()}


def stat_vec(ev, c, args, di, S):
    """Sufficient statistics of one strategy: per half-year block (traded days, sum and sum-of-squares of day P&L,
    trades) plus total P&L per group. Layout: [nd(B) s1(B) s2(B) nt(B) sym(S)]."""
    B = di.B
    out = np.zeros(4 * B + S)
    r = run_cfg(ev, c, args)
    if r is None:
        return out
    idx, _, res = r
    pnl = res["pnl"]
    d = di.didx[idx]
    dp = np.bincount(d, weights=pnl, minlength=di.D)
    dn = np.bincount(d, minlength=di.D)
    tr = dn > 0
    bd = di.bod[tr]
    out[:B] = np.bincount(bd, minlength=B)
    out[B:2 * B] = np.bincount(bd, weights=dp[tr], minlength=B)
    out[2 * B:3 * B] = np.bincount(bd, weights=dp[tr] ** 2, minlength=B)
    out[3 * B:4 * B] = np.bincount(bd, weights=dn[tr], minlength=B)
    out[4 * B:] = np.bincount(ev.sym[idx], weights=pnl, minlength=S)
    return out


def score_stats(M, B, S, years, args, gated=True, profit=True):
    """t-statistic of day P&L over the whole selection window. With gated=True a strategy only scores if it is
    positive in >= pos_blocks of the half-years and in the most recent year, and trades on enough days."""
    nd, s1, s2 = M[:, :B], M[:, B:2 * B], M[:, 2 * B:3 * B]
    ND, S1, S2 = nd.sum(1), s1.sum(1), s2.sum(1)
    with np.errstate(divide="ignore", invalid="ignore"):
        mean = S1 / ND
        var = np.maximum(S2 / ND - mean ** 2, 1e-12)
        t = mean / np.sqrt(var / ND)
    ok = ND >= args.min_days_year * years
    if profit:
        ok &= mean > 0
    if gated:
        ok &= ((s1 > 0) & (nd > 0)).sum(1) >= math.ceil(args.pos_blocks * B)
        ok &= s1[:, -2:].sum(1) > 0
    return np.where(ok, np.nan_to_num(t, nan=-np.inf), -np.inf)


def scramble_events(ev, seed):
    """Null world: every halt keeps its own features but is handed ANOTHER halt's price path after the unhalt (same time
    of day, rescaled to its own price). Nothing can be predicted here, so whatever score the search reaches is luck."""
    rng = np.random.default_rng(seed)
    d = {k: getattr(ev, k) for k in EV_ALL}
    ev2 = as_events(d)
    perm = np.arange(ev.E)
    bucket = np.asarray(ev.emin) // 30
    for bkt in np.unique(bucket):
        ids = np.nonzero(bucket == bkt)[0]
        perm[ids] = rng.permutation(ids)
    ref_i = np.asarray(ev.PO)[:, 0:1].astype(float)
    for name in ("PO", "PH", "PL", "PC"):
        P = np.asarray(getattr(ev, name)).astype(float)
        rel = (P / ref_i - 1.0)[perm]
        ev2.__dict__[name] = (ref_i * (1.0 + rel)).astype(np.float32)
    ev2.__dict__["has"] = np.asarray(ev.has)[perm]
    ev2.nb = np.asarray(ev.nb)[perm]
    return ev2


# ============================ NEURAL NETWORK ================================
TPL = [      # (entry delay in minutes, take-profit %, stop %, max hold minutes)
    dict(name="Buy at the unhalt, sell after 1 min", delay=0, tp=0.0, sl=0.0, hold=1),
    dict(name="Buy at the unhalt, sell after 5 min", delay=0, tp=0.0, sl=0.0, hold=5),
    dict(name="Buy at the unhalt, sell after 15 min", delay=0, tp=0.0, sl=0.0, hold=15),
    dict(name="Buy at the unhalt, TP 3% / SL 2%, max 15 min", delay=0, tp=3.0, sl=2.0, hold=15),
    dict(name="Buy at the unhalt, TP 5% / SL 3%, max 30 min", delay=0, tp=5.0, sl=3.0, hold=30),
    dict(name="Buy at the unhalt, TP 8% / SL 4%, max 60 min", delay=0, tp=8.0, sl=4.0, hold=60),
    dict(name="Wait 1 min, then sell after 5 min", delay=1, tp=0.0, sl=0.0, hold=5),
    dict(name="Wait 1 min, TP 3% / SL 2%, max 15 min", delay=1, tp=3.0, sl=2.0, hold=15),
    dict(name="Wait 2 min, then sell after 10 min", delay=2, tp=0.0, sl=0.0, hold=10),
    dict(name="Buy at the unhalt, sell after 60 min", delay=0, tp=0.0, sl=0.0, hold=60),
]
TSETS = {0: [0, 1, 2, 3], 1: [0, 1, 2, 3, 4, 5], 2: list(range(10))}
NN_GENES = {
    "h1": [8, 16, 32, 64], "h2": [4, 8, 16], "l2": [3e-4, 2e-3, 8e-3, 3e-2], "lr": [1e-3, 3e-3],
    "ens": [1, 2, 3], "tset": [0, 1, 2], "feat": ["all", "no_dow", "core"], "maxday": [1, 2],
}
CORE_GROUPS = {"halt direction", "run into the halt", "move today", "halt length", "price", "volume surge"}


def random_nn(rng):
    return {g: ch[int(rng.integers(len(ch)))] for g, ch in NN_GENES.items()}


def mutate_nn(cfg, rng):
    c = dict(cfg)
    for g in rng.choice(list(NN_GENES), size=int(rng.integers(1, 3)), replace=False):
        ch = NN_GENES[g]
        c[g] = ch[int(rng.integers(len(ch)))]
    return c


def nn_dist(a, b):
    return sum(a[g] != b[g] for g in NN_GENES)


def nn_features(ev, side):
    """One row per halt, everything known BEFORE the unhalt, signed so that positive means 'in the direction we trade'."""
    cl = lambda a, k: np.clip(np.asarray(a, float), -k, k)
    G = [
        ("halt direction", (ev.hdir * side)[:, None]),
        ("run into the halt", np.column_stack([cl(side * ev.ret5, 1) * 10, cl(side * ev.ret15, 1) * 10, cl(side * ev.ret30, 1) * 10])),
        ("move today", np.column_stack([cl(side * ev.dayret, 3) * 5, cl(side * ev.gap, 3) * 5])),
        ("halt length", np.column_stack([np.log1p(ev.dur), (ev.dur > 5.5).astype(float)])),
        ("which halt today", np.minimum(ev.nth, 4)[:, None]),
        ("price", np.log(np.maximum(ev.price, 0.01))[:, None]),
        ("volume surge", np.column_stack([np.log1p(np.clip(ev.rvol, 0, 200)), ev.dvol5])),
        ("volatility", np.clip(ev.rng5, 0, 1)[:, None] * 10),
        ("time of day", (np.asarray(ev.emin) / MIN_DAY)[:, None]),
        ("day of week", np.eye(5)[np.minimum(ev.dow, 4)]),
    ]
    X, names, cols, c0 = [], [], [], 0
    for name, a in G:
        a = np.asarray(a, float)
        X.append(a)
        names.append(name)
        cols.append(list(range(c0, c0 + a.shape[1])))
        c0 += a.shape[1]
    return np.hstack(X), names, cols


def feature_cols(names, cols, mode):
    keep = [n for n in names if (mode == "all") or (mode == "no_dow" and n != "day of week")
            or (mode == "core" and n in CORE_GROUPS)]
    sel = [c for n, cs in zip(names, cols) for c in cs if n in keep]
    pos = {c: i for i, c in enumerate(sel)}
    groups = [(n, [pos[c] for c in cs]) for n, cs in zip(names, cols) if n in keep]
    return sel, groups


class MLP:
    """Tiny feed-forward net: inputs -> tanh -> tanh -> outputs, trained with Adam."""

    def __init__(self, sizes, rng, out_bias):
        self.W = [rng.normal(0, 1 / math.sqrt(a), (a, b)) for a, b in zip(sizes[:-1], sizes[1:])]
        self.b = [np.zeros(b) for b in sizes[1:]]
        self.b[-1] = out_bias.copy()

    def fwd(self, X):
        A = [X]
        for l, (W, b) in enumerate(zip(self.W, self.b)):
            z = A[-1] @ W + b
            A.append(np.tanh(z) if l < len(self.W) - 1 else z)
        return A

    def predict(self, X):
        return self.fwd(X)[-1]

    def loss(self, X, Y, M):
        d = (self.predict(X) - Y) * M
        return float((d * d).sum() / max(M.sum(), 1))

    def fit(self, X, Y, M, Xv, Yv, Mv, rng, epochs=60, lr=3e-3, bs=1024, l2=2e-3, patience=6):
        params = self.W + self.b
        m = [np.zeros_like(p) for p in params]
        v = [np.zeros_like(p) for p in params]
        t, best, bad, n = 0, (1e18, None), 0, len(X)
        for _ in range(epochs):
            perm = rng.permutation(n)
            for s in range(0, n, bs):
                ib = perm[s:s + bs]
                A = self.fwd(X[ib])
                g = 2 * (A[-1] - Y[ib]) * M[ib] / max(M[ib].sum(), 1)
                gW, gb = [None] * len(self.W), [None] * len(self.W)
                for l in range(len(self.W) - 1, -1, -1):
                    gW[l] = A[l].T @ g + l2 * self.W[l]
                    gb[l] = g.sum(0)
                    if l > 0:
                        g = (g @ self.W[l].T) * (1 - A[l] ** 2)
                t += 1
                for p_, g_, m_, v_ in zip(params, gW + gb, m, v):
                    m_[:] = 0.9 * m_ + 0.1 * g_
                    v_[:] = 0.999 * v_ + 0.001 * g_ * g_
                    p_ -= lr * (m_ / (1 - 0.9 ** t)) / (np.sqrt(v_ / (1 - 0.999 ** t)) + 1e-8)
            vl = self.loss(Xv, Yv, Mv)
            if vl < best[0] - 1e-7:
                best, bad = (vl, [p.copy() for p in params]), 0
            else:
                bad += 1
                if bad >= patience:
                    break
        if best[1] is not None:
            for p_, b_ in zip(params, best[1]):
                p_[:] = b_


def nn_prepare(ev, cfg, args, cache):
    """Label every halt under every exit style: the net's training table."""
    key = cfg["tset"]
    if cache is not None and key in cache:
        return cache[key]
    if cache is not None:
        if "X" not in cache:
            cache["X"] = nn_features(ev, args.side_val)
        X, names, cols = cache["X"]
    else:
        X, names, cols = nn_features(ev, args.side_val)
    E = ev.E
    tpls = [TPL[i] for i in TSETS[cfg["tset"]]]
    K = len(tpls)
    side = np.full(E, float(args.side_val))
    idx = np.arange(E)
    PNL, M, HD = np.zeros((E, K)), np.zeros((E, K), bool), np.zeros((E, K))
    for k, t in enumerate(tpls):
        ok = (np.asarray(ev.has[:, t["delay"]]) > 0) & (np.asarray(ev.nb) - t["delay"] >= 1)
        res = simulate_chunked(ev, idx, side, t["delay"], t["tp"], t["sl"], t["hold"], args)
        PNL[:, k], M[:, k], HD[:, k] = np.where(ok, res["pnl"], 0.0), ok, res["hold"]
    D = dict(X=X, names=names, cols=cols, PNL=PNL, M=M, HD=HD, emin=np.asarray(ev.emin), E=E,
             Y=np.clip(PNL / args.budget, -1.0, 1.5), side=side, cidx=idx, cdate=np.asarray(ev.date),
             cdk=np.asarray(ev.daykey), K=K, tpls=tpls)
    if cache is not None:
        for k in [k for k in cache if k != "X"][:-2]:
            del cache[k]
        cache[key] = D
    return D


def pick_seq(D, best, tm, rows, margin, maxday):
    """Per symbol per day, walk forward in time: whenever we are flat and the net's best predicted return clears the margin,
    take the halt, up to maxday non-overlapping trades."""
    ce = np.nonzero(rows & (best >= margin))[0]
    if ce.size == 0:
        return ce
    dk, em = D["cdk"], D["emin"]
    ce = ce[np.lexsort((em[ce], dk[ce]))]
    keep = seq_select(dk[ce], em[ce], em[ce] + D["HD"][ce, tm[ce]], maxday)
    return ce[keep]


def nn_fold(D, cfg, lo, hi, rng, args, want_model=False):
    """Train on everything dated before `lo`, then trade the halts dated in [lo, hi). The confidence margin is chosen on
    the NEWEST 15% of the training period only; if nothing looks good it still trades (the gates judge the result)."""
    cdate = D["cdate"]
    tr = cdate < lo
    te = (cdate >= lo) & (cdate < hi)
    if tr.sum() < 300 or not te.any():
        return None
    cut = np.quantile(cdate[tr], 0.85)
    fit, ho = tr & (cdate <= cut), tr & (cdate > cut)
    sel, groups = feature_cols(D["names"], D["cols"], cfg["feat"])
    Xs = D["X"][:, sel]
    mu, sd = Xs[fit].mean(0), Xs[fit].std(0) + 1e-9
    Z = np.clip((Xs - mu) / sd, -5, 5)
    Y, Mf, K = D["Y"], D["M"].astype(float), D["K"]
    ymean = (Y[fit] * Mf[fit]).sum(0) / np.maximum(Mf[fit].sum(0), 1)
    need = ho | te
    nets, preds = [], []
    for _ in range(cfg["ens"]):
        net = MLP([Z.shape[1], cfg["h1"], cfg["h2"], K], rng, ymean)
        net.fit(Z[fit], Y[fit], Mf[fit], Z[ho], Y[ho], Mf[ho], rng, lr=cfg["lr"], l2=cfg["l2"], bs=256)
        nets.append(net)
        preds.append(net.predict(Z[need]))
    P = np.mean(preds, axis=0)
    best = np.full(len(cdate), -np.inf)
    tm = np.zeros(len(cdate), int)
    Pm = np.where(D["M"][need], P, -np.inf)
    best[need], tm[need] = Pm.max(1), Pm.argmax(1)
    bestm, bestt = -9.0, -1e9
    for mg in (-9.0, -0.05, 0.0, 0.01, 0.02, 0.04, 0.07, 0.10, 0.15, 0.25):
        r = pick_seq(D, best, tm, ho, mg, cfg["maxday"])
        if len(r) >= 25:
            tt = day_stats(cdate[r], D["PNL"][r, tm[r]])["t"]
            if tt > bestt:
                bestm, bestt = mg, tt
    r = pick_seq(D, best, tm, te, bestm, cfg["maxday"])
    out = dict(rows=r, tm=tm[r], margin=bestm, ho_t=bestt, n_train=int(tr.sum()))
    if want_model:
        out["model"] = dict(W=[[w.copy() for w in n.W] for n in nets], b=[[b.copy() for b in n.b] for n in nets],
                            mu=mu, sd=sd, sel=np.array(sel), cfg=cfg, margin=bestm)
        base = float(np.mean([n.loss(Z[ho], Y[ho], Mf[ho]) for n in nets]))
        imp = []
        for name, cs in groups:
            Zs = Z[ho].copy()
            Zs[:, cs] = Zs[rng.permutation(len(Zs))][:, cs]
            imp.append((name, float(np.mean([n.loss(Zs, Y[ho], Mf[ho]) for n in nets])) - base))
        out["importance"] = sorted(imp, key=lambda x: -x[1])
    return out


def nn_candidate(ev, cfg, args, folds, seed, cache=None, want_model=False):
    """One neural-net strategy variant, trained from scratch for each fold using only EARLIER halts, and the pooled
    out-of-sample trades it makes."""
    rng = np.random.default_rng(seed)
    D = nn_prepare(ev, cfg, args, cache)
    args_s = stress_args(args)
    keys = ("date", "sym", "pnl", "pnl_s", "tm", "fold", "side", "emin", "tid", "decay", "spread", "fees", "dirok")
    res = {k: [] for k in keys}
    res.update(folds=[], model=None, importance=None)
    for fi, (lo, hi) in enumerate(folds):
        f = nn_fold(D, cfg, lo, hi, rng, args, want_model)
        if f is None:
            continue
        r, tm = f["rows"], f["tm"]
        res["folds"].append(dict(lo=lo, hi=hi, margin=f["margin"], n=int(len(r)), n_train=f["n_train"], ho_t=f["ho_t"]))
        if want_model:
            res["model"], res["importance"] = f["model"], f["importance"]
        if not len(r):
            continue
        base = {n: np.zeros(len(r)) for n in ("pnl", "decay", "spread", "fees", "dirok")}
        pnl_s = np.zeros(len(r))
        for k in np.unique(tm):
            q = np.nonzero(tm == k)[0]
            t = D["tpls"][k]
            kw = (t["delay"], t["tp"], t["sl"], t["hold"])
            sim = simulate_chunked(ev, r[q], D["side"][r[q]], *kw, args)
            for n in base:
                base[n][q] = sim[n]
            pnl_s[q] = simulate_chunked(ev, r[q], D["side"][r[q]], *kw, args_s)["pnl"]
        for n in base:
            res[n].append(base[n])
        res["date"].append(np.asarray(ev.date)[r])
        res["sym"].append(np.asarray(ev.sym)[r])
        res["tid"].append(np.asarray(ev.tid)[r])
        res["pnl_s"].append(pnl_s)
        res["tm"].append(np.array([TSETS[cfg["tset"]][k] for k in tm]))
        res["fold"].append(np.full(len(r), fi))
        res["side"].append(D["side"][r])
        res["emin"].append(np.asarray(ev.emin)[r])
    for k in keys:
        res[k] = np.concatenate(res[k]) if res[k] else np.zeros(0)
    for k in ("date", "sym", "tm", "fold", "emin", "tid"):
        res[k] = res[k].astype(int)
    return res


# ============================ WORKER PROCESSES ==============================
_W = {}


def lower_priority():
    """Below-normal priority: still uses every idle core, but Windows stays responsive."""
    try:
        if os.name == "nt":
            import ctypes
            ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 0x00004000)
        else:
            os.nice(5)
    except Exception:
        pass


def keep_awake():
    if os.name == "nt":
        try:
            import ctypes
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)     # no sleep while hunting
        except Exception:
            pass


def _init_worker(cache_dir, args_d):
    try:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
    except Exception:
        pass
    lower_priority()
    args = SimpleNamespace(**args_d)
    ev = load_events(Path(cache_dir), "sel")          # the lockbox is never loaded here
    _W.update(args=args, dir=Path(cache_dir), ev=ev, di=make_dayinfo(ev), S=int(ev.sym.max()) + 1,
              nulls=None, nn={}, known=(None, None))


def get_nulls():
    if _W["nulls"] is None:
        _W["nulls"] = [scramble_events(_W["ev"], _W["args"].seed + 101 + k) for k in range(_W["args"].nulls)]
    return _W["nulls"]


def load_known(path):
    if _W["known"][0] != path:
        arr = np.load(path) if path and os.path.exists(path) else np.zeros(0, np.int64)
        _W["known"] = (path, set(arr.tolist()))
    return _W["known"][1]


def task_rules(spec):
    ev, args, di, S = _W["ev"], _W["args"], _W["di"], _W["S"]
    nulls = get_nulls()
    rng = np.random.default_rng(spec["seed"])
    known, seen = load_known(spec["known_path"]), set()
    elites, cfgs, real, nrows = spec["elites"], [], [], [[] for _ in nulls]
    guard = 0
    while len(cfgs) < spec["n"] and guard < spec["n"] * 30:
        guard += 1
        c = mutate(elites[int(rng.integers(len(elites)))], rng) if (elites and rng.random() > spec["p_random"]) \
            else random_cfg(rng)
        h = cfg_hash(c)
        if h in known or h in seen:
            continue
        seen.add(h)
        cfgs.append(cfg_key(c))
        real.append(stat_vec(ev, c, args, di, S))
        for k, en in enumerate(nulls):
            nrows[k].append(stat_vec(en, c, args, di, S))
    return dict(keys=cfgs, real=np.array(real), nulls=[np.array(x) for x in nrows])


def task_check(spec):
    """Full detail on one rule strategy: its trade record and cost breakdown, 1.5x costs, and (optionally)
    every one-setting-away neighbour (a real edge should survive those)."""
    ev, args, di, S = _W["ev"], _W["args"], _W["di"], _W["S"]
    c = spec["cfg"]
    r = run_cfg(ev, c, args)
    if r is None:
        base, stress = day_stats([], []), day_stats([], [])
        base.update(decay=0.0, spread=0.0, fees=0.0, dir_win=0.0, curve=[])
    else:
        idx, side, res = r
        base = day_stats(ev.date[idx], res["pnl"])
        base.update(decay=float(res["decay"].sum()), spread=float(res["spread"].sum()), fees=float(res["fees"].sum()),
                    dir_win=float(res["dirok"].mean() * 100),
                    curve=make_curve(ev.date[idx], res["pnl"]))
        stress = day_stats(ev.date[idx], cfg_sim(ev, c, idx, side, stress_args(args))["pnl"])
    for d in (base, stress):
        d.pop("dp"), d.pop("days")
    nb = neighbors(c) if spec.get("nbrs") else []
    rows = np.array([stat_vec(ev, n, args, di, S) for n in nb]) if nb else np.zeros((0, 4 * di.B + S))
    return dict(base=base, stress=stress, nb=rows)


def task_nn(spec):
    return nn_candidate(_W["ev"], spec["cfg"], _W["args"], spec["folds"], spec["seed"], cache=_W["nn"])


def task_lock_nn(spec):
    """Final fit on the WHOLE selection set, then trade the lockbox once."""
    ev_lock = load_events(_W["dir"], "lock", mmap=False)
    ev_all = concat_events(_W["ev"], ev_lock)
    return nn_candidate(ev_all, spec["cfg"], _W["args"], [(spec["lock_start"], 99999999)], spec["seed"],
                        cache=None, want_model=True)


TASKS = {"rules": task_rules, "check": task_check, "nn": task_nn, "locknn": task_lock_nn}


def run_task(spec):
    try:
        return spec["kind"], TASKS[spec["kind"]](spec), None, spec.get("tag")
    except Exception:
        return spec["kind"], None, traceback.format_exc(), spec.get("tag")


# ================================ THE HUNT ==================================
class StopHunt(Exception):
    pass


def jsonable(o):
    if isinstance(o, np.bool_):
        return bool(o)
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return float(o)
    if isinstance(o, np.ndarray):
        return o.tolist()
    if isinstance(o, (set, tuple)):
        return list(o)
    raise TypeError(str(type(o)))


def _stable_nn(cfg):
    return int(hashlib.md5(repr(sorted(cfg.items())).encode()).hexdigest()[:15], 16)


def nn_label(c):
    return (f"{c['h1']}-{c['h2']} hidden units x{c['ens']}, up to {c['maxday']} trades/stock/day, "
            f"exit set {c['tset']}, features '{c['feat']}'")


def short_label(c):
    return (f"{c['hdir']}-halts / dur:{c['dur']} / ${c['pmin']:g}-{('%g' % c['pmax']) if c['pmax'] < 1e8 else 'any'} / "
            f"{hhmm(c['t0'])}-{hhmm(c['t1'])} / run>={c['pre']:g}% vol>={c['rvol']:g}x / halt#:{c['nth']} / "
            f"wait {c['delay']}m confirm:{c['confirm']} / TP {c['tp']:g}% SL {c['sl']:g}% / hold {c['hold']}m / {c['maxday']}/day")


class Hunt:
    def __init__(self, args, meta, ev_dir, state_dir, pool, n_workers, syms):
        self.a, self.meta, self.dir, self.sdir, self.pool, self.W = args, meta, Path(ev_dir), Path(state_dir), pool, n_workers
        self.syms = syms
        self.sdir.mkdir(parents=True, exist_ok=True)
        ev = load_events(self.dir, "sel")
        di = make_dayinfo(ev)
        self.B, self.S, self.years = di.B, int(ev.sym.max()) + 1, di.D / 252.0
        self.folds = [(y * 10000 + 101, (y + 1) * 10000 + 101) for y in meta["test_years"]]
        self.lock_start = meta["lock_start"]
        self.n_sel_days = int(di.D)
        self.n_lock_days = int(len(np.unique(np.load(self.dir / "lock_date.npy"))))
        self.n_wf_days = int((di.dates >= self.folds[0][0]).sum())
        self.atr_by_sym = {}
        self.ev_lock = None
        self.state = self.load_state()
        self.pool_keys, self.pool_M, self.chunks = self.load_pool()
        self.known = set(np.load(self.sdir / "known.npy").tolist()) if (self.sdir / "known.npy").exists() else set()
        self.t0 = time.time() - self.state["elapsed"]
        self.stop_file = Path("STOP_HALTS.txt")
        self.round_no = self.state["rounds"]
        self.opened = False

    # ------------------------------------------------------------- persistence
    def load_state(self):
        p = self.sdir / "state.json"
        fresh = dict(rounds=0, elapsed=0.0, n_rules=0, n_nn=0, null_best=0.0, best_rule=0.0, best_nn_t=0.0,
                     ledger=[], checked={}, nn_hist=[], seed_ctr=0, attempts=[], attempt_ctr=0, rule_attempts={},
                     last_best_rule=None)
        if p.exists() and not self.a.fresh:
            try:
                st = json.loads(p.read_text())
                for k, v in fresh.items():
                    st.setdefault(k, v)
                log(f"  resuming a previous hunt: {st['rounds']} rounds, {st['n_rules']:,} rule strategies, "
                    f"{st['n_nn']} neural nets, {len(st['ledger'])} sealed-test look(s) already used")
                return st
            except Exception:
                log("  (could not read the saved state, starting fresh)")
        return fresh

    def load_pool(self):
        p = self.sdir / "pool.pkl"
        if p.exists() and not self.a.fresh:
            try:
                with open(p, "rb") as f:
                    keys, M = pickle.load(f)
                if M.shape[1] == 4 * self.B + self.S:
                    return keys, M, []
            except Exception:
                pass
        return [], np.zeros((0, 4 * self.B + self.S)), []

    def merge_chunks(self):
        if self.chunks:
            self.pool_M = np.vstack([self.pool_M] + self.chunks)
            self.chunks = []

    def save(self):
        self.merge_chunks()
        self.state["elapsed"] = time.time() - self.t0
        self.state["rounds"] = self.round_no
        (self.sdir / "state.json").write_text(json.dumps(self.state, default=jsonable))
        with open(self.sdir / "pool.pkl", "wb") as f:
            pickle.dump((self.pool_keys, self.pool_M), f, protocol=4)
        np.save(self.sdir / "known.npy", np.array(sorted(self.known), dtype=np.int64))

    # ------------------------------------------------------------- helpers
    def should_stop(self):
        if self.stop_file.exists():
            return "STOP_HALTS.txt found"
        if self.a.max_hours and (time.time() - self.t0) / 3600.0 >= self.a.max_hours:
            return f"MAX_HOURS ({self.a.max_hours}) reached"
        return None

    def check_stop(self):
        why = self.should_stop()
        if why:
            raise StopHunt(why)

    def call(self, spec, stoppable=True):
        ar = self.pool.apply_async(run_task, (spec,))
        while True:
            if stoppable:
                self.check_stop()
            try:
                kind, res, err, _ = ar.get(timeout=2)
                break
            except mp.TimeoutError:
                continue
        if err:
            raise RuntimeError(f"{spec['kind']} task failed:\n{err}")
        return res

    def alpha_k(self, k):
        return self.a.alpha * 6.0 / (math.pi ** 2 * k * k)

    def nn_tmin(self, M):
        return max(self.a.nn_tmin, NORM.inv_cdf(1.0 - 0.25 / max(M, 1)))

    def rule_thr(self):
        return max(self.a.rule_tmin, self.state["null_best"] + self.a.null_margin)

    def attempted(self, kind):
        return [h["cfg"] for h in self.state["ledger"] if h["kind"] == kind]

    def power(self, t_in, basis_days, shrink):
        """Would a REAL edge of this size have a fair chance (min_power) of clearing the next lockbox bar?
        Expected lockbox t = shrink x (t seen so far) x sqrt(lockbox days / days that t was measured over)."""
        k = len(self.state["ledger"]) + 1
        need = NORM.inv_cdf(1.0 - self.alpha_k(k)) + NORM.inv_cdf(self.a.min_power)
        return shrink * t_in * math.sqrt(self.n_lock_days / max(basis_days, 1)), need

    def attempt_by_id(self, i):
        for r in reversed(self.state["attempts"]):
            if r["id"] == i:
                return r
        return None

    def add_attempt(self, **kw):
        self.state["attempt_ctr"] += 1
        rec = dict(id=self.state["attempt_ctr"], round=self.round_no, when=time.strftime("%Y-%m-%d %H:%M"), **kw)
        self.state["attempts"].append(rec)
        return rec

    # ------------------------------------------------------------- rule pool
    def rule_elites(self):
        self.merge_chunks()
        if not len(self.pool_M):
            return []
        g = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=True)
        r = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=False)
        idx = list(dict.fromkeys(list(np.argsort(-g)[:20]) + list(np.argsort(-r)[:20])))
        return [cfg_from_key(self.pool_keys[i]) for i in idx if max(g[i], r[i]) > -np.inf]

    def compact_pool(self):
        if len(self.pool_keys) <= 400000:
            return
        self.merge_chunks()
        r = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=False)
        keep = set(np.argsort(-r)[:120000].tolist())
        rng = np.random.default_rng(len(self.pool_keys))
        keep |= set(rng.choice(len(r), size=40000, replace=False).tolist())
        keep = np.array(sorted(keep))
        self.pool_keys = [self.pool_keys[i] for i in keep]
        self.pool_M = self.pool_M[keep]

    def absorb_rules(self, res):
        if not len(res["keys"]):
            return
        self.pool_keys.extend(res["keys"])
        self.chunks.append(res["real"])
        for k in res["keys"]:
            self.known.add(cfg_hash(cfg_from_key(k)))
        self.state["n_rules"] += len(res["keys"])
        for nm in res["nulls"]:
            sc = score_stats(nm, self.B, self.S, self.years, self.a, gated=True)
            if np.isfinite(sc).any():
                self.state["null_best"] = max(self.state["null_best"], float(sc[np.isfinite(sc)].max()))

    def rule_reasons(self, score_g, score_r, thr, chk=None, total=None):
        """Plain-English reasons a rule strategy did not make it to the sealed test."""
        a, why = self.a, []
        if total is not None and total <= 0:
            why.append("it lost money (spread and time decay outweigh any edge it has)")
        elif score_g == -np.inf:
            why.append(f"it was not consistent enough: it must trade on at least {a.min_days_year} days a year, make money in at least "
                       f"{int(a.pos_blocks * 100)}% of half-years and in the latest year")
        elif score_g < thr:
            why.append(f"its score ({score_g:.1f}) is not clearly above what pure luck reaches: the same search on scrambled, "
                       f"unpredictable data scored {self.state['null_best']:.1f}, so it needs at least {thr:.1f}")
        else:
            exp_t, need = self.power(score_g, self.n_sel_days, a.shrink_rule)
            if exp_t < need:
                why.append(f"even if it is real, it is too small to be confirmed on the sealed test "
                           f"(expected score there ~{exp_t:.1f}, needs ~{need:.1f})")
        if chk is not None:
            if chk["nb_frac"] < a.nbr_frac:
                why.append(f"it falls apart when settings are nudged: only {chk['nb_frac'] * 100:.0f}% of near-identical "
                           f"variants are profitable (needs {a.nbr_frac * 100:.0f}%)")
            if chk["stress_total"] <= 0:
                why.append("it stops making money if trading costs are 1.5x higher")
        return why

    def rule_attempt(self, cfg, score_g, score_r, thr, nbrs):
        """Run the detailed check for a rule strategy; creates (or refreshes) its attempt record."""
        h = str(cfg_hash(cfg))
        res = self.call(dict(kind="check", cfg=cfg, nbrs=nbrs))
        base, st = res["base"], res["stress"]
        chk = None
        if nbrs:
            nb = score_stats(res["nb"], self.B, self.S, self.years, self.a, gated=False) if len(res["nb"]) else np.zeros(0)
            frac = float(np.mean(nb >= 1.0)) if len(nb) else 0.0
            chk = dict(nb_frac=frac, n_nb=int(len(nb)), stress_total=float(st["total"]), stress_t=float(st["t"]))
            chk["ok"] = bool(frac >= self.a.nbr_frac and st["total"] > 0)
            self.state["checked"][h] = chk
            log(f"    checked rule: {short_label(cfg)}\n      near-identical variants still profitable {frac * 100:.0f}% "
                f"(need {self.a.nbr_frac * 100:.0f}%), at 1.5x costs {money(st['total'], True)} -> {'PASS' if chk['ok'] else 'fail'}")
        why = self.rule_reasons(score_g, score_r, thr, chk, base['total'])
        stats = dict(n_days=base["n_days"], n_trades=base["n_trades"], total=base["total"], t=float(score_g if np.isfinite(score_g) else base["t"]),
                     win=base["win"], dir_win=base["dir_win"], decay=base["decay"], spread=base["spread"], fees=base["fees"], stress_total=float(st["total"]))
        status = "rejected" if why else "ready"
        verdict = ("Rejected: " + "; ".join(why) + ".") if why else "Cleared every internal test - eligible for a sealed-test look."
        curves = [dict(name="Chosen from this period (in-sample: it was picked because it looked good)", kind="sel", pts=base["curve"])]
        rid = self.state["rule_attempts"].get(h)
        rec = self.attempt_by_id(rid) if rid else None
        if rec is None:
            rec = self.add_attempt(kind="rule", title="Rule strategy", label=short_label(cfg), cfg=cfg,
                                   lines=describe(cfg, self.a))
            self.state["rule_attempts"][h] = rec["id"]
        rec.update(status=status, verdict=verdict, stats=stats, curves=curves, round=self.round_no)
        return rec, (chk or dict(ok=False))

    def rule_candidate(self):
        self.merge_chunks()
        if not len(self.pool_M):
            return None
        g = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=True)
        r = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=False)
        fin = np.isfinite(g)
        self.state["best_rule"] = float(g[fin].max()) if fin.any() else 0.0
        thr = self.rule_thr()
        r2 = score_stats(self.pool_M, self.B, self.S, self.years, self.a, gated=False, profit=False)
        lead = int(np.argmax(g)) if fin.any() else (int(np.argmax(r)) if np.isfinite(r).any() else int(np.argmax(r2)))
        if max(g[lead], r[lead], r2[lead]) > -np.inf:          # keep a record of every new "best rule so far"
            cfg = cfg_from_key(self.pool_keys[lead])
            if str(cfg_hash(cfg)) != self.state["last_best_rule"] and str(cfg_hash(cfg)) not in self.state["rule_attempts"]:
                self.rule_attempt(cfg, g[lead], r[lead], thr, nbrs=False)
            self.state["last_best_rule"] = str(cfg_hash(cfg))
        done, checks = self.attempted("rule"), 0
        for i in np.argsort(-g)[:40]:
            if g[i] < thr:
                break
            cfg = cfg_from_key(self.pool_keys[i])
            if any(cfg_dist(cfg, d) <= 2 for d in done):
                continue
            exp_t, need = self.power(g[i], self.n_sel_days, self.a.shrink_rule)
            if exp_t < need:
                continue
            h = str(cfg_hash(cfg))
            chk = self.state["checked"].get(h)
            if chk is None:
                if checks >= 2:
                    continue
                checks += 1
                rec, chk = self.rule_attempt(cfg, g[i], r[i], thr, nbrs=True)
            if chk["ok"]:
                return cfg, float(g[i]) / thr
        return None

    # ------------------------------------------------------------- neural nets
    def nn_gate(self, s, M):
        a = self.a
        tmin, why = self.nn_tmin(M), []
        need_days = max(a.nn_min_days, int(a.min_trade_frac * self.n_wf_days))
        if s["n_days"] < need_days:
            why.append(f"it traded on only {s['n_days']} days on years it never trained on (needs {need_days})")
        elif s["total"] <= 0:
            why.append("it lost money on years it never trained on")
        elif s["t"] < tmin:
            why.append(f"its score ({s['t']:.1f}) is not high enough: after trying {M} networks some look good by luck, so it needs {tmin:.1f}")
        if s["n_days"] >= need_days and s["total"] > 0:
            if s["n_blocks"] < 3 or s["pos_blocks"] < math.ceil(0.6 * s["n_blocks"]):
                why.append("its profit was not consistent across half-years")
            if not s["sym_ok"]:
                why.append("it lost money on one of the tickers")
            if s["stress_total"] <= 0:
                why.append("it stops making money if trading costs are 1.5x higher")
        if not why:
            exp_t, need = self.power(s["t"], self.n_wf_days, a.shrink_nn)
            if exp_t < need:
                why.append(f"even if it is real, it is too small to be confirmed on the sealed test "
                           f"(expected score there ~{exp_t:.1f}, needs ~{need:.1f})")
        return (not why), tmin, why

    def absorb_nn(self, spec, res):
        a = self.a
        s = oos_summary(res["date"], res["sym"], res["pnl"], res["pnl_s"], self.S)
        self.state["n_nn"] += 1
        M = self.state["n_nn"]
        ok, tmin, why = self.nn_gate(s, M)
        s.update(cfg=spec["cfg"], seed=spec["seed"], key=str(_stable_nn(spec["cfg"])))
        stats = dict(n_days=s["n_days"], n_trades=s["n_trades"], total=s["total"], t=s["t"], win=s["win"],
                     dir_win=float(np.mean(res["dirok"]) * 100) if len(res["dirok"]) else 0.0,
                     decay=float(np.sum(res["decay"])), spread=float(np.sum(res["spread"])), fees=float(np.sum(res["fees"])),
                     stress_total=s["stress_total"], pos_blocks=s["pos_blocks"], n_blocks=s["n_blocks"])
        verdict = ("Cleared every internal test - eligible for a sealed-test look." if ok
                   else ("Rejected: " + "; ".join(why) + "." if why else "Rejected."))
        if not s["n_trades"]:
            verdict = "Rejected: it never found a setup it trusted enough to trade."
        rec = self.add_attempt(kind="nn", title=f"Neural network #{M}", label=nn_label(spec["cfg"]), cfg=spec["cfg"],
                               status="ready" if ok else "rejected", verdict=verdict, stats=stats,
                               curves=[dict(name="Out-of-sample (each year traded by a net that only saw earlier years)", kind="oos",
                                            pts=make_curve(res["date"], res["pnl"]))],
                               lines=None)
        s["attempt"] = rec["id"]
        self.state["nn_hist"].append(s)
        if s["n_days"] >= 30:
            self.state["best_nn_t"] = max(self.state["best_nn_t"], float(s["t"]))
        if s["n_days"]:
            log(f"    NN #{M} ({spec['cfg']['h1']}-{spec['cfg']['h2']} x{spec['cfg']['ens']}, {spec['cfg']['maxday']}/day): "
                f"out-of-sample {s['n_trades']} trades, {money(s['total'], True)}, score {s['t']:.2f}")

    def nn_pick(self):
        M, best, done = max(self.state["n_nn"], 1), None, self.attempted("nn")
        for s in self.state["nn_hist"]:
            if s.get("attempted") or any(nn_dist(s["cfg"], d) <= 2 for d in done):
                continue
            ok, tmin, _ = self.nn_gate(s, M)
            if ok and (best is None or s["t"] / tmin > best[1]):
                best = (s, s["t"] / tmin)
        return best

    def nn_elites(self):
        h = [s for s in self.state["nn_hist"] if s["n_days"] >= 30]
        return [s["cfg"] for s in sorted(h, key=lambda s: -s["t"])[:8]]

    # ------------------------------------------------------------- lockbox
    def get_lock(self):
        if self.ev_lock is None:
            self.ev_lock = load_events(self.dir, "lock", mmap=False)
        return self.ev_lock

    def lockbox_attempt(self, kind, cfg, extra):
        """Show a candidate the lockbox. Costs part of the error budget whatever the outcome."""
        a, k = self.a, len(self.state["ledger"]) + 1
        ak = self.alpha_k(k)
        ls = self.lock_start
        log(f"\n  >>> SEALED TEST LOOK #{k}: a {kind} candidate cleared every internal gate. To pass it needs "
            f"p <= {ak:.5f} (one-sided) on {ls // 10000}-{ls // 100 % 100:02d}-{ls % 100:02d} onward ...")
        model = None
        if kind == "rule":
            ev = self.get_lock()
            r = run_cfg(ev, cfg, a)
            if r is None:
                z = np.zeros(0)
                rec = dict(date=np.zeros(0, int), sym=np.zeros(0, int), tid=np.zeros(0, int), pnl=z, pnl_s=z, decay=z, spread=z, fees=z, dirok=z)
            else:
                idx, side, res = r
                rec = dict(date=np.asarray(ev.date)[idx], sym=np.asarray(ev.sym)[idx], tid=np.asarray(ev.tid)[idx], pnl=res["pnl"],
                           pnl_s=cfg_sim(ev, cfg, idx, side, stress_args(a))["pnl"], decay=res["decay"],
                           spread=res["spread"], fees=res["fees"], dirok=res["dirok"])
            label = short_label(cfg)
        else:
            rec = self.call(dict(kind="locknn", cfg=cfg, seed=extra["seed"] + 1, lock_start=self.lock_start))
            model, label = rec.get("model"), nn_label(cfg)
        ds = day_stats(rec["date"], rec["pnl"])
        n = ds["n_days"]
        p_t = t_sf(ds["t"], n - 1) if n > 2 else 1.0
        p_b = boot_p(ds["dp"], ds["t"], np.random.default_rng(a.seed + k)) if n > 2 else 1.0
        p = max(p_t, p_b)
        stress_total = float(np.sum(rec["pnl_s"]))
        passed = bool(p <= ak and ds["total"] > 0 and n >= a.min_lock_days and stress_total > 0)
        entry = dict(k=k, kind=kind, cfg=cfg, label=label, n_days=n, n_trades=ds["n_trades"], total=ds["total"],
                     t=ds["t"], p=p, p_t=p_t, p_boot=p_b, alpha_k=ak, stress_total=stress_total, passed=passed,
                     win=ds["win"], when=time.strftime("%Y-%m-%d %H:%M"))
        self.state["ledger"].append(dict(entry))
        att_id = extra.get("attempt") if kind == "nn" else self.state["rule_attempts"].get(str(cfg_hash(cfg)))
        att = self.attempt_by_id(att_id) if att_id else None
        if kind == "nn":
            for s in self.state["nn_hist"]:
                if s["key"] == extra["key"]:
                    s["attempted"] = True
        why_not = []
        if p > ak:
            why_not.append(f"p-value {p:.4f} is above the {ak:.4f} needed")
        if ds["total"] <= 0:
            why_not.append("it lost money")
        if n < a.min_lock_days:
            why_not.append(f"too few days ({n}, needs {a.min_lock_days})")
        if stress_total <= 0:
            why_not.append("not profitable at 1.5x costs")
        if att is not None:
            att["status"] = "passed" if passed else "failed_lockbox"
            att["verdict"] = ("EDGE CONFIRMED: it made money on the sealed months it had never been near, and the result is "
                              "statistically strong enough to rule out luck.") if passed else \
                ("Failed the sealed test: " + "; ".join(why_not) + ". This look used up part of the error budget.")
            att["lock"] = dict(n_days=n, n_trades=ds["n_trades"], total=ds["total"], t=ds["t"], p=p, alpha_k=ak, win=ds["win"],
                               dir_win=float(np.mean(rec["dirok"]) * 100) if len(rec["dirok"]) else 0.0,
                               stress_total=stress_total, decay=float(np.sum(rec["decay"])), spread=float(np.sum(rec["spread"])),
                               fees=float(np.sum(rec["fees"])), k=k)
            att["curves"] = [c for c in att["curves"] if c["kind"] != "lock"] + [
                dict(name="Sealed test (never seen by the search)", kind="lock_pass" if passed else "lock_fail",
                     pts=make_curve(rec["date"], rec["pnl"]))]
        log(f"      sealed test: {ds['n_trades']} trades over {n} days, {money(ds['total'], True)}, score {ds['t']:.2f}, "
            f"p={p:.5f} (needed {ak:.5f}), at 1.5x costs {money(stress_total, True)}  ->  "
            f"{'*** EDGE CONFIRMED ***' if passed else 'not confirmed (error budget spent, hunt continues)'}")
        entry["attempt"] = att_id
        return passed, entry, rec, model

    # ------------------------------------------------------------- one round
    def run_round(self):
        a, st, W = self.a, self.state, self.W
        self.round_no += 1
        t_r = time.time()
        np_path = self.sdir / f"known_{self.round_no}.npy"
        np.save(np_path, np.array(sorted(self.known), dtype=np.int64))
        for old in self.sdir.glob("known_*.npy"):
            if old != np_path:
                try:
                    old.unlink()
                except OSError:
                    pass
        elites = self.rule_elites()
        nn_el = self.nn_elites()
        seen_nn = {s["key"] for s in st["nn_hist"]}
        specs = []
        for _ in range(a.nn_tasks or W):
            st["seed_ctr"] += 1
            rng = np.random.default_rng(a.seed * 7919 + st["seed_ctr"])
            for _try in range(60):
                cfg = mutate_nn(nn_el[int(rng.integers(len(nn_el)))], rng) if (nn_el and rng.random() < 0.6) else random_nn(rng)
                if str(_stable_nn(cfg)) not in seen_nn:
                    break
            seen_nn.add(str(_stable_nn(cfg)))
            specs.append(dict(kind="nn", cfg=cfg, seed=int(rng.integers(1 << 30)), folds=self.folds, tag=len(specs)))
        for _ in range(a.rule_tasks or 2 * W):
            st["seed_ctr"] += 1
            specs.append(dict(kind="rules", seed=a.seed * 104729 + st["seed_ctr"], n=a.rule_batch, elites=elites,
                              p_random=0.4 if elites else 1.0, known_path=str(np_path), tag=len(specs)))
        log(f"\n[round {self.round_no}] {len(specs)} jobs on {W} cores ...")
        it = self.pool.imap_unordered(run_task, specs)
        pending, errs = len(specs), 0
        while pending:
            self.check_stop()
            try:
                kind, res, err, tag = it.next(timeout=2)
            except mp.TimeoutError:
                continue
            pending -= 1
            if err:
                errs += 1
                log(f"  !! a {kind} job crashed (job skipped):\n{err}")
                if errs >= 3 and errs == len(specs) - pending:
                    raise RuntimeError("every job is failing - see the error above")
                continue
            if kind == "rules":
                self.absorb_rules(res)
            else:
                self.absorb_nn(specs[tag], res)
        self.compact_pool()
        found = None
        cand = self.rule_candidate()
        nnc = self.nn_pick()
        if cand or nnc:
            # one sealed-test look per round, for whichever candidate is furthest above its own bar
            if cand and (not nnc or cand[1] >= nnc[1]):
                ok, entry, rec, model = self.lockbox_attempt("rule", cand[0], {})
            else:
                s = nnc[0]
                ok, entry, rec, model = self.lockbox_attempt("nn", s["cfg"], s)
            if ok:
                found = (entry, rec, model)
        self.save()
        self.progress(time.time() - t_r, "found" if found else "hunting")
        return found

    def progress(self, dt, status="hunting", why=""):
        st = self.state
        M = max(st["n_nn"], 1)
        if dt is not None:
            log(f"[round {self.round_no} done in {fmt_td(dt)} | hunting for {fmt_td(time.time() - self.t0)}]  "
                f"rules tried {st['n_rules']:,}: best score {st['best_rule']:.2f}, luck-only {st['null_best']:.2f}, "
                f"needs >= {self.rule_thr():.2f}  |  neural nets tried {st['n_nn']}: best score {st['best_nn_t']:.2f}, "
                f"needs >= {self.nn_tmin(M):.2f}  |  sealed-test looks used {len(st['ledger'])}")
        try:
            out = Path(self.a.out)
            out.mkdir(parents=True, exist_ok=True)
            write_dashboard(out / "report.html", self.payload(status, why))
            if not self.opened and not self.a.no_browser:
                self.opened = True
                import webbrowser
                webbrowser.open((out / "report.html").resolve().as_uri())
        except Exception:
            log("(could not write the dashboard)\n" + traceback.format_exc())

    def visible_attempts(self):
        """Keep the page light: everything that reached the sealed test or the internal gates, the best and the
        newest of the rest."""
        att = self.state["attempts"]
        keep = {r["id"] for r in att if r["status"] in ("passed", "failed_lockbox", "ready")}
        rest = [r for r in att if r["id"] not in keep]
        keep |= {r["id"] for r in rest[-150:]}
        keep |= {r["id"] for r in sorted(rest, key=lambda r: -r["stats"].get("t", 0))[:100]}
        return [r for r in att if r["id"] in keep]

    def payload(self, status, why="", winner=None):
        st, a = self.state, self.a
        M = max(st["n_nn"], 1)
        k = len(st["ledger"]) + 1
        ls = self.lock_start
        return dict(
            status=status, why=why, generated=time.strftime("%Y-%m-%d %H:%M:%S"),
            meta=dict(symbols=self.syms, budget=a.budget, alpha=a.alpha,
                      stress=a.stress, lock_months=a.lockbox_months,
                      lock_start=ls, lock_date=f"{ls // 10000}-{ls // 100 % 100:02d}-{ls % 100:02d}",
                      sel_days=self.n_sel_days, lock_days=self.n_lock_days, wf_days=self.n_wf_days,
                      kind="halt", side=a.side, slip_bps=a.slip_bps, slip_rng=a.slip_rng, fee_share=a.fee_share,
                      min_price=a.min_price, max_price=a.max_price),
            hunt=dict(rounds=self.round_no, elapsed=time.time() - self.t0, n_rules=st["n_rules"], n_nn=st["n_nn"],
                      best_rule=st["best_rule"], null_best=st["null_best"], rule_thr=self.rule_thr(),
                      best_nn=st["best_nn_t"], nn_thr=self.nn_tmin(M), looks=len(st["ledger"]),
                      next_alpha=self.alpha_k(k)),
            ledger=st["ledger"], attempts=self.visible_attempts(), n_attempts=len(st["attempts"]), winner=winner)

    def run(self):
        ls = self.lock_start
        log(f"  Sealed test period: {ls // 10000}-{ls // 100 % 100:02d}-{ls % 100:02d} onward (never used by the search).  "
            f"Error budget ALPHA={self.a.alpha}.  Stop any time: Ctrl+C or create STOP_HALTS.txt")
        self.progress(None, "hunting")
        while True:
            self.check_stop()
            found = self.run_round()
            if found:
                return found
            if self.a.max_rounds and self.round_no >= self.a.max_rounds:
                raise StopHunt(f"MAX_ROUNDS ({self.a.max_rounds}) reached")


# =============================== DESCRIPTIONS ===============================
def describe(c, args):
    verb = "Buy" if args.side_val > 0 else "Sell short"
    when = f"unhalting between {hhmm(c['t0'])} and {hhmm(c['t1'])} (time of day, counted from the 9:30 open)"
    lines = [f"Signal: a Nasdaq stock whose LULD (limit up / limit down) volatility pause just ended, {when}."]
    filt = []
    if c["hdir"] != "any":
        filt.append("the stock was halted after a spike UP" if c["hdir"] == "up" else "the stock was halted after a drop DOWN")
    if c["dur"] != "any":
        filt.append("a standard 5-minute pause" if c["dur"] == "std" else "an extended pause (longer than 5 minutes)")
    filt.append(f"price {'$%g to $%g' % (c['pmin'], c['pmax']) if c['pmax'] < 1e8 else 'at least $%g' % c['pmin']}")
    if c["pre"]:
        filt.append(f"it ran at least {c['pre']:g}% in the 15 minutes before the halt")
    if c["rvol"]:
        filt.append(f"volume in the 5 minutes before the halt was at least {c['rvol']:g}x normal")
    if c["nth"] != "any":
        filt.append("the first halt of the day for that stock" if c["nth"] == "first" else "a repeat halt (second or later that day)")
    lines.append("Filters: " + "; ".join(filt) + ".")
    wait = ("at the first print after the unhalt" if c["delay"] == 0 else f"{c['delay']} minute(s) after the first print")
    cf = {"none": "", "with": " Only if the bar just before entry moved in our direction.",
          "against": " Only if the bar just before entry moved against us."}[c["confirm"]]
    lines.append(f"Entry: {verb.lower()} shares {wait}.{cf}")
    lines.append(f"Take profit: {'+%g%% from the entry' % c['tp']}. Stop loss: " + (f"-{c['sl']:g}% from the entry (a gap through the stop fills at the worse price)." if c["sl"] else "none."))
    lines.append(f"Time exit: sell after {c['hold']} minute(s) if neither is hit, and always before the close.")
    lines.append(f"Costs charged on every trade: slippage of at least {args.slip_bps:g} bps each way (more when the bar is wide) "
                 f"and ${args.fee_share:g} per share each way. "
                 + ("One trade per stock per day." if c["maxday"] == 1 else f"Up to {c['maxday']} trades per stock per day, one at a time."))
    return lines


def describe_nn(c, args=None):
    exits = ", ".join(TPL[i]["name"] for i in TSETS[c["tset"]])
    return [f"A neural network ({c['h1']} and {c['h2']} hidden units, ensemble of {c['ens']}, weight decay {c['l2']}, "
            f"learning rate {c['lr']}, feature set '{c['feat']}').",
            "Every LULD unhalt is scored by the network under each exit style; it predicts the net return after slippage and fees "
            "from what was known before the unhalt (run into the halt, halt length, price, volume surge, move today, time of day).",
            f"Exit styles it chooses between: {exits}.",
            f"Up to {c['maxday']} trade(s) per stock per day, one at a time, each only if its predicted return clears a confidence "
            "margin that was chosen on the newest slice of the training years.",
            "The weights are retrained from scratch on every year of data before the period it trades (walk-forward)."]


# =============================== DASHBOARD ==================================
DASH_HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Halt Hunter</title>
<script>
(function(){var t=null;try{t=localStorage.getItem('eh-theme')}catch(e){}
if(!t){t=(window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light'}
document.documentElement.setAttribute('data-theme',t)})();
</script>
<style>
:root{--bg:#f3f5f9;--card:#ffffff;--text:#172033;--muted:#5b6880;--line:#dfe4ed;--soft:#eef2f8;
--accent:#2457d6;--accent-soft:#e4ecff;--good:#0f7d3d;--good-soft:#e1f5e9;--bad:#c0332b;--bad-soft:#fdeceb;
--warn:#9a5d00;--warn-soft:#fff2d1;--c-sel:#7d8aa0;--c-oos:#2457d6;--shadow:0 1px 2px rgba(20,30,50,.06),0 6px 18px rgba(20,30,50,.05)}
:root[data-theme=dark]{--bg:#0d1118;--card:#151b26;--text:#e8ecf4;--muted:#9aa7bb;--line:#263046;--soft:#1c2433;
--accent:#74a7ff;--accent-soft:#1b2c50;--good:#4fd18c;--good-soft:#11301f;--bad:#ff7d74;--bad-soft:#3b1d1d;
--warn:#f4bb5a;--warn-soft:#3b3012;--c-sel:#7f8ca1;--c-oos:#74a7ff;--shadow:none}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1180px;margin:0 auto;padding:22px 18px 60px}
header{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:14px}
h1{font-size:26px;margin:0;letter-spacing:-.01em}
.sub{color:var(--muted);font-size:14px;margin-top:2px}
h2{font-size:20px;margin:0 0 4px}
h3{font-size:15px;margin:18px 0 8px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.04em}
button,select{font:inherit;color:var(--text);background:var(--card);border:1px solid var(--line);border-radius:10px;padding:7px 12px;cursor:pointer}
button:hover{border-color:var(--accent)}
button:disabled{opacity:.4;cursor:default}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px 20px;box-shadow:var(--shadow);margin:14px 0}
.banner{border-radius:16px;padding:20px 22px;margin:14px 0;border:1px solid}
.banner .h{font-size:22px;font-weight:700;margin-bottom:4px}
.banner p{margin:4px 0 0}
.b-hunt{background:var(--accent-soft);border-color:var(--accent)}
.b-good{background:var(--good-soft);border-color:var(--good)}
.b-stop{background:var(--warn-soft);border-color:var(--warn)}
.pulse{display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--accent);margin-right:8px;animation:p 1.4s infinite}
@keyframes p{0%{opacity:1}50%{opacity:.25}100%{opacity:1}}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:14px 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 16px}
.stat .k{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
.stat .v{font-size:24px;font-weight:700;margin-top:2px}
.stat .n{font-size:12px;color:var(--muted);margin-top:2px}
.meter{margin:14px 0 6px}
.meter .row{display:flex;justify-content:space-between;gap:10px;font-size:14px;flex-wrap:wrap}
.track{position:relative;height:14px;border-radius:8px;background:var(--soft);margin-top:6px;overflow:visible}
.fill{height:100%;border-radius:8px;background:var(--accent)}
.fill.ok{background:var(--good)}
.mark{position:absolute;top:-4px;width:2px;height:22px;background:var(--text);opacity:.7}
.help{color:var(--muted);font-size:13px;margin:4px 0 0}
.chips{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:10px 0}
.chip{border-radius:999px;padding:5px 13px;font-size:14px}
.chip.on{background:var(--accent);color:#fff;border-color:var(--accent)}
:root[data-theme=dark] .chip.on{color:#0d1118}
.grid{display:grid;grid-template-columns:330px 1fr;gap:16px;align-items:start}
.list{max-height:640px;overflow:auto;border:1px solid var(--line);border-radius:12px;background:var(--bg)}
.item{display:block;width:100%;text-align:left;border:0;border-bottom:1px solid var(--line);border-radius:0;background:transparent;padding:10px 12px}
.item:hover{background:var(--soft)}
.item.sel{background:var(--accent-soft);box-shadow:inset 3px 0 0 var(--accent)}
.item .t{font-weight:600;font-size:14px;display:flex;justify-content:space-between;gap:6px}
.item .m{font-size:12px;color:var(--muted);margin-top:2px}
.badge{display:inline-block;border-radius:999px;padding:2px 10px;font-size:12px;font-weight:700;white-space:nowrap}
.bd-passed{background:var(--good);color:#fff}
:root[data-theme=dark] .bd-passed{color:#0d1118}
.bd-failed_lockbox{background:var(--bad-soft);color:var(--bad);border:1px solid var(--bad)}
.bd-ready{background:var(--accent-soft);color:var(--accent);border:1px solid var(--accent)}
.bd-rejected{background:var(--soft);color:var(--muted);border:1px solid var(--line)}
.nav{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:10px}
.nav select{flex:1;min-width:160px;max-width:100%}
.verdict{border-radius:12px;padding:12px 14px;margin:10px 0;font-size:15px;border:1px solid var(--line);background:var(--soft)}
.verdict.good{background:var(--good-soft);border-color:var(--good)}
.verdict.bad{background:var(--bad-soft);border-color:var(--bad)}
.verdict.info{background:var(--accent-soft);border-color:var(--accent)}
svg.chart{width:100%;height:auto;display:block;background:var(--card);border:1px solid var(--line);border-radius:12px}
.ax{fill:var(--muted);font-size:11px}
.gl{stroke:var(--line);stroke-width:1}
.zero{stroke:var(--muted);stroke-dasharray:4 4;stroke-width:1}
.ln{fill:none;stroke-width:2.4;stroke-linejoin:round}
.ln-sel{stroke:var(--c-sel)}.ln-oos{stroke:var(--c-oos)}.ln-lock_pass{stroke:var(--good)}.ln-lock_fail{stroke:var(--bad)}
.lockline{stroke:var(--warn);stroke-dasharray:5 4;stroke-width:1.5}
.cw{position:relative}
.tip{position:absolute;pointer-events:none;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:7px 10px;font-size:13px;box-shadow:var(--shadow);display:none;z-index:5;white-space:nowrap}
.legend{display:flex;gap:16px;flex-wrap:wrap;font-size:13px;color:var(--muted);margin:8px 2px}
.sw{display:inline-block;width:18px;height:4px;border-radius:2px;margin-right:6px;vertical-align:middle}
table{border-collapse:collapse;width:100%;font-size:14px}
th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
th:first-child,td:first-child{text-align:left}
th{color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.03em}
td.l,th.l{text-align:left;white-space:normal}
tr.tot td{font-weight:700;background:var(--soft)}
tr.click{cursor:pointer}tr.click:hover td{background:var(--soft)}
.tw{overflow-x:auto}
.pos{color:var(--good)}.neg{color:var(--bad)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.two>*,.grid>*{min-width:0}
ol.steps,ul.plain{margin:6px 0;padding-left:22px}
ol.steps li,ul.plain li{margin:5px 0}
details{border-top:1px solid var(--line);padding:10px 0}
details:first-of-type{border-top:0}
summary{cursor:pointer;font-weight:600}
details p,details ul{margin:8px 0 2px;color:var(--text)}
.muted{color:var(--muted)}
.empty{padding:30px;text-align:center;color:var(--muted)}
footer{color:var(--muted);font-size:13px;margin-top:22px}
@media (max-width:860px){.grid{grid-template-columns:1fr}.list{max-height:260px}.two{grid-template-columns:1fr}.wrap{padding:14px 12px 50px}h1{font-size:22px}}
</style></head><body>
<div class="wrap" id="app"></div>
<script>
const D = __DATA__;
const $ = (s, r) => (r || document).querySelector(s);
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const usd = v => (v < 0 ? '-' : '') + '$' + Math.abs(Math.round(v)).toLocaleString('en-US');
const sg = v => (v > 0 ? '+' : '') + usd(v);
const cl = v => v > 0 ? 'pos' : (v < 0 ? 'neg' : '');
const num = (v, d) => (v == null || !isFinite(v)) ? '-' : Number(v).toFixed(d == null ? 1 : d);
const dur = s => { s = Math.round(s); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h ? h + 'h ' + m + 'm' : m + 'm ' + (s % 60) + 's'; };
const dnum = n => new Date(Math.floor(n / 10000), Math.floor(n / 100) % 100 - 1, n % 100).getTime();
const dstr = n => new Date(dnum(n)).toLocaleDateString('en-US', {year: 'numeric', month: 'short', day: 'numeric'});
const BADGE = {passed: 'EDGE CONFIRMED', failed_lockbox: 'Failed sealed test', ready: 'Passed internal tests', rejected: 'Rejected'};
const M = D.meta, H = D.hunt;
let filter = 'all', sort = 'new', cur = null;

function attemptsFiltered() {
  let a = D.attempts.slice();
  if (filter === 'lock') a = a.filter(x => x.lock);
  else if (filter === 'nn') a = a.filter(x => x.kind === 'nn');
  else if (filter === 'rule') a = a.filter(x => x.kind === 'rule');
  if (sort === 'new') a.sort((x, y) => y.id - x.id);
  else if (sort === 'score') a.sort((x, y) => (y.stats.t || -99) - (x.stats.t || -99));
  else a.sort((x, y) => (y.stats.total || -1e9) - (x.stats.total || -1e9));
  return a;
}
function byId(id) { return D.attempts.find(x => x.id === id); }

function costTable(att) {
  const cols = [['Test period', att.stats, att.kind === 'rule' ? 'chosen because it looked good' : 'out-of-sample']];
  if (att.lock) cols.push(['Sealed test', att.lock, 'never seen']);
  const rows = [
    ['Profit from the price moving your way', s => s.total + s.spread + s.fees],
    ['Slippage (worse fills when a halted stock reopens)', s => -s.spread],
    ['Fees', s => -s.fees],
    ['Net profit', s => s.total],
    ['Net profit if costs were 1.5x higher', s => s.stress_total]];
  let h = '<div class="tw"><table><tr><th class="l">Where the money went</th>' + cols.map(c => '<th>' + esc(c[0]) + '</th>').join('') + '</tr>';
  rows.forEach((r, i) => {
    h += '<tr' + (i === 3 ? ' class="tot"' : '') + '><td class="l">' + esc(r[0]) + '</td>' +
      cols.map(c => { const v = r[1](c[1]); return '<td class="' + cl(v) + '">' + sg(v) + '</td>'; }).join('') + '</tr>';
  });
  return h + '</table></div>';
}

function drawChart(el, att) {
  const curves = att.curves.filter(c => c.pts.length);
  if (!curves.length) { el.innerHTML = '<div class="empty">This attempt made no trades, so there is nothing to graph.</div>'; return; }
  const base = curves.find(c => c.kind === 'sel' || c.kind === 'oos');
  const off = base ? base.pts[base.pts.length - 1][1] : 0;
  const S = curves.map(c => ({name: c.name, kind: c.kind, off: c.kind.indexOf('lock') === 0 ? off : 0,
    pts: c.pts.map(p => [dnum(p[0]), p[1] + (c.kind.indexOf('lock') === 0 ? off : 0), p[0]])}));
  const W = 900, Ht = 340, L = 66, R = 16, T = 14, B = 32;
  let x0 = Infinity, x1 = -Infinity, y0 = 0, y1 = 0;
  S.forEach(s => s.pts.forEach(p => { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }));
  if (att.lock) x1 = Math.max(x1, dnum(M.lock_start));
  const pad = Math.max((y1 - y0) * 0.08, 20); y0 -= pad; y1 += pad;
  const X = t => L + (W - L - R) * (t - x0) / Math.max(x1 - x0, 1);
  const Y = v => T + (Ht - T - B) * (y1 - v) / (y1 - y0);
  let g = '';
  for (let i = 0; i <= 4; i++) { const v = y0 + (y1 - y0) * i / 4; g += '<line class="gl" x1="' + L + '" x2="' + (W - R) + '" y1="' + Y(v) + '" y2="' + Y(v) + '"/><text class="ax" x="' + (L - 8) + '" y="' + (Y(v) + 4) + '" text-anchor="end">' + usd(v) + '</text>'; }
  const yA = new Date(x0).getFullYear(), yB = new Date(x1).getFullYear();
  for (let y = yA; y <= yB + 1; y++) { const t = new Date(y, 0, 1).getTime(); if (t >= x0 && t <= x1) g += '<line class="gl" x1="' + X(t) + '" x2="' + X(t) + '" y1="' + T + '" y2="' + (Ht - B) + '"/><text class="ax" x="' + (X(t) + 4) + '" y="' + (Ht - B + 16) + '">' + y + '</text>'; }
  g += '<line class="zero" x1="' + L + '" x2="' + (W - R) + '" y1="' + Y(0) + '" y2="' + Y(0) + '"/>';
  if (att.lock) { const lx = X(dnum(M.lock_start)); g += '<line class="lockline" x1="' + lx + '" x2="' + lx + '" y1="' + T + '" y2="' + (Ht - B) + '"/><text class="ax" x="' + (lx + 5) + '" y="' + (T + 11) + '">sealed test starts</text>'; }
  S.forEach(s => { g += '<polyline class="ln ln-' + s.kind + '" points="' + s.pts.map(p => X(p[0]).toFixed(1) + ',' + Y(p[1]).toFixed(1)).join(' ') + '"/>'; });
  g += '<line id="xh" class="zero" y1="' + T + '" y2="' + (Ht - B) + '" style="display:none"/>';
  el.innerHTML = '<div class="cw"><svg class="chart" viewBox="0 0 ' + W + ' ' + Ht + '" role="img" aria-label="Cumulative profit and loss">' + g +
    '<rect id="hit" x="' + L + '" y="' + T + '" width="' + (W - L - R) + '" height="' + (Ht - T - B) + '" fill="transparent"/></svg><div class="tip" id="tip"></div></div>' +
    '<div class="legend">' + S.map(s => '<span><span class="sw" style="background:var(--' + ({sel: 'c-sel', oos: 'c-oos', lock_pass: 'good', lock_fail: 'bad'})[s.kind] + ')"></span>' + esc(s.name) + '</span>').join('') + '</div>';
  const svg = $('svg', el), tip = $('#tip', el), xh = $('#xh', el), hit = $('#hit', el);
  hit.addEventListener('mousemove', e => {
    const r = svg.getBoundingClientRect(), px = (e.clientX - r.left) / r.width * W, t = x0 + (px - L) / (W - L - R) * (x1 - x0);
    let html = '', dd = '';
    S.forEach(s => { let b = null; s.pts.forEach(p => { if (b === null || Math.abs(p[0] - t) < Math.abs(b[0] - t)) b = p; });
      if (b && Math.abs(b[0] - t) < (x1 - x0) * 0.25) { dd = dd || dstr(b[2]); html += '<div>' + esc(s.kind.indexOf('lock') === 0 ? 'Sealed test' : 'Profit so far') + ': <b class="' + cl(b[1] - s.off) + '">' + sg(b[1] - s.off) + '</b></div>'; } });
    if (!html) { tip.style.display = 'none'; return; }
    xh.style.display = ''; xh.setAttribute('x1', px); xh.setAttribute('x2', px);
    tip.innerHTML = '<div class="muted">' + dd + '</div>' + html; tip.style.display = 'block';
    const left = (e.clientX - r.left) + 14; tip.style.left = Math.min(left, r.width - 170) + 'px'; tip.style.top = (e.clientY - r.top + 8) + 'px';
  });
  hit.addEventListener('mouseleave', () => { tip.style.display = 'none'; xh.style.display = 'none'; });
}

function statCards(s, isLock, den) {
  const c = (k, v, n, c2) => '<div class="stat"><div class="k">' + k + '</div><div class="v ' + (c2 || '') + '">' + v + '</div>' + (n ? '<div class="n">' + n + '</div>' : '') + '</div>';
  return '<div class="stats">' + c('Net profit', sg(s.total), isLock ? 'on the sealed months' : 'after all costs', cl(s.total)) +
    c('Trades', s.n_trades, 'on ' + s.n_days + ' of ' + den + ' days (' + Math.round(100 * s.n_days / Math.max(den, 1)) + '%)') + c('Win rate', num(s.win, 0) + '%', 'trades that made money after costs') + c('Stock moved your way', num(s.dir_win, 0) + '%', 'before costs: about 50% is a coin flip') +
    c('Score', num(s.t, 2), isLock ? 'p-value ' + num(s.p, 4) + ' (needs \u2264 ' + num(s.alpha_k, 4) + ')' : 'higher = harder to be luck') + '</div>';
}

function renderDetail() {
  const el = $('#detail'), a = cur ? byId(cur) : null;
  const lst = attemptsFiltered();
  if (!a) { el.innerHTML = '<div class="empty">Nothing to show yet. The first attempts appear after the first round finishes.</div>'; return; }
  const i = lst.findIndex(x => x.id === a.id);
  let h = '<div class="nav"><button id="prev"' + (i <= 0 ? ' disabled' : '') + '>&larr; Newer</button><button id="next"' + (i < 0 || i >= lst.length - 1 ? ' disabled' : '') + '>Older &rarr;</button>' +
    '<select id="pick" aria-label="Choose an attempt">' + lst.map(x => '<option value="' + x.id + '"' + (x.id === a.id ? ' selected' : '') + '>#' + x.id + ' \u00b7 ' + esc(x.title) + ' \u00b7 ' + esc(BADGE[x.status]) + '</option>').join('') + '</select></div>';
  h += '<h2>' + esc(a.title) + ' <span class="badge bd-' + a.status + '">' + esc(BADGE[a.status]) + '</span></h2>';
  h += '<div class="muted" style="font-size:14px">Attempt #' + a.id + ' \u00b7 round ' + a.round + ' \u00b7 ' + esc(a.when) + '</div>';
  h += '<div class="verdict ' + (a.status === 'passed' ? 'good' : (a.status === 'failed_lockbox' ? 'bad' : (a.status === 'ready' ? 'info' : ''))) + '"><b>What happened:</b> ' + esc(a.verdict) + '</div>';
  h += '<div id="chart"></div>';
  h += '<h3>' + (a.lock ? 'Result on the sealed test' : (a.kind === 'rule' ? 'Result on the training period' : 'Result on years it never trained on')) + '</h3>';
  const dn = a.kind === 'nn' ? M.wf_days : M.sel_days;
  h += statCards(a.lock || a.stats, !!a.lock, a.lock ? M.lock_days : dn);
  if (a.lock) h += '<h3>Result before the sealed test</h3>' + statCards(a.stats, false, dn);
  h += '<h3>Where the money went (shares, with slippage and fees)</h3>' + costTable(a);
  h += '<h3>What this strategy does</h3>';
  if (a.lines) h += '<ol class="steps">' + a.lines.map(l => '<li>' + esc(l) + '</li>').join('') + '</ol>';
  else h += '<p class="muted">' + esc(a.label) + '</p><p>A neural network scores every LULD unhalt under several exit styles and predicts the profit after slippage and fees, using only what was known before the unhalt. It only trades when the prediction clears a confidence bar, one position at a time. It is retrained each year using only earlier years.</p>';
  el.innerHTML = h;
  drawChart($('#chart'), a);
  $('#prev').onclick = () => { if (i > 0) select(lst[i - 1].id); };
  $('#next').onclick = () => { if (i < lst.length - 1) select(lst[i + 1].id); };
  $('#pick').onchange = e => select(parseInt(e.target.value, 10));
}

function renderList() {
  const lst = attemptsFiltered();
  $('#list').innerHTML = lst.length ? lst.map(a => '<button class="item' + (a.id === cur ? ' sel' : '') + '" data-id="' + a.id + '"><div class="t"><span>#' + a.id + ' ' + esc(a.title) + '</span><span class="badge bd-' + a.status + '">' + esc(BADGE[a.status]) + '</span></div><div class="m">Round ' + a.round + ' \u00b7 <span class="' + cl(a.stats.total) + '">' + sg(a.stats.total) + '</span> \u00b7 ' + a.stats.n_trades + ' trades \u00b7 score ' + num(a.stats.t, 1) + (a.lock ? ' \u00b7 sealed: <span class="' + cl(a.lock.total) + '">' + sg(a.lock.total) + '</span>' : '') + '</div></button>').join('') : '<div class="empty">No attempts in this view yet.</div>';
  document.querySelectorAll('.item').forEach(b => b.onclick = () => select(parseInt(b.dataset.id, 10)));
}
function select(id) {
  cur = id; try { history.replaceState(null, '', '#a' + id); } catch (e) {}
  renderList(); renderDetail();
  const it = $('.item.sel'); if (it) it.scrollIntoView({block: 'nearest'});
}
function setFilter(f) {
  filter = f; document.querySelectorAll('.chip[data-f]').forEach(b => b.classList.toggle('on', b.dataset.f === f));
  const lst = attemptsFiltered(); if (!lst.find(x => x.id === cur) && lst.length) cur = lst[0].id;
  renderList(); renderDetail();
}

function meter(label, val, thr, hint, ok) {
  const w = thr > 0 ? Math.max(0, Math.min(100, val / thr * 100)) : 0;
  return '<div class="meter"><div class="row"><b>' + label + '</b><span>' + num(val, 1) + ' <span class="muted">of the ' + num(thr, 1) + ' needed</span></span></div>' +
    '<div class="track"><div class="fill' + (ok ? ' ok' : '') + '" style="width:' + w + '%"></div></div><div class="help">' + hint + '</div></div>';
}

function build() {
  const win = D.winner, found = D.status === 'found';
  const stopped = D.status === 'stopped';
  let h = '<header><div><h1>Halt Hunter <span class="muted" style="font-size:16px">' + (M.side === 'long' ? 'long' : 'short') + ' side</span></h1><div class="sub">' + 'Nasdaq LULD halts \u00b7 ' + (M.side === 'long' ? 'buying shares at the unhalt' : 'shorting shares at the unhalt') + ' \u00b7 sealed test: ' + esc(M.lock_date) + ' onward \u00b7 $' + M.budget + ' per trade</div></div>' +
    '<button id="theme" title="Switch between dark and light">&#9681; Dark / light</button></header>';
  if (found) h += '<div class="banner b-good"><div class="h">Edge confirmed</div><p>A strategy made money on months it had never been near, by more than luck can explain. Details are just below. Treat it as something to paper-trade first, not something to fund yet.</p></div>';
  else if (stopped) h += '<div class="banner b-stop"><div class="h">Hunt stopped \u2014 no edge confirmed yet</div><p>' + esc(D.why) + '. Everything is saved: run the .bat again and it carries on from here.</p></div>';
  else h += '<div class="banner b-hunt"><div class="h"><span class="pulse"></span>Hunting for an edge\u2026</div><p>Your computer is trying strategies and training neural networks on every core. Nothing has passed the sealed test yet. This can take hours \u2014 and if the data holds no real edge, it will never find one (that is the correct answer, not a bug). This page refreshes by itself.</p></div>';
  if (found && win) {
    h += '<div class="card"><h2>The strategy that passed</h2><ol class="steps">' + win.lines.map(l => '<li>' + esc(l) + '</li>').join('') + '</ol>';
    h += '<div class="two"><div><h3>Sealed test, year by year</h3>' + yearTable(win.lock_years) + '</div><div><h3>Earlier period, year by year</h3>' + yearTable(win.sel_years) + '</div></div>';
    if (win.importance && win.importance.length) { const mx = Math.max.apply(null, win.importance.map(x => x[1]).concat([1e-9])); h += '<h3>What the network paid attention to</h3>' + win.importance.slice(0, 8).map(x => '<div style="margin:3px 0">' + esc(x[0]) + ' <span style="display:inline-block;height:10px;border-radius:5px;background:var(--accent);vertical-align:middle;width:' + Math.max(3, x[1] / mx * 160) + 'px"></span></div>').join(''); }
    h += '<p class="help">Files saved next to this page: ' + win.files.map(esc).join(', ') + '</p></div>';
  }
  h += '<div class="stats">' +
    '<div class="stat"><div class="k">Time hunting</div><div class="v">' + dur(H.elapsed) + '</div><div class="n">' + H.rounds + ' rounds</div></div>' +
    '<div class="stat"><div class="k">Rule strategies tried</div><div class="v">' + H.n_rules.toLocaleString('en-US') + '</div><div class="n">each also run on scrambled data</div></div>' +
    '<div class="stat"><div class="k">Neural networks tried</div><div class="v">' + H.n_nn + '</div><div class="n">each judged on unseen years</div></div>' +
    '<div class="stat"><div class="k">Sealed-test looks used</div><div class="v">' + H.looks + '</div><div class="n">next one needs p \u2264 ' + num(H.next_alpha, 4) + '</div></div></div>';
  h += '<div class="card"><h2>How close is it?</h2><div class="help">A strategy only gets a look at the sealed months once its score clears the bar. The bar rises as more things are tried, because the more you try, the more things look good by pure luck.</div>' +
    meter('Rule search \u2014 best score so far', H.best_rule, H.rule_thr, 'Bar = what the same search reaches on scrambled, unpredictable data (' + num(H.null_best, 1) + ') plus a safety margin.', H.best_rule >= H.rule_thr && H.rule_thr > 0) +
    meter('Neural networks \u2014 best score so far', H.best_nn, H.nn_thr, 'Scored only on years the network never trained on. The bar goes up with every network tried.', H.best_nn >= H.nn_thr) + '</div>';
  h += '<div class="card" id="explorer"><h2>Every attempt, with its graph</h2><div class="help">Click any attempt (or use the arrows / dropdown) to switch the graph. The line is cumulative profit after option decay, spread and fees. ' + (D.n_attempts > D.attempts.length ? 'Showing the ' + D.attempts.length + ' most relevant of ' + D.n_attempts + '.' : '') + '</div>' +
    '<div class="chips"><button class="chip on" data-f="all">All</button><button class="chip" data-f="lock">Reached the sealed test</button><button class="chip" data-f="nn">Neural networks</button><button class="chip" data-f="rule">Rule strategies</button>' +
    '<span style="flex:1"></span><label class="muted" style="font-size:14px">Sort <select id="sort"><option value="new">Newest first</option><option value="score">Best score</option><option value="profit">Biggest profit</option></select></label></div>' +
    '<div class="grid"><div class="list" id="list"></div><div id="detail"></div></div></div>';
  if (D.ledger.length) {
    h += '<div class="card"><h2>Sealed-test log</h2><div class="help">Every look at the sealed months is recorded here. Look number k must reach p \u2264 ' + M.alpha + ' \u00d7 6 / (\u03c0\u00b2k\u00b2), so the total chance of ever being fooled by luck, however long this runs, stays under ' + Math.round(M.alpha * 100) + '%.</div><div class="tw"><table><tr><th>#</th><th class="l">Strategy</th><th>Days</th><th>Profit</th><th>Score</th><th>p-value</th><th>Needed</th><th>At 1.5x costs</th><th>Result</th></tr>' +
      D.ledger.map(e => '<tr class="click" data-id="' + (e.attempt || '') + '"><td>' + e.k + '</td><td class="l">' + esc(e.kind === 'nn' ? 'Neural network' : 'Rule') + ': ' + esc(e.label) + '</td><td>' + e.n_days + '</td><td class="' + cl(e.total) + '">' + sg(e.total) + '</td><td>' + num(e.t, 2) + '</td><td>' + num(e.p, 5) + '</td><td>' + num(e.alpha_k, 5) + '</td><td class="' + cl(e.stress_total) + '">' + sg(e.stress_total) + '</td><td><span class="badge ' + (e.passed ? 'bd-passed' : 'bd-failed_lockbox') + '">' + (e.passed ? 'CONFIRMED' : 'failed') + '</span></td></tr>').join('') + '</table></div></div>';
  }
  h += '<div class="card"><h2>How this works, in plain English</h2>' +
    '<details open><summary>What is it doing?</summary><p>It looks at every <b>LULD halt</b> on Nasdaq (the automatic 5-minute pause when a stock moves too far too fast) and tests, on years of past minute-by-minute prices, whether ' + (M.side === 'long' ? '<b>buying shares the moment trading resumes</b>' : '<b>shorting shares the moment trading resumes</b>') + ' has an edge. Two searchers run side by side on every CPU core: a <b>rule search</b> (combinations like "after an UP halt on a $2\u2013$5 stock with a volume surge, buy and sell 5 minutes later") and <b>neural networks</b> that learn which halts tend to pay off and how to exit. It repeats until something passes the sealed test, or you stop it. Long and short are separate hunts with separate results.</p></details>' +
    '<details><summary>What is the sealed test?</summary><p>The newest ' + M.lock_months + ' months of data (' + esc(M.lock_date) + ' onward, ' + M.lock_days + ' trading days) are locked away. The search never sees them. A strategy is only shown them after it clears every other test, and each look uses up part of an error budget, so luck cannot slip through just by trying again and again. If it passes, the result is strong evidence \u2014 not a guarantee.</p></details>' +
    '<details><summary>How are the trades and costs handled?</summary><p>Every trade is in <b>shares</b>, sized to $' + M.budget + ', ' + (M.side === 'long' ? 'bought' : 'sold short') + ' at the first print after the halt ends (or a few minutes later if the strategy waits), and closed by its take-profit, stop, time limit or the close. Halted stocks reopen with wide, jumpy prices, so every fill is charged <b>slippage</b>: at least ' + M.slip_bps + ' basis points each way, or ' + Math.round(M.slip_rng * 100) + '% of that minute\u2019s own high-low range if that is bigger, plus <b>$' + M.fee_share + ' per share</b> in fees each way. If a stop is gapped through, the fill is the worse price. The "Where the money went" table on each attempt shows exactly how much slippage and fees cost. Prices come from Nasdaq-venue 1-minute bars, not real quotes.</p></details>' +
    '<details><summary>What do "score" and "p-value" mean?</summary><p><b>Score</b> measures how steady the profit is compared with its ups and downs. Around 0 means no better than a coin flip; 2 would be convincing if you only tried one strategy; but since thousands are tried, the bar is higher (see the meters). <b>p-value</b> is the chance of seeing a result this good by pure luck. Smaller is better.</p></details>' +
    '<details><summary>What if it never finds anything?</summary><p>Then there probably is no tradable edge in this data after realistic option costs \u2014 which is the usual outcome. The page keeps showing the best attempts so you can see how close they got. You can stop at any time (Ctrl+C in the black window, or create a file named STOP_HALTS.txt next to the .bat) and resume later.</p></details>' +
    '<details><summary>Important caveats</summary><ul class="plain"><li>Real fills at a reopening are usually worse than this model, and some halted stocks cannot be traded in the first seconds at all.</li><li>Halts are rare per stock, so the number of trades is modest; only a sizeable edge can be confirmed in ' + M.lock_months + ' sealed months.</li><li>Shorting needs shares to borrow; borrow fees and short-sale restrictions are not modelled.</li><li>A pass is evidence about the past ' + M.lock_months + ' months. Paper-trade before using real money.</li></ul></details></div>';
  h += '<footer>Updated ' + esc(D.generated) + (D.status === 'hunting' ? ' \u00b7 this page reloads itself every 45 seconds while the hunt runs' : '') + '</footer>';
  $('#app').innerHTML = h;
  $('#theme').onclick = () => { const t = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark'; document.documentElement.setAttribute('data-theme', t); try { localStorage.setItem('eh-theme', t); } catch (e) {} };
  document.querySelectorAll('.chip[data-f]').forEach(b => b.onclick = () => setFilter(b.dataset.f));
  $('#sort').onchange = e => { sort = e.target.value; renderList(); };
  document.querySelectorAll('tr.click').forEach(r => r.onclick = () => { const id = parseInt(r.dataset.id, 10); if (id && byId(id)) { setFilter('all'); select(id); $('#explorer').scrollIntoView({behavior: 'smooth'}); } });
}
function yearTable(rows) {
  if (!rows || !rows.length) return '<p class="muted">No trades.</p>';
  return '<div class="tw"><table><tr><th>Year</th><th>Trades</th><th>Win %</th><th>Avg / trade</th><th>Profit</th></tr>' + rows.map((r, i) => '<tr' + (r[0] === 'ALL' ? ' class="tot"' : '') + '><td>' + r[0] + '</td><td>' + r[1] + '</td><td>' + num(r[2], 0) + '%</td><td class="' + cl(r[3]) + '">' + sg(r[3]) + '</td><td class="' + cl(r[4]) + '">' + sg(r[4]) + '</td></tr>').join('') + '</table></div>';
}

build();
const hh = (location.hash.match(/^#a(\d+)$/) || [])[1];
const lockLast = D.attempts.filter(a => a.lock).sort((x, y) => y.id - x.id)[0];
cur = (hh && byId(parseInt(hh, 10))) ? parseInt(hh, 10) : (D.winner && D.winner.attempt && byId(D.winner.attempt) ? D.winner.attempt : (lockLast ? lockLast.id : (D.attempts.length ? D.attempts[D.attempts.length - 1].id : null)));
renderList(); renderDetail();
try { const y = sessionStorage.getItem('eh-scroll'); if (y) { window.scrollTo(0, parseInt(y, 10)); sessionStorage.removeItem('eh-scroll'); } } catch (e) {}
if (D.status === 'hunting') setTimeout(() => { try { sessionStorage.setItem('eh-scroll', window.scrollY); } catch (e) {} location.reload(); }, 45000);
</script></body></html>
'''


def write_dashboard(path, payload):
    """The whole UI is one self-contained page (no internet needed); written atomically so a browser refresh never
    catches it half-written."""
    data = json.dumps(payload, default=jsonable, separators=(",", ":")).replace("</", "<\\/")
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(DASH_HTML.replace("__DATA__", data), encoding="utf-8")
    os.replace(tmp, path)





# ============================ SYNTHETIC SELF-TEST ===========================
def make_synthetic(args):
    """Synthetic LULD halts in the exact cache format the real loader reads. Each halt follows a sharp run, pauses for
    5-15 minutes, then reopens. With selftest 'edge' the price keeps going the way it was going (up-halts keep rising,
    down-halts keep falling) for 10 minutes after the unhalt, so BOTH the long and the short hunt have a real edge to
    find; 'null' plants nothing."""
    rng = np.random.default_rng(777)
    edge = args.selftest_edge if args.selftest == "edge" else 0.0           # % per minute for 10 minutes
    days = pd.bdate_range(f"{args.first_year}-01-01", pd.Timestamp(args.end) - pd.Timedelta(days=1))
    symbols = [f"T{i:03d}" for i in range(300)]
    by_day = {}
    for day in days:
        d0 = pd.Timestamp(f"{day:%Y-%m-%d} 09:30", tz=TZ)
        prev_ts = (pd.Timestamp(f"{day:%Y-%m-%d} 15:59", tz=TZ) - pd.offsets.BDay(1))
        bars, used = {}, set()
        for _ in range(rng.poisson(3.2)):
            s = symbols[int(rng.integers(len(symbols)))]
            if s in used:
                continue
            used.add(s)
            th = int(rng.integers(12, 330))
            dur = 5 if rng.random() < 0.8 else int(rng.choice([10, 15]))
            dirn = 1 if rng.random() < 0.55 else -1
            p0 = float(np.clip(np.exp(rng.normal(np.log(4.0), 0.8)), 0.8, 80))
            ret = rng.normal(0, 0.0035, 390)
            ret[max(th - 8, 0):th] += dirn * 0.013
            ret[th + dur:th + dur + 10] += dirn * edge / 100.0
            path = p0 * np.exp(np.cumsum(ret))
            prev_close = p0 * float(np.exp(rng.normal(0, 0.03)))
            m = np.arange(390)
            live = ~((m >= th) & (m < th + dur))
            o = np.r_[p0, path[:-1]]
            hi = np.maximum(o, path) * (1 + np.abs(rng.normal(0, 0.002, 390)))
            lo = np.minimum(o, path) * (1 - np.abs(rng.normal(0, 0.002, 390)))
            vol = np.maximum(1, np.exp(rng.normal(8.0, 0.8, 390)) * np.where((m >= th - 8) & (m < th), 6, 1)).round()
            idx = pd.DatetimeIndex([d0 + pd.Timedelta(minutes=int(k)) for k in m[live]])
            df = pd.DataFrame(dict(open=o[live], high=hi[live], low=lo[live], close=path[live], volume=vol[live]), index=idx)
            prev = pd.DataFrame(dict(open=[prev_close], high=[prev_close], low=[prev_close], close=[prev_close], volume=[100.0]),
                                index=pd.DatetimeIndex([prev_ts]))
            bars[s] = pd.concat([prev, df])
            by_day.setdefault(f"{day:%Y-%m-%d}", []).append((s, d0 + pd.Timedelta(minutes=th), d0 + pd.Timedelta(minutes=th + dur)))
        bf = bars_cache(f"{day:%Y-%m-%d}", args.dataset)
        bf.parent.mkdir(parents=True, exist_ok=True)
        pd.to_pickle(bars, bf)
    for day in days:
        rows = by_day.get(f"{day:%Y-%m-%d}", [])
        h = pd.DataFrame(rows, columns=["sym", "halt_ts", "resume_ts"])
        f = status_cache(f"{day:%Y-%m-%d}", args.dataset)
        f.parent.mkdir(parents=True, exist_ok=True)
        pd.to_pickle((h, {"action=9 reason=50": len(h)}), f)


def setup_selftest(args):
    d = Path(f"halt_selftest_{args.selftest}")
    d.mkdir(exist_ok=True)
    os.chdir(d)
    log(f"SELF-TEST ({args.selftest.upper()}, {args.side}): synthetic halts in {d.resolve()}  "
        + ("(continuation after the unhalt is planted - the hunter SHOULD find it)" if args.selftest == "edge"
           else "(pure noise - the hunter must NOT confirm anything)"))
    Path("data_cache").mkdir(exist_ok=True)
    if not all(status_cache(d_, args.dataset).exists() for d_ in halt_days(args)):
        log("  generating synthetic halts and 1-minute bars ...")
        make_synthetic(args)


def year_rows(date, pnl):
    date, pnl = np.asarray(date), np.asarray(pnl, float)
    rows = []
    if not len(pnl):
        return rows
    yr = date // 10000
    for y in sorted(set(yr.tolist())):
        p = pnl[yr == y]
        rows.append([str(y), int(len(p)), float((p > 0).mean() * 100), float(p.mean()), float(p.sum())])
    rows.append(["ALL", int(len(pnl)), float((pnl > 0).mean() * 100), float(pnl.mean()), float(pnl.sum())])
    return rows


def finalize(H, found, args, syms, why):
    """Write the final dashboard (and, if an edge was confirmed, the strategy files)."""
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    winner = None
    if found:
        entry, lock, model = found
        cfg, kind = entry["cfg"], entry["kind"]
        ev_sel = load_events(H.dir, "sel", mmap=False)
        ticks = json.loads((H.dir / "tickers.json").read_text())
        files = ["edge_strategy.json", "edge_lockbox_trades.csv", "edge_selection_trades.csv"]
        if kind == "rule":
            idx, side, res = run_cfg(ev_sel, cfg, args)
            sel = dict(date=ev_sel.date[idx], pnl=res["pnl"], tid=ev_sel.tid[idx])
            lines, importance = describe(cfg, args), None
        else:
            seed = next(s["seed"] for s in H.state["nn_hist"] if nn_dist(s["cfg"], cfg) == 0)
            sres = H.call(dict(kind="nn", cfg=cfg, seed=seed, folds=H.folds), stoppable=False)
            sel = dict(date=sres["date"], pnl=sres["pnl"], tid=sres["tid"])
            lines, importance = describe_nn(cfg), lock.get("importance")
            if model:
                np.savez(out / "edge_nn_model.npz", mu=model["mu"], sd=model["sd"], sel=model["sel"],
                         margin=-1 if model["margin"] is None else model["margin"],
                         **{f"net{i}_W{l}": w for i, ws in enumerate(model["W"]) for l, w in enumerate(ws)},
                         **{f"net{i}_b{l}": b for i, bs in enumerate(model["b"]) for l, b in enumerate(bs)})
                files.append("edge_nn_model.npz")
        (out / "edge_strategy.json").write_text(json.dumps(dict(kind=kind, side=args.side, config=cfg, sealed_test=entry), indent=2, default=jsonable))
        tn = lambda t: [ticks[int(i)] for i in t]
        pd.DataFrame(dict(date=lock["date"], ticker=tn(lock["tid"]), pnl=np.round(lock["pnl"], 2),
                          pnl_if_costs_1_5x=np.round(lock["pnl_s"], 2))).to_csv(out / "edge_lockbox_trades.csv", index=False)
        pd.DataFrame(dict(date=sel["date"], ticker=tn(sel["tid"]), pnl=np.round(sel["pnl"], 2))).to_csv(out / "edge_selection_trades.csv", index=False)
        winner = dict(attempt=entry.get("attempt"), kind=kind, lines=lines, importance=importance, files=files,
                      lock_years=year_rows(lock["date"], lock["pnl"]), sel_years=year_rows(sel["date"], sel["pnl"]))
    H.progress(None, "found" if found else "stopped", why)
    write_dashboard(out / "report.html", H.payload("found" if found else "stopped", why, winner))
    return out / "report.html"


# ================================== MAIN ====================================
def parse_args(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--side", choices=["long", "short"], default="long", help="long = buy at the unhalt, short = sell short at the unhalt")
    p.add_argument("--first-year", type=int, default=2021)
    p.add_argument("--end", default="2026-10-01")
    p.add_argument("--first-test-year", type=int, default=2023)
    p.add_argument("--dataset", default="XNAS.ITCH")
    p.add_argument("--lockbox-months", type=int, default=12)
    p.add_argument("--alpha", type=float, default=0.05)
    p.add_argument("--workers", type=int, default=0)
    p.add_argument("--mem-gb", type=float, default=14.0)
    p.add_argument("--max-hours", type=float, default=0.0)
    p.add_argument("--max-rounds", type=int, default=0)
    p.add_argument("--rule-batch", type=int, default=1000)
    p.add_argument("--rule-tasks", type=int, default=0)
    p.add_argument("--nn-tasks", type=int, default=0)
    p.add_argument("--nulls", type=int, default=2)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--min-days-year", type=int, default=30, help="a strategy must trade on at least this many days a year")
    p.add_argument("--min-trade-frac", type=float, default=0.0)
    p.add_argument("--pos-blocks", type=float, default=0.6)
    p.add_argument("--rule-tmin", type=float, default=3.0)
    p.add_argument("--null-margin", type=float, default=0.4)
    p.add_argument("--nbr-frac", type=float, default=0.6)
    p.add_argument("--nn-tmin", type=float, default=2.2)
    p.add_argument("--nn-min-days", type=int, default=60)
    p.add_argument("--min-lock-days", type=int, default=40)
    p.add_argument("--stress", type=float, default=1.5)
    p.add_argument("--min-power", type=float, default=0.3)
    p.add_argument("--shrink-rule", type=float, default=0.5)
    p.add_argument("--shrink-nn", type=float, default=0.8)
    p.add_argument("--budget", type=float, default=1000)
    p.add_argument("--slip-bps", type=float, default=40.0, help="slippage per side, basis points of price (minimum)")
    p.add_argument("--slip-rng", type=float, default=0.15, help="slippage per side as a share of the 1-minute bar's own range")
    p.add_argument("--fee-share", type=float, default=0.004, help="fees, $ per share per side")
    p.add_argument("--min-price", type=float, default=0.5)
    p.add_argument("--max-price", type=float, default=200.0)
    p.add_argument("--max-cost", type=float, default=0.0, help="stop before spending more than this on Databento, US dollars (0 = no limit; cached data is free)")
    p.add_argument("--yes", action="store_true", help="skip the 15-second 'this will cost about $X' pause")
    p.add_argument("--estimate", action="store_true", help="only print what the Databento downloads would cost, then exit")
    p.add_argument("--no-browser", action="store_true")
    p.add_argument("--selftest", choices=["null", "edge"], default=None)
    p.add_argument("--selftest-edge", type=float, default=0.2)
    p.add_argument("--fresh", action="store_true", help="ignore saved hunt state and start over")
    p.add_argument("--out", default=None)
    a = p.parse_args(argv)
    a.side_val = 1 if a.side == "long" else -1
    a.out = a.out or f"halt_results_{a.side}"
    return a


def md5s(*parts):
    return hashlib.md5(repr(parts).encode()).hexdigest()[:12]


def check_config(args):
    """Refuse bad year settings BEFORE any download is paid for."""
    lock_start = pd.Timestamp(args.end) - pd.DateOffset(months=args.lockbox_months)
    last_sel_year = lock_start.year if (lock_start.month, lock_start.day) != (1, 1) else lock_start.year - 1
    test_years = [y for y in range(args.first_year, last_sel_year + 1) if y >= args.first_test_year]
    if not test_years or test_years[0] - args.first_year < 1:
        have = (f"only {args.first_year} to {last_sel_year}" if args.first_year <= last_sel_year else "nothing at all")
        sys.exit(f"ERROR: these year settings cannot work (nothing was downloaded or spent). The newest {args.lockbox_months} months "
                 f"(from {lock_start:%Y-%m-%d}) are sealed, so the search and the neural net get {have}.\n"
                 f"       The neural net needs at least 1 year of halts BEFORE its first test year ({args.first_test_year}). "
                 f"Set FIRST_YEAR at least one year before FIRST_TEST_YEAR, and FIRST_TEST_YEAR no later than {last_sel_year}.")


def prepare_events(args):
    keys = ("first_year", "end", "dataset", "lockbox_months", "min_price", "max_price", "selftest", "selftest_edge")
    ev_dir = Path("halt_events") / f"ev_{md5s(EV_VERSION, *[getattr(args, k) for k in keys])}"
    if (ev_dir / "meta.json").exists():
        if args.estimate:
            log("Everything is already downloaded and built, so there is nothing to estimate or spend.")
            sys.exit(EXIT_INFO)
        log("[1/3] Halt events loaded from cache.")
        return json.loads((ev_dir / "meta.json").read_text()), ev_dir
    check_config(args)
    log("[1/3] Finding LULD halts and building events (first run only - cached afterwards) ...")
    halts = load_halts(args)
    load_all_bars(halts, args)
    d, ticks = build_halt_events(halts, args)
    lock_start = int((pd.Timestamp(args.end) - pd.DateOffset(months=args.lockbox_months)).strftime("%Y%m%d"))
    sel = d["date"] < lock_start
    if sel.sum() == 0 or (~sel).sum() == 0:
        sys.exit("ERROR: the sealed lockbox or the selection set is empty - check FIRST_YEAR / END / LOCKBOX_MONTHS.")
    years = np.unique(d["date"][sel] // 10000)
    test_years = [int(y) for y in years if y >= args.first_test_year]
    if not test_years or test_years[0] - int(years[0]) < 1:
        sys.exit("ERROR: the neural net needs at least 1 year of halts before the first test year. "
                 "Lower FIRST_YEAR or raise FIRST_TEST_YEAR.")
    if test_years[0] - int(years[0]) < 2:
        log(f"  (only {test_years[0] - int(years[0])} year of halts before the first test year: the neural net will be weaker; "
            f"a lower FIRST_YEAR gives it more to learn from)")
    ev_dir.mkdir(parents=True, exist_ok=True)
    save_events(ev_dir, "sel", take_events(d, sel))
    save_events(ev_dir, "lock", take_events(d, ~sel))
    (ev_dir / "tickers.json").write_text(json.dumps(ticks))
    meta = dict(lock_start=lock_start, test_years=test_years, n_sel=int(sel.sum()), n_lock=int((~sel).sum()))
    (ev_dir / "meta.json").write_text(json.dumps(meta))
    log(f"  {meta['n_sel']:,} halts in the selection set, {meta['n_lock']:,} sealed in the lockbox")
    return meta, ev_dir


def pick_workers(args, meta):
    w = args.workers or (os.cpu_count() or 4)
    per_mb = meta["n_sel"] * LEN_PATH * 4 * 4 * (1 + args.nulls) / 1e6 * 1.5 + 400
    cap = max(1, int(args.mem_gb * 1000 / per_mb))
    if w > cap:
        log(f"  (memory budget {args.mem_gb:.0f} GB allows {cap} workers; using {cap})")
        w = cap
    return w


def main():
    args = parse_args()
    if args.selftest:
        setup_selftest(args)
    try:
        Path("STOP_HALTS.txt").unlink()
    except OSError:
        pass
    syms = ["Nasdaq LULD halts"]
    meta, ev_dir = prepare_events(args)
    W = pick_workers(args, meta)
    sig = md5s(EV_VERSION, args.side, args.first_year, args.end, args.dataset, args.lockbox_months, args.min_price,
               args.max_price, args.budget, args.slip_bps, args.slip_rng, args.fee_share, args.nulls,
               args.min_days_year, args.pos_blocks, args.selftest, args.selftest_edge, args.first_test_year)
    log(f"[2/3] Starting {W} worker processes (one per core, below-normal priority so Windows stays usable) ...")
    keep_awake()
    pool = mp.get_context("spawn").Pool(W, initializer=_init_worker, initargs=(str(ev_dir), dict(vars(args))))
    H = Hunt(args, meta, ev_dir, Path("halt_state") / sig, pool, W, syms)
    log(f"[3/3] Hunting ({args.side.upper()} side). Each round: rule search (with scrambled-data luck benchmark) + neural-net variants.")
    code, found, why = EXIT_STOP, None, ""
    try:
        found = H.run()
        code = EXIT_OK
    except StopHunt as e:
        why = str(e)
        log(f"\nHunt stopped: {why}")
    except KeyboardInterrupt:
        why = "stopped by you (Ctrl+C)"
        log(f"\nHunt {why}")
    try:
        H.save()
        rpt = finalize(H, found, args, syms, why or "stopped")
        log(f"\nDashboard: {rpt.resolve()}")
    except Exception:
        log("(could not write the report)\n" + traceback.format_exc())
    finally:
        pool.terminate()
    if found:
        e = found[0]
        log("\n" + "=" * 78)
        log(f"  *** EDGE CONFIRMED ON THE SEALED LOCKBOX ({args.side.upper()}) ***")
        log("=" * 78)
        log(f"  {e['label']}")
        log(f"  lockbox: {e['n_trades']} trades / {e['n_days']} days, {money(e['total'], True)}, t={e['t']:.2f}, "
            f"p={e['p']:.5f} (needed {e['alpha_k']:.5f}), at 1.5x costs {money(e['stress_total'], True)}")
        print("\a", end="", flush=True)
    return code


if __name__ == "__main__":
    mp.freeze_support()
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except KeyboardInterrupt:
        sys.exit(EXIT_STOP)
    except Exception:
        traceback.print_exc()
        sys.exit(EXIT_CRASH)
