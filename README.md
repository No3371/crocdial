# crocdial

Generate pre-configured [croc](https://github.com/schollz/croc) scripts for file transfer and messaging. Each generated script has a baked-in code phrase — double-click to receive, drag files to send.

## Quick Start

**PowerShell** (Windows):
```powershell
.\crocdial.ps1 -Recipient alice -CodePhrase "our-secret-phrase"
.\crocdial.ps1 -Recipient alice -CodePhrase "msg-phrase-456" -Mode message
.\crocdial.ps1 -Recipient bob -CodePhrase "bob-phrase" -Relay "myrelay.com:9009"
```

**Bash** (Linux/macOS/WSL):
```bash
./crocdial.sh -r alice -c "our-secret-phrase"
./crocdial.sh -r alice -c "msg-phrase-456" -m message
./crocdial.sh -r bob -c "bob-phrase" -R "myrelay.com:9009"
```

Scripts are written to `dials/`:
```
dials/alice_dial.bat      # Windows file transfer
dials/alice_dial.sh       # Unix file transfer
dials/alice_message.bat   # Windows messaging
dials/alice_message.sh    # Unix messaging
```

## Modes

### `dial` (default)
| Action | Behavior |
|---|---|
| Double-click / no args | Receive — waits for sender, retries automatically |
| Drag files onto script / pass args | Send files |

### `message`
| Action | Behavior |
|---|---|
| Double-click / no args | Prompts for text input, sends as file |
| Run with any arg | Receive — waits for sender, retries automatically |

Received files land in `dials/inbox/`.

## Parameters

| PowerShell | Bash | Required | Description |
|---|---|---|---|
| `-Recipient` | `-r` | Yes | Name for the script (letters, digits, hyphens, underscores) |
| `-CodePhrase` | `-c` | Yes | Shared secret (min 6 chars) |
| `-Mode` | `-m` | No | `dial` (default) or `message` |
| `-Relay` | `-R` | No | Self-hosted relay (`host` or `host:port`) |
| `-Force` | `-f` | No | Overwrite existing scripts |

## Requirements

- **Generator**: PowerShell 5.1+ or Bash 4+
- **Generated scripts**: [croc](https://github.com/schollz/croc) must be installed on both machines

## Notes

- The sender must start before the receiver connects. Receiver scripts retry automatically every 5 seconds until a sender is available.
- Code phrases can be reused across transfers — the relay room frees up after each completed transfer.
- `dials/` is gitignored since scripts contain embedded code phrases.
