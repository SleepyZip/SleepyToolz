@echo off
REM ===================================================================
REM  Build BrowserActivityReport.exe  --  run this on a Windows box that
REM  has Python installed. Produces one standalone .exe that needs no
REM  Python and no packages on the machines you hand it to.
REM
REM  Just double-click this file, or run it from a terminal. Output lands
REM  in the dist\ folder next to this script.
REM ===================================================================

setlocal
cd /d "%~dp0"

if not exist "browser_report_gui.py" (
    echo.
    echo Cannot find browser_report_gui.py in this folder:
    echo    %~dp0
    echo Put Build-Exe.bat, browser_report_gui.py, and chrome_activity_report.py
    echo all in ONE folder, then run this again.
    pause
    exit /b 1
)
if not exist "chrome_activity_report.py" (
    echo.
    echo Cannot find chrome_activity_report.py in this folder:
    echo    %~dp0
    echo It must sit next to Build-Exe.bat. Move it here and run this again.
    pause
    exit /b 1
)

echo Installing build dependencies...
python -m pip install --upgrade pyinstaller openpyxl tzdata >nul 2>&1
if errorlevel 1 (
    echo.
    echo Could not install packages. Is Python on PATH?
    echo Try:  py -m pip install pyinstaller openpyxl tzdata
    pause
    exit /b 1
)

echo Building BrowserActivityReport.exe ...
python -m PyInstaller --onefile --windowed ^
    --name BrowserActivityReport ^
    --collect-all tzdata ^
    --hidden-import chrome_activity_report ^
    --add-data "%~dp0chrome_activity_report.py;." ^
    "%~dp0browser_report_gui.py"

if errorlevel 1 (
    echo.
    echo Build failed. See the messages above.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Done.  Your program is:
echo     dist\BrowserActivityReport.exe
echo.
echo  Copy that single file anywhere. No Python needed to run it.
echo ============================================================
pause
