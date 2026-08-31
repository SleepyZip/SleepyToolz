# Browser Activity Report — Setup & Troubleshooting

This turns collected Chrome/Edge history databases into a formatted Excel
report, one workbook per user. This file covers the whole workflow: pulling the
history off the PCs with the Datto RMM job, getting Python running, and fixing
the problems you're most likely to hit.

The workflow has three stages:

```
1. Collect   Datto RMM job copies each user's history to the PC (local LocalCollector profile)
2. Gather    You pull those files from the PCs to one folder on your workstation
3. Report    The Python app turns them into Excel workbooks
```

If you just want to hand the report tool to someone with no setup, skip to the
bottom ("Give it to someone with no Python") and build the standalone .exe.

---

## What's in the folder

Keep these together in one folder:

```
Collect-BrowserHistory.ps1  Datto RMM component (runs on the PCs)
Gather-BrowserHistory.ps1   pulls captures from PCs to your workstation
browser_report_gui.py       the report app (run this)
browser_report_gui.pyw      same app, double-click version (no console)
chrome_activity_report.py   the engine (required, don't rename)
Build-Exe.bat               builds the standalone .exe
```

The GUI will not start without `chrome_activity_report.py` sitting next to it.

---

## Stage 1: Collect the history with Datto RMM

This assumes the "Collect Browser History" component and job are already set up
in Datto (see RUNBOOK.md sections 6–8 if not).

1. In Datto RMM, run the **Collect Browser History** job against the PCs the
   person may have used. Use a Quick Job for one machine, or the device group
   for several.
2. When the job prompts for variables, type the target in **usrTargetUsers**:

   ```
   first.last
   ```

   Leave it blank to collect every profile on the machine instead of one user.
3. Watch the **Result** column. Success looks like:

   ```
   Copied 2, skipped 0, failed 0
   ```

   If a machine didn't have that user, it tells you:

   ```
   Copied 0, failed 0. NOT FOUND: first.last
   ```

The files land on each PC at `C:\Users\LocalCollector\Documents\BrowserData`.

## Stage 2: Gather the files to your workstation

Run this from your own PC, in PowerShell (not Datto). It pulls the captures off
each machine into one folder, ready for the report.

```
.\Gather-BrowserHistory.ps1 -Computers PC01,PC02 -Destination "C:\Reports\Captures"
```

List whichever PCs you ran the job against. Add `-Cleanup` to delete the copy
left on each PC once it's been pulled (recommended — these are full history
files sitting in a local profile).

```
--- PC01
    ok    ChromeHistory_first.lastPC01  (28.4 MB)
--- PC02
    offline

Pulled 1 file(s) to C:\Reports\Captures
```

You now have a folder of capture files. The rest of this README turns them into
a report.

---

## Install Python (one time)

Two ways — pick one.

**Option A: winget (fastest, if you have it).** Windows 10/11 include winget.
Open Command Prompt and run:

```
winget install Python.Python.3.12
```

Close and reopen Command Prompt afterward so it picks up the new PATH. winget
adds Python to PATH automatically, so you skip the checkbox gotcha below.

**Option B: manual installer.**

1. Go to https://www.python.org/downloads/
2. Download the latest Windows installer.
3. Run it. On the very first screen, **check the box that says
   "Add python.exe to PATH"** before clicking Install. This is the step people
   miss, and skipping it causes most of the "python is not recognized" errors
   below.
4. Finish the install.

Confirm it worked. Open Command Prompt (press Start, type `cmd`, Enter) and run:

```
python --version
```

You should see something like `Python 3.12.10`. If you get an error, see
"'python' is not recognized" below.

---

## Install the dependencies (one time)

pip comes bundled with Python, so once Python is installed you already have it.
In Command Prompt:

```
pip install openpyxl tzdata
```

`openpyxl` writes the Excel files. `tzdata` gives Python the timezone database
so timestamps show in local time instead of UTC. Both are required.

If `pip` isn't recognized, call it through Python instead (this always works):

```
py -m pip install openpyxl tzdata
```

Optional, only if you want drag-and-drop into the app:

```
pip install tkinterdnd2
```

Without it the app still works — you use the Add Files / Add Folder buttons.

To confirm the dependencies installed:

```
pip show openpyxl
```

If it prints a version and location, you're set. "WARNING: Package(s) not
found" means it didn't install — re-run the install command above.

---

## Run it

Two ways:

**Double-click** `browser_report_gui.pyw` — no console window appears.

**From a terminal** (do this if it won't open, because errors stay on screen):

```
cd C:\path\to\the\folder
python browser_report_gui.py
```

Then: add the capture files you gathered in Stage 2 (Add Folder → point it at
`C:\Reports\Captures`), check the parsed User/Workstation (double-click a cell
to fix), set an optional date range, pick an output folder, Generate Report.

---

## Troubleshooting

### Datto job Result says "NO LOCAL ACCOUNT 'LocalCollector'"

That PC doesn't have a local account named LocalCollector. Check the account name and
set the `usrLocalAccount` variable to match, or fix the account on the machine.

### Datto job says "NOT FOUND: <user>"

That user has no profile on that particular PC — they never signed in there.
This is normal on shared machines. Run the job against the other PCs the person
may have used; the one they actually used will collect their history.

### Gather script says "offline" or "admin share"

- **offline** — the PC didn't answer a ping. It's off, asleep, or not on the
  network. Try again when it's up.
- **admin share** — your account can't reach `\\PC\C$`. You need local admin on
  that machine, and File and Printer Sharing has to be allowed through its
  firewall.

### Gather pulled nothing ("no captures")

The Datto collect job hasn't run on that PC yet, or it collected a different
user. Re-run Stage 1 against that machine first.

### "python is not recognized as an internal or external command"

Python isn't on PATH. Either:

- Reinstall Python and tick **"Add python.exe to PATH"** on the first screen, or
- Try `py` instead of `python` everywhere (`py --version`, `py browser_report_gui.py`).

`py` is the Windows Python launcher and often works even when `python` doesn't.

### Typing `python` opens the Microsoft Store

Windows ships a fake `python` that redirects to the Store. Fix it:

- Settings → Apps → Advanced app settings → App execution aliases
- Turn **off** the two entries named "python.exe" and "python3.exe"

Or just use `py` instead.

### The window flashes and closes immediately

Something crashed at startup. Two things:

1. Check `Documents\BrowserReport_error.log` — the app writes the reason there.
2. Run it from a terminal (`python browser_report_gui.py`) so the error stays
   visible.

Most common cause is `chrome_activity_report.py` not being in the same folder.

### "ModuleNotFoundError: No module named 'chrome_activity_report'"

The engine file isn't next to the app. Put `browser_report_gui.py` and
`chrome_activity_report.py` in the same folder.

### "ModuleNotFoundError: No module named 'openpyxl'"

Dependencies aren't installed. Run `pip install openpyxl tzdata`. If pip itself
isn't recognized, use `py -m pip install openpyxl tzdata`.

### All the times are wrong (off by several hours)

`tzdata` is missing. Run `pip install tzdata` and regenerate the report.

### "Permission denied" when generating a report

The output file is open in Excel. Close the workbook and run it again — Excel
locks the file and blocks the overwrite.

### A user's report is missing recent activity

Chrome keeps roughly 90 days of history. Anything older than that is gone from
the source database and can't be recovered here.

### It shows two date ranges for one person with a gap between

That user has capture files from different points in time (for example an older
profile plus a current one). It's not a bug — filter the Date column in the
workbook to the range you care about.

### A whole category looks wrong or "Uncategorized" is huge

The category rules don't match this site mix yet. Open the **Uncategorized
Domains** sheet in the output, add the high-count domains to `CATEGORY_RULES`
near the top of `chrome_activity_report.py`, and run it again. Expect a couple
of passes to tune it.

---

## Give it to someone with no Python

Build a standalone .exe once, hand out one file, and the receiving machine needs
nothing installed.

1. On a Windows PC that has Python, put these three in one folder:
   `browser_report_gui.py`, `chrome_activity_report.py`, `Build-Exe.bat`
2. Double-click `Build-Exe.bat`.
3. When it finishes, your program is `dist\BrowserActivityReport.exe`.

Copy that single .exe anywhere. No Python, no pip, no dependencies.

If the build fails with "Unable to find chrome_activity_report.py", the three
files aren't in the same folder — move them together and run it again.

The category rules are baked into the .exe at build time, so rebuild after
editing `CATEGORY_RULES`.
