# Helper tools

Two kinds of things live here:

```
tools/
├─ scripts/   PowerShell helpers that act on your real game install
└─ bin/       C# console tools (build outputs, not committed)
```

---

## scripts/

| Script | What it does |
| --- | --- |
| `Install-OnlineFix.ps1` | Copies the payload from `package\` into your Dimraeth folder, backing up the original DLL. `-Remove` puts it back. |
| `Start-Dimraeth.ps1` | Launches the game through Steam, after checking that the fix and ZeroTier are in place. |
| `Get-Diagnostics.ps1` | Writes a full report: process, sockets, config, game logs, ZeroTier, and a decode of the emulator's network traffic. |
| `Test-LobbyDiscovery.ps1` | Spins up a second emulator instance and runs the real client flow against your lobby. |

All four are optional. The fix itself needs no installer and no launcher — you can
copy the files by hand and press Play in Steam. These scripts exist for
convenience and for diagnosing problems.

```powershell
# from the repository root
pwsh -File .\tools\scripts\Install-OnlineFix.ps1
pwsh -File .\tools\scripts\Start-Dimraeth.ps1
pwsh -File .\tools\scripts\Get-Diagnostics.ps1 -Seconds 30
pwsh -File .\tools\scripts\Test-LobbyDiscovery.ps1
```

---

## bin/

Build these with `dev\packaging\build.ps1`; the executables are not committed (see
`.gitignore`).

| Tool | Purpose |
| --- | --- |
| `JoinTest.exe` | Lobby discovery / join test. Runs the real client flow (`RequestLobbyList` → `GetLobbyByIndex` → `JoinLobby` → `GetNumLobbyMembers`) against a hosting game. |
| `LobbyHarness.exe` | Drives the emulator's lobby API directly. Used to verify lobby propagation between two emulator instances. |
| `PacketSniffer.exe` | Decodes the emulator's announce broadcast so you can see who is announcing, on which interface, with which AppID — and, most importantly, the **real SteamID64** of each sender. |

All three load `steam_api64.dll` from a directory you pass with `--dir`, so they do
not depend on the game being installed.

### JoinTest

```powershell
.\tools\bin\JoinTest.exe --dir <instanceDir> [--seconds 60] [--poll 3000] [--log FILE]
```

The instance directory needs the emulator DLL plus `steam_appid.txt` containing
`480`. Exits `0` when a lobby was found and the join was accepted, `10` when no
lobby was visible, `11` when a lobby was found but the member count did not rise.

Also available as `tools\scripts\Test-LobbyDiscovery.ps1`, which prepares the
instance directory and checks that the game is hosting first.

**Scope:** matchmaking layer only. A successful join does not prove a player
spawns in the game's party — that also needs the P2P data channel and Netcode
approval. See `docs\TESTING.md`.

### LobbyHarness

```powershell
# one terminal
.\tools\bin\LobbyHarness.exe --dir <instanceA> --host 8 --seconds 120 --tag HOST

# another terminal
.\tools\bin\LobbyHarness.exe --dir <instanceB> --joinauto --seconds 60 --tag CLIENT
```

Modes: `--host [maxMembers]`, `--join <lobbyId>`, `--joinauto`, `--list`.
Common options: `--seconds N`, `--tag NAME`, `--interval MS`, `--log FILE`.

Exits `0` on success, `10` when nothing was found. On success the host prints
`HOST_SEES_MEMBERS=2` and the client prints `JOINED ... members=2`.

The 47584 hub rule matters here: only one process per machine can own UDP 47584,
and the others fall back to 47585+. Discovery still works because the 47584 owner
relays, but the instance on 47584 must be the one you want as host.

### PacketSniffer

```powershell
.\tools\bin\PacketSniffer.exe [--seconds 30] [--ports 47584,47585] [--log FILE] [--listen-only] [--hex]
```

The game holds `0.0.0.0:47584`, which blocks any later wildcard bind on that port.
This tool binds **specific** addresses instead (`127.0.0.1`, each local IPv4),
which Windows permits — and because the emulator broadcasts to every interface,
those sockets receive a copy without stealing anything from the game.

`--listen-only` skips sending its own probe announce.
`--hex` also dumps every protobuf field with its raw bytes, which is what you want
when checking the encoding itself.

Exits `0` when announces were decoded, `10` when nothing was heard.

#### Reading the output

Each announce carries **two different 64-bit ids**, and mixing them up is the
single easiest mistake to make here:

- **`key=`** / `source_id` — Goldberg's internal connection key (`0x0130 0001…`).
  Stable per instance, handy for telling instances apart, **not** a SteamID, and
  it will never match any settings file.
- **`real steamid =`** — the sender's actual SteamID64 (`0x0110 0001…`), read out
  of `Announce.ids`. This one is byte-for-byte the value in that machine's
  `%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt`.

So to answer "is the other player reaching me?", look at the `real SteamIDs heard`
block, or grep a `--hex` capture for their SteamID64 directly. If their SteamID
never shows up, their announce is not arriving and the problem is the network
path. See `docs\TESTING.md` for the full decode.

---

## Building

```powershell
# from the repository root
pwsh -File .\dev\packaging\build.ps1
```

Compiled with the classic .NET Framework `csc.exe`. The .NET 10 Roslyn compiler
fails on Windows builds without full CET support, so the sources in `dev\src\` are
written in C# 5 style — no local functions, no tuples.
