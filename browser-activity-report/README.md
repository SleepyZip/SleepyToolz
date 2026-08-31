# Browser Activity Report

Turn collected Chrome/Edge history databases into a clean, categorized Excel
report — one workbook per user. Built for IT teams who occasionally need to
review workstation browsing activity as part of an authorized investigation.

It reads the SQLite `History` files that Chrome and Edge keep on disk, sorts
each visit into categories (work tools, job searching, social media, shopping,
and so on), flags the ones worth a closer look, and writes a formatted
spreadsheet with a summary, per-visit detail, downloads, and source-file
hashes.

There's a drag-and-drop desktop GUI, a command-line version, and optional
PowerShell scripts for collecting the history at scale via an RMM.

## Please read first: appropriate use

This tool processes personal browsing history and can surface sensitive
information. Use it only where you have a legitimate basis and proper
authorization to do so.

- Confirm your authority to collect and review the data (employer policy,
  written approval, applicable law). Rules vary by jurisdiction.
- The output can contain personal and, depending on the environment,
  regulated data. People sometimes paste sensitive text into search boxes,
  which lands in the report. Treat every output file as confidential: store it
  access-controlled, not on a general share, and set a retention period.
- Collect the minimum needed. The collector supports targeting specific users
  rather than sweeping every profile.

You are responsible for how you use this. See `LICENSE` (no warranty).

## How it works

```
1. Collect   RMM job copies each user's History file locally on the PC        (optional, PowerShell)
2. Gather    Pull those files to one folder on your workstation               (optional, PowerShell)
3. Report    Turn the gathered files into Excel workbooks                     (the app)
```

Stages 1 and 2 are only needed for collecting from many machines. If you
already have the `History` files, go straight to stage 3.

## Quick start (report only)

```
winget install Python.Python.3.12
py -m pip install openpyxl tzdata tkinterdnd2
python browser_report_gui.py
```

Drop your `History` files into the window, pick an output folder, click
Generate Report. Full setup and troubleshooting is in **USAGE.md**.

Command-line equivalent:

```
python chrome_activity_report.py -i "C:\path\to\history\files" --outdir out
```

## What's in this repo

```
browser_report_gui.py        Drag-and-drop desktop app (run this)
browser_report_gui.pyw       Same app, double-click launch with no console
chrome_activity_report.py    The engine: parsing, categorizing, Excel output
Build-Exe.bat                Builds a standalone .exe (no Python needed to run)
make_test_data.py            Generates fake History files so you can try it safely

Collect-BrowserHistory.ps1   RMM component: copy History files locally on a PC
Gather-BrowserHistory.ps1    Pull collected files from PCs to your workstation

USAGE.md                     Install, run, and troubleshooting guide
RUNBOOK.md                   Detailed reference incl. RMM setup
```

## Try it without real data

```
python make_test_data.py
python chrome_activity_report.py -i sample --outdir demo_out
```

This builds a `sample/` folder of synthetic History databases for fictional
users and produces example workbooks — a safe way to see the output.

## Customizing the categories

Category assignment is driven by a rule table (`CATEGORY_RULES`) near the top
of `chrome_activity_report.py`. It ships with common public domains plus
clearly marked `CUSTOMIZE` placeholders for your own systems (intranet,
line-of-business apps, vendor portals). After a run, open the **Uncategorized
Domains** sheet to see what had no rule, add those domains, and re-run. First
match wins, so order matters.

## Requirements

- Python 3.9+ (3.12 recommended)
- `openpyxl` and `tzdata` (required); `tkinterdnd2` (optional, drag-and-drop)
- Windows for the PowerShell collection scripts; the report tool itself runs
  anywhere Python does.

## License

MIT — see `LICENSE`. Provided as-is, with no warranty.
