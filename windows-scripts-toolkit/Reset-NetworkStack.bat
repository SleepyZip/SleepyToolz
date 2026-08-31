@echo off
:: Classic network reset - the "have you tried turning it off and on again"
:: of network troubleshooting. Requires admin rights.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This script needs to run as Administrator. Right-click and "Run as administrator".
    pause
    exit /b 1
)

echo Releasing IP address...
ipconfig /release

echo Renewing IP address...
ipconfig /renew

echo Flushing DNS cache...
ipconfig /flushdns

echo Resetting Winsock catalog...
netsh winsock reset

echo Resetting TCP/IP stack...
netsh int ip reset

echo.
echo Done. A reboot is required for the Winsock/TCP-IP resets to take effect.
pause
