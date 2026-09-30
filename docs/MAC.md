# Native Mac client

Build on macOS 15+ with Swift 6 / Xcode 16+:

```sh
swift test
bash scripts/build.sh
open "dist/Flodo Open.app"
```

The build script selects the sole available Apple Development/Distribution identity, or uses explicit `FLODO_SIGNING_IDENTITY`. With no unambiguous identity it uses ad-hoc signing and explains the limitation. For public distribution/notarization use your own Developer ID workflow. Never include signing keys in the repository. A changed ad-hoc signature can invalidate Keychain trust after each update.

Mac 0.3.2 reads Keychain without authentication UI during background sync and caches the result in memory. If access is unavailable, sync pauses until the user presses Connect in Settings → Telegram sync. During the one-time migration from an old signature, choose Always Allow. No secrets are written into board.json. Force quitting an app with an open editor can lose a draft; restart only when safe.

Endpoint: `https://DOMAIN/index.php?route=sync` (SSH or Vercel compatibility route). Use the independent sync token, not the Telegram bot token. Enter through SecureField or stdin:

```python
import json, subprocess
from pathlib import Path
connection = json.loads(Path('.deploy/client.json').read_text())
subprocess.run(['dist/Flodo Open.app/Contents/MacOS/FlodoOpen',
                '--configure-sync', connection['endpoint']],
               input=connection['token'], text=True, check=True)
```

The CLI process saves config and key only; reopen the GUI safely to load it. Settings → Connect can configure a currently running instance.

Data lives in `~/Library/Application Support/FlodoOpen/board.json`; previous atomic snapshot in `board.previous.json`; sync conflict copies in `Sync Conflicts`. Use `FLODO_OPEN_HOME` for isolated tests. Do not point tests at real data.

`flowctl` inside the app bundle shares the native repository. Commands include list, add, move, done, reopen and export. JSON imports add missing UUIDs instead of overwriting the whole board. Flodo import reads its original SQLite store without modifying it; verify column mappings after import. Back up before migrating.
