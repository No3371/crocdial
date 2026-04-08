param(
    [Parameter(Mandatory=$true)]
    [string]$Recipient,

    [Parameter(Mandatory=$true)]
    [string]$CodePhrase,

    [ValidateSet("dial","message")]
    [string]$Mode = "dial",

    [string]$Relay,

    [switch]$Force
)

# --- Banner ---
Write-Host ""
Write-Host "  =====================" -ForegroundColor Green
Write-Host "     crocdial" -ForegroundColor Green
Write-Host "  =====================" -ForegroundColor Green
Write-Host ""

# --- Validation ---
$RecipientLower = $Recipient.Trim().ToLower()

if ($RecipientLower -notmatch '^[a-z0-9_-]+$') {
    Write-Error "Invalid recipient name. Use only letters, digits, hyphens, and underscores."
    exit 1
}

if ($CodePhrase.Length -lt 6) {
    Write-Error "Code phrase must be at least 6 characters."
    exit 1
}

if ($CodePhrase -notmatch '^[a-zA-Z0-9_.'' -]+$') {
    Write-Error "Code phrase contains invalid characters. Use only letters, digits, spaces, hyphens, dots, apostrophes, and underscores."
    exit 1
}

if ($Relay) {
    if ($Relay -notmatch '^[a-zA-Z0-9._-]+(:\d+)?$') {
        Write-Error "Invalid relay format. Use hostname or hostname:port (e.g. myrelay.com:9009)."
        exit 1
    }
}

# --- Output paths ---
$DialsDir = Join-Path $PSScriptRoot "dials"
$BatFile  = Join-Path $DialsDir "${RecipientLower}_${Mode}.bat"
$ShFile   = Join-Path $DialsDir "${RecipientLower}_${Mode}.sh"

# --- Overwrite protection ---
if (-not $Force) {
    $existing = @()
    if (Test-Path $BatFile) { $existing += $BatFile }
    if (Test-Path $ShFile)  { $existing += $ShFile }
    if ($existing.Count -gt 0) {
        Write-Error "File(s) already exist:`n  $($existing -join "`n  ")`nUse -Force to overwrite."
        exit 1
    }
}

# --- Ensure dials/ exists ---
New-Item -ItemType Directory -Path $DialsDir -Force | Out-Null

# --- Build relay flags ---
$BatRelayFlag = ""
$ShRelayFlag  = ""
if ($Relay) {
    $BatRelayFlag = " --relay $Relay"
    $ShRelayFlag  = " --relay `"$Relay`""
}

# --- Shared: croc check snippets ---
$BatCrocCheck = @"
where croc >nul 2>nul
if errorlevel 1 (
    echo.
    echo  croc is not installed or not in PATH.
    echo.
    echo  Install it with one of:
    echo    winget install schollz.croc
    echo    scoop install croc
    echo    choco install croc
    echo    https://github.com/schollz/croc/releases
    echo.
    pause
    exit /b 1
)
"@

$ShCrocCheck = @"
if ! command -v croc &>/dev/null; then
    echo ""
    echo "  croc is not installed or not in PATH."
    echo ""
    echo "  Install it with one of:"
    echo "    curl https://getcroc.schollz.com | bash"
    echo "    brew install croc"
    echo "    sudo apt install croc"
    echo "    sudo snap install croc"
    echo "    https://github.com/schollz/croc/releases"
    echo ""
    exit 1
fi
"@

# --- Generate content based on mode ---
if ($Mode -eq "dial") {

    $BatContent = @"
@echo off
set "SCRIPTDIR=%~dp0"
setlocal EnableDelayedExpansion

$BatCrocCheck

if "%~1"=="" goto :RECEIVE

:SEND
echo.
echo  =====================
echo     crocdial - SEND
echo     to: $Recipient
echo  =====================
echo.
croc$BatRelayFlag send --code "$CodePhrase" %*
goto :END

:RECEIVE
echo.
echo  =====================
echo     crocdial - RECEIVE
echo     from: $Recipient
echo  =====================
echo.
if not exist "%SCRIPTDIR%inbox\" mkdir "%SCRIPTDIR%inbox"
pushd "%SCRIPTDIR%inbox"
set /a RETRIES=0
:RETRY
croc --yes$BatRelayFlag "$CodePhrase"
if errorlevel 1 (
    set /a RETRIES+=1
    if !RETRIES! geq 60 (
        echo.
        echo  Timed out after 5 minutes. Check the code phrase and try again.
        popd
        goto :END
    )
    echo.
    echo  Waiting for sender... retrying in 5s [attempt !RETRIES!/60]
    timeout /t 5 /nobreak >nul
    goto :RETRY
)
popd
goto :END

:END
echo.
pause
"@

    $ShContent = @"
#!/usr/bin/env bash
set -euo pipefail

$ShCrocCheck

INBOX="`$(cd "`$(dirname "`$0")" && pwd)/inbox"
if [ `$# -eq 0 ]; then
    echo ""
    echo "  ====================="
    echo "     crocdial - RECEIVE"
    echo "     from: $Recipient"
    echo "  ====================="
    echo ""
    mkdir -p "`$INBOX"
    cd "`$INBOX"
    RETRIES=0
    while true; do
        if croc --yes$ShRelayFlag "$CodePhrase"; then
            break
        fi
        RETRIES=`$((RETRIES + 1))
        if [ `$RETRIES -ge 60 ]; then
            echo ""
            echo "  Timed out after 5 minutes. Check the code phrase and try again."
            exit 1
        fi
        echo ""
        echo "  Waiting for sender... retrying in 5s [attempt `$RETRIES/60]"
        sleep 5
    done
else
    echo ""
    echo "  ====================="
    echo "     crocdial - SEND"
    echo "     to: $Recipient"
    echo "  ====================="
    echo ""
    croc$ShRelayFlag send --code "$CodePhrase" "`$@"
fi
"@

    $UsageText = @"
    Double-click (or run with no args) -> receive mode
    Drag files onto script (or pass as args) -> send mode
"@

} elseif ($Mode -eq "message") {

    $BatContent = @"
@echo off
set "SCRIPTDIR=%~dp0"
setlocal EnableDelayedExpansion

$BatCrocCheck

if "%~1"=="" goto :SEND_MESSAGE

:RECEIVE
echo.
echo  ========================
echo     crocdial - RECEIVE
echo     message from: $Recipient
echo  ========================
echo.
if not exist "%SCRIPTDIR%inbox\" mkdir "%SCRIPTDIR%inbox"
pushd "%SCRIPTDIR%inbox"
set /a RETRIES=0
:RETRY
croc --yes$BatRelayFlag "$CodePhrase"
if errorlevel 1 (
    set /a RETRIES+=1
    if !RETRIES! geq 60 (
        echo.
        echo  Timed out after 5 minutes. Check the code phrase and try again.
        popd
        goto :END
    )
    echo.
    echo  Waiting for sender... retrying in 5s [attempt !RETRIES!/60]
    timeout /t 5 /nobreak >nul
    goto :RETRY
)
popd
goto :END

:SEND_MESSAGE
echo.
echo  ========================
echo     crocdial - MESSAGE
echo     to: $Recipient
echo  ========================
echo.
echo  Type your message, then press Enter to send:
echo.
set /p MSG=^>
if "!MSG!"=="" (
    echo  No message entered. Aborted.
    goto :END
)
set "TMPFILE=%TEMP%\crocdial_msg_%RANDOM%.txt"
>"%TMPFILE%" echo(!MSG!
croc$BatRelayFlag send --code "$CodePhrase" "%TMPFILE%"
goto :END

:END
if defined TMPFILE del "%TMPFILE%" 2>nul
echo.
pause
"@

    $ShContent = @"
#!/usr/bin/env bash
set -euo pipefail

$ShCrocCheck

INBOX="`$(cd "`$(dirname "`$0")" && pwd)/inbox"
if [ `$# -eq 0 ]; then
    echo ""
    echo "  ========================"
    echo "     crocdial - MESSAGE"
    echo "     to: $Recipient"
    echo "  ========================"
    echo ""
    echo "  Type your message, then press Enter to send:"
    echo ""
    read -r -p "> " MSG </dev/tty
    if [ -z "`$MSG" ]; then
        echo "  No message entered. Aborted."
        exit 1
    fi
    TMPFILE=`$(mktemp /tmp/crocdial_msg.XXXXXX.txt)
    trap 'rm -f "`$TMPFILE"' EXIT
    echo "`$MSG" > "`$TMPFILE"
    croc$ShRelayFlag send --code "$CodePhrase" "`$TMPFILE"</dev/null
    rm -f "`$TMPFILE"
else
    echo ""
    echo "  ========================"
    echo "     crocdial - RECEIVE"
    echo "     message from: $Recipient"
    echo "  ========================"
    echo ""
    mkdir -p "`$INBOX"
    cd "`$INBOX"
    RETRIES=0
    while true; do
        if croc --yes$ShRelayFlag "$CodePhrase"; then
            break
        fi
        RETRIES=`$((RETRIES + 1))
        if [ `$RETRIES -ge 60 ]; then
            echo ""
            echo "  Timed out after 5 minutes. Check the code phrase and try again."
            exit 1
        fi
        echo ""
        echo "  Waiting for sender... retrying in 5s [attempt `$RETRIES/60]"
        sleep 5
    done
fi
"@

    $UsageText = @"
    Double-click (or run with no args) -> type and send a message
    Run with any arg (e.g. 'receive') -> receive mode
"@

}

# --- Write .bat with ASCII encoding ---
[System.IO.File]::WriteAllText($BatFile, $BatContent, [System.Text.Encoding]::ASCII)

# --- Write .sh with LF line endings (UTF-8 no BOM) ---
$ShContentLF = $ShContent -replace "`r`n", "`n"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($ShFile, $ShContentLF, $Utf8NoBom)

# --- Summary ---
Write-Host "  Generated ($Mode mode):" -ForegroundColor Cyan
Write-Host "    $BatFile" -ForegroundColor White
Write-Host "    $ShFile" -ForegroundColor White
Write-Host ""
Write-Host "  Recipient : $Recipient" -ForegroundColor Gray
Write-Host "  Code phrase: $CodePhrase" -ForegroundColor Gray
if ($Relay) {
    Write-Host "  Relay     : $Relay" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Usage:" -ForegroundColor Cyan
Write-Host $UsageText -ForegroundColor Gray
Write-Host ""
