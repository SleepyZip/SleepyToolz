# Browser Activity Reporting — Windows Runbook

## 1. Install (once)

```
winget install Python.Python.3.12
pip install openpyxl tzdata
```

```
Successfully installed et-xmlfile-2.0.0 openpyxl-3.1.5 tzdata-2026.1
```

Verify:

```
python --version
```

```
Python 3.12.10
```

---

## 2. Options

```
python chrome_activity_report.py --help
```

```
usage: chrome_activity_report.py [-h] [-i INPUT] [-o OUTDIR] [--start START]
                                 [--end END] [--keep-noise] [--keep-subframes]
                                 [--keep-redirects]

Chrome history -> categorized XLSX report

options:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        folder holding the ChromeHistory_* files
  -o OUTDIR, --outdir OUTDIR
                        folder to write one workbook per user into
  --start START         only include visits on/after YYYY-MM-DD
  --end END             only include visits on/before YYYY-MM-DD
  --keep-noise          keep ad/tracker/system rows in the user sheets
  --keep-subframes      keep auto-loaded subframe hits (very noisy)
  --keep-redirects      keep intermediate redirect hops
```

---

## 3. Run — full range

```
python chrome_activity_report.py -i "C:\Reports\Captures" --outdir "C:\Reports\Full"
```

```
  reading ChromeHistory_alex.taylorPC01  ->  alex.taylor @ PC01
    17,893 visits kept (55 dropped as noise/duplicate/out-of-range)
  reading ChromeHistory_sam.riveraPC02  ->  sam.rivera @ PC02
    30,944 visits kept (132 dropped as noise/duplicate/out-of-range)

  C:\Reports\Full\Browsing_Activity_alex.taylor.xlsx
      47,296 visits, 40 high-flag, 4,855 downloads
  C:\Reports\Full\Browsing_Activity_sam.rivera.xlsx
      40,315 visits, 0 high-flag, 376 downloads
```

## 4. Run — date window

```
python chrome_activity_report.py -i "C:\Reports\Captures" --outdir "C:\Reports\Aug14-20" --start 08-14-2026 --end 08-20-2026
```

```
  reading ChromeHistory_alex.taylorPC01  ->  alex.taylor @ PC01
    1,734 visits kept (16,214 dropped as noise/duplicate/out-of-range)
  reading ChromeHistory_sam.riveraPC03  ->  sam.rivera @ PC03
    0 visits kept (9,518 dropped as noise/duplicate/out-of-range)

  C:\Reports\Aug14-20\Browsing_Activity_alex.taylor.xlsx
      4,168 visits, 2 high-flag, 12 downloads
  C:\Reports\Aug14-20\Browsing_Activity_sam.rivera.xlsx
      1,239 visits, 0 high-flag, 5 downloads
```

Both bounds inclusive. `0 visits kept` = that capture holds no data in the window.

---

## 5. Quoting

```
-i "C:\Reports\Captures"      OK
-i "C:\Reports\Captures\"     breaks — trailing \ escapes the closing quote
-i C:\Reports\Captures        OK — no quotes needed when the path has no spaces
```

---

## 6. Destination

The collector writes to the local account's profile on each endpoint:

```
C:\Users\LocalCollector\Documents\BrowserData\
```

SYSTEM always has local write access, so there are no share permissions,
no machine-account ACLs, and no stored credentials involved.

Confirm the account exists on a target:

```
Get-LocalUser -Name LocalCollector
```

```
Name     Enabled Description
----     ------- -----------
LocalCollector True    Local support account
```

The folder is created if missing — the whole path, including
`Documents\BrowserData`, and `C:\Users\LocalCollector` itself if the account has
never signed in. If a prior profile collision left it at
`C:\Users\LocalCollector.<COMPUTERNAME>`, the script resolves the real path from
the registry and writes there instead of creating a second wrong folder.

---

## 7. Datto RMM component

Automation -> Components -> New Component

```
Name            : Collect Browser History
Level           : Global
Category        : Scripts
Component Type  : Script
OS              : Windows
Script Engine   : PowerShell
Script          : paste Collect-BrowserHistory.ps1
```

Variables (Value type, all optional):

```
usrTargetUsers  = DOMAIN\first.last          (blank = every profile)
usrLocalAccount = LocalCollector
usrSubfolder    = Documents\BrowserData
usrIncludeEdge  = false
usrMaxAgeDays   = 0
```

Save.

## 7-targets. Targeting specific users (shared PCs)

Leave `usrTargetUsers` blank to collect every profile on the device. To pull
only named users on a shared machine, set it to a comma or semicolon separated
list:

```
usrTargetUsers = DOMAIN\first.last
usrTargetUsers = DOMAIN\first.last, DOMAIN\jane.doe
usrTargetUsers = first.last          # domain optional
```

Each name is resolved to its SID, then to the real profile folder via the
registry, so it works even when the on-disk folder is `first.last.DOMAIN`
after a profile-name collision. The output filename is normalised back to
`first.last` so the report parser reads it correctly.

A user with no profile on that particular device is reported, not fatal:

```
  target  DOMAIN\first.last  ->  C:\Users\first.last
  target  DOMAIN\jane.doe        ->  NOT FOUND on this device
```

```
Result=Copied 2, failed 0. NOT FOUND: DOMAIN\jane.doe
```

This is the usual pattern for shared front-desk PCs: run the job against every
machine the person may have used, targeted at their username, and collect
whichever devices actually have their profile.

## 7a. Test on one device

Device -> Quick Job -> select the component -> Run.

```
=== Browser history collection ===
Device       : PC01
Local account: .\LocalCollector
Include Edge : False
Destination  : C:\Users\LocalCollector\Documents\BrowserData

  ok    ChromeHistory_alex.taylorPC01  (31.2 MB)
  ok    ChromeHistory_alex.taylorPC01P1  (4.8 MB)

Copied 2, skipped 0, failed 0
Location: C:\Users\LocalCollector\Documents\BrowserData
```

Job Result column:

```
Copied 2, skipped 0, failed 0
```

Account missing on that endpoint:

```
FATAL: local account '.\LocalCollector' does not exist on PC01.
```

```
Result=NO LOCAL ACCOUNT 'LocalCollector'
```

Account exists but has never signed in (folder gets created anyway):

```
NOTE: .\LocalCollector has no profile yet; creating C:\Users\LocalCollector\Documents\BrowserData.
```

## 7b. Target group

Build an explicit static group. Do not use a dynamic filter for this.

```
Sites -> [site] -> Device Groups -> New Static Group
Name    : Browser History - Collect
Members : add named devices only
```

## 7c. Job

```
Automation -> Jobs -> New Job
Name      : Collect Browser History - <ticket>
Targets   : Device Group "Browser History - Collect"
Component : Collect Browser History
Schedule  : Run Now  (on-demand)
Options   : [x] Run on next check-in if device offline
Run As    : Local System
```

Leave Run As at Local System. It needs to read other users' AppData, and
because the destination is local it needs no network rights and no stored
credentials.

Scheduled recurrence is a policy decision, not a default. Chrome keeps ~90
days, so recurring collection only matters if retention beyond that is a
documented requirement.

---

## 8. Gather from endpoints

Run from your workstation, under your own credentials, over the admin share.

```
.\Gather-BrowserHistory.ps1 -Computers PC01,PC02,PC03 -Destination "C:\Reports\Captures"
```

```
--- PC01
    ok    ChromeHistory_alex.taylorPC01  (31.2 MB)
    ok    ChromeHistory_alex.taylorPC01P1  (4.8 MB)
--- PC02
    ok    ChromeHistory_alex.taylorPC02  (39.3 MB)
--- PC03
    offline

Pulled 3 file(s) to C:\Reports\Captures
Incomplete:
  PC03 (offline)

Next:
  python chrome_activity_report.py -i "C:\Reports\Captures" --outdir "C:\Reports\Out"
```

Add `-Cleanup` to delete the endpoint copy after a verified size match:

```
.\Gather-BrowserHistory.ps1 -Computers PC01 -Cleanup
```

Filenames carry COMPUTERNAME, so captures from many machines land in one
folder without collision.

---

## 9. Tune categories

Open **Uncategorized Domains** in the output workbook, add high-count domains
to `CATEGORY_RULES` in the script, re-run. First match wins — order matters.

---

---

## 10. GUI

Three ways to launch, in order of least effort for the end user.

Double-click (no terminal):

```
browser_report_gui.pyw
```

The .pyw extension runs under pythonw, so there's no console window. Needs
Python plus openpyxl/tzdata on that machine. If it fails to open, a readable
reason is written to:

```
Documents\BrowserReport_error.log
```

From a terminal (shows errors live):

```
python browser_report_gui.py
```

Standalone .exe (nothing to install) -- see section 11.

All three need chrome_activity_report.py in the same folder as the launcher.
Optional drag-and-drop:

```
pip install tkinterdnd2
```

Without it, use the Add Files / Add Folder buttons; everything else is the same.

---

## 11. Standalone .exe

Removes the Python requirement on other machines. Build once, hand out one file.

On a Windows box with Python installed, put these three in a folder:

```
browser_report_gui.py
chrome_activity_report.py
Build-Exe.bat
```

Double-click `Build-Exe.bat`. When it finishes:

```
dist\BrowserActivityReport.exe
```

Copy that single .exe anywhere. It needs no Python and no packages. Rules live
in chrome_activity_report.py and are baked in at build time, so rebuild after
editing CATEGORY_RULES.

---

## 12. Output handling

Workbooks may contain PHI in the Search Term column. Store access-controlled,
not on a general share. Same for the raw captures gathered into
`C:\Reports\Captures` and the copies left in the LocalCollector profile on each endpoint.
