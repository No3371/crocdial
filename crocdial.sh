#!/usr/bin/env bash
set -euo pipefail

# --- Defaults ---
MODE="dial"
RELAY=""
FORCE=false
RECIPIENT=""
CODE_PHRASE=""

# --- Usage ---
usage() {
    echo ""
    echo "  Usage: crocdial.sh -r <recipient> -c <code-phrase> [-m dial|message] [-R relay] [-f]"
    echo ""
    echo "  Options:"
    echo "    -r  Recipient name (required)"
    echo "    -c  Code phrase, min 6 chars (required)"
    echo "    -m  Mode: dial (default) or message"
    echo "    -R  Relay host or host:port"
    echo "    -f  Force overwrite existing scripts"
    echo ""
    exit 1
}

# --- Parse args ---
while getopts "r:c:m:R:fh" opt; do
    case $opt in
        r) RECIPIENT="$OPTARG" ;;
        c) CODE_PHRASE="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        R) RELAY="$OPTARG" ;;
        f) FORCE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Banner ---
echo ""
echo "  ====================="
echo "     crocdial"
echo "  ====================="
echo ""

# --- Validation ---
if [ -z "$RECIPIENT" ] || [ -z "$CODE_PHRASE" ]; then
    echo "  Error: -r (recipient) and -c (code phrase) are required." >&2
    usage
fi

RECIPIENT_LOWER=$(echo "$RECIPIENT" | tr '[:upper:]' '[:lower:]')

if ! [[ "$RECIPIENT_LOWER" =~ ^[a-z0-9_-]+$ ]]; then
    echo "  Error: Invalid recipient name. Use only letters, digits, hyphens, and underscores." >&2
    exit 1
fi

if [ ${#CODE_PHRASE} -lt 6 ]; then
    echo "  Error: Code phrase must be at least 6 characters." >&2
    exit 1
fi

if ! [[ "$CODE_PHRASE" =~ ^[a-zA-Z0-9_.' '-]+$ ]]; then
    echo "  Error: Code phrase contains invalid characters." >&2
    exit 1
fi

if [[ "$MODE" != "dial" && "$MODE" != "message" ]]; then
    echo "  Error: Mode must be 'dial' or 'message'." >&2
    exit 1
fi

if [ -n "$RELAY" ]; then
    if ! [[ "$RELAY" =~ ^[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; then
        echo "  Error: Invalid relay format. Use hostname or hostname:port." >&2
        exit 1
    fi
fi

# --- Output paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIALS_DIR="$SCRIPT_DIR/dials"
BAT_FILE="$DIALS_DIR/${RECIPIENT_LOWER}_${MODE}.bat"
SH_FILE="$DIALS_DIR/${RECIPIENT_LOWER}_${MODE}.sh"

# --- Overwrite protection ---
if [ "$FORCE" = false ]; then
    EXISTING=""
    [ -f "$BAT_FILE" ] && EXISTING="$EXISTING  $BAT_FILE\n"
    [ -f "$SH_FILE" ] && EXISTING="$EXISTING  $SH_FILE\n"
    if [ -n "$EXISTING" ]; then
        echo "  Error: File(s) already exist:" >&2
        printf '%b' "$EXISTING" >&2
        echo "  Use -f to overwrite." >&2
        exit 1
    fi
fi

# --- Ensure dials/ exists ---
mkdir -p "$DIALS_DIR"

# --- Build relay flags ---
BAT_RELAY_FLAG=""
SH_RELAY_FLAG=""
if [ -n "$RELAY" ]; then
    BAT_RELAY_FLAG=" --relay $RELAY"
    SH_RELAY_FLAG=" --relay \"$RELAY\""
fi

# --- Generate based on mode ---
if [ "$MODE" = "dial" ]; then

    cat > "$BAT_FILE" <<BATEOF
@echo off
set "SCRIPTDIR=%~dp0"
setlocal EnableDelayedExpansion

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

if "%~1"=="" goto :RECEIVE

:SEND
echo.
echo  =====================
echo     crocdial - SEND
echo     to: $RECIPIENT
echo  =====================
echo.
croc$BAT_RELAY_FLAG send %* --code "$CODE_PHRASE" 
goto :END

:RECEIVE
echo.
echo  =====================
echo     crocdial - RECEIVE
echo     from: $RECIPIENT
echo  =====================
echo.
if not exist "%SCRIPTDIR%inbox\\" mkdir "%SCRIPTDIR%inbox"
pushd "%SCRIPTDIR%inbox"
set /a RETRIES=0
:RETRY
croc --yes$BAT_RELAY_FLAG "$CODE_PHRASE"
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
BATEOF

    cat > "$SH_FILE" <<'SHEOF_START'
#!/usr/bin/env bash
set -euo pipefail

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

INBOX="$(cd "$(dirname "$0")" && pwd)/inbox"
SHEOF_START
    cat >> "$SH_FILE" <<SHEOF_END
if [ \$# -eq 0 ]; then
    echo ""
    echo "  ====================="
    echo "     crocdial - RECEIVE"
    echo "     from: $RECIPIENT"
    echo "  ====================="
    echo ""
    mkdir -p "\$INBOX"
    cd "\$INBOX"
    RETRIES=0
    while true; do
        if croc --yes$SH_RELAY_FLAG "$CODE_PHRASE"; then
            break
        fi
        RETRIES=\$((RETRIES + 1))
        if [ \$RETRIES -ge 60 ]; then
            echo ""
            echo "  Timed out after 5 minutes. Check the code phrase and try again."
            exit 1
        fi
        echo ""
        echo "  Waiting for sender... retrying in 5s [attempt \$RETRIES/60]"
        sleep 5
    done
else
    echo ""
    echo "  ====================="
    echo "     crocdial - SEND"
    echo "     to: $RECIPIENT"
    echo "  ====================="
    echo ""
    croc$SH_RELAY_FLAG send "\$@" --code "$CODE_PHRASE" 
fi
SHEOF_END

    USAGE_TEXT="    Double-click (or run with no args) -> receive mode
    Drag files onto script (or pass as args) -> send mode"

elif [ "$MODE" = "message" ]; then

    cat > "$BAT_FILE" <<BATEOF
@echo off
set "SCRIPTDIR=%~dp0"
setlocal EnableDelayedExpansion

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

if "%~1"=="" goto :SEND_MESSAGE

:RECEIVE
echo.
echo  ========================
echo     crocdial - RECEIVE
echo     message from: $RECIPIENT
echo  ========================
echo.
if not exist "%SCRIPTDIR%inbox\\" mkdir "%SCRIPTDIR%inbox"
pushd "%SCRIPTDIR%inbox"
set /a RETRIES=0
:RETRY
croc --yes$BAT_RELAY_FLAG "$CODE_PHRASE"
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
echo     to: $RECIPIENT
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
croc$BAT_RELAY_FLAG send "%TMPFILE%" --code "$CODE_PHRASE" 
goto :END

:END
if defined TMPFILE del "%TMPFILE%" 2>nul
echo.
pause
BATEOF

    cat > "$SH_FILE" <<'SHEOF_START'
#!/usr/bin/env bash
set -euo pipefail

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

INBOX="$(cd "$(dirname "$0")" && pwd)/inbox"
SHEOF_START
    cat >> "$SH_FILE" <<SHEOF_END
if [ \$# -eq 0 ]; then
    echo ""
    echo "  ========================"
    echo "     crocdial - MESSAGE"
    echo "     to: $RECIPIENT"
    echo "  ========================"
    echo ""
    echo "  Type your message, then press Enter to send:"
    echo ""
    read -r -p "> " MSG </dev/tty
    if [ -z "\$MSG" ]; then
        echo "  No message entered. Aborted."
        exit 1
    fi
    TMPFILE=\$(mktemp /tmp/crocdial_msg.XXXXXX.txt)
    trap 'rm -f "\$TMPFILE"' EXIT
    echo "\$MSG" > "\$TMPFILE"
    croc$SH_RELAY_FLAG send "\$TMPFILE" --code "$CODE_PHRASE"</dev/null
    rm -f "\$TMPFILE"
else
    echo ""
    echo "  ========================"
    echo "     crocdial - RECEIVE"
    echo "     message from: $RECIPIENT"
    echo "  ========================"
    echo ""
    mkdir -p "\$INBOX"
    cd "\$INBOX"
    RETRIES=0
    while true; do
        if croc --yes$SH_RELAY_FLAG "$CODE_PHRASE"; then
            break
        fi
        RETRIES=\$((RETRIES + 1))
        if [ \$RETRIES -ge 60 ]; then
            echo ""
            echo "  Timed out after 5 minutes. Check the code phrase and try again."
            exit 1
        fi
        echo ""
        echo "  Waiting for sender... retrying in 5s [attempt \$RETRIES/60]"
        sleep 5
    done
fi
SHEOF_END

    USAGE_TEXT="    Double-click (or run with no args) -> type and send a message
    Run with any arg (e.g. 'receive') -> receive mode"

fi

# --- Fix .sh line endings (strip any CR) and make executable ---
sed -i 's/\r$//' "$SH_FILE"
chmod +x "$SH_FILE"

# --- Summary ---
echo "  Generated ($MODE mode):"
echo "    $BAT_FILE"
echo "    $SH_FILE"
echo ""
echo "  Recipient : $RECIPIENT"
echo "  Code phrase: $CODE_PHRASE"
if [ -n "$RELAY" ]; then
    echo "  Relay     : $RELAY"
fi
echo ""
echo "  Usage:"
echo "$USAGE_TEXT"
echo ""
