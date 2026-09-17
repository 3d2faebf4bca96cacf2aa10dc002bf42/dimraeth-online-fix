# Dimraeth — Online Co-op Fix

Play **Dimraeth** in co-op with a friend over the internet, without a Steam
lobby, without a dedicated server, and without owning the game twice.

Dimraeth ships no server browser of its own. It relies on Steam for matchmaking
and peer-to-peer connections, which means two players behind different routers
cannot see each other. This project replaces the Steam API layer with a local LAN
emulator and uses **ZeroTier** to bridge the two machines onto one virtual
network, so the game's own lobby discovery keeps working — over the internet.

**Six files. No installer, no launcher, no batch script.** Copy the payload and
press **Play** in Steam.

> **Scope:** an unofficial interoperability fix, shared between friends. It
> circumvents no copy protection, because Dimraeth has none. Not affiliated with
> the game's developers or with Valve.

---

## Contents

- [What you get](#what-you-get)
- [How it works](#how-it-works)
- [Install](#install)
- [Networking with ZeroTier](#networking-with-zerotier)
- [Playing](#playing)
- [Windows Firewall](#windows-firewall)
- [How to tell it is working](#how-to-tell-it-is-working)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Diagnostics and tools](#diagnostics-and-tools)
- [Repository layout](#repository-layout)
- [Technical details](#technical-details)
- [Limits](#limits)
- [Credits and licence](#credits-and-licence)

---

## What you get

The payload is six files that go inside your existing Dimraeth install:

```
Dimraeth_Data\Plugins\x86_64\
├─ steam_api64.dll                  the emulator (replaces Valve's)
├─ steam_appid.txt                  480
└─ steam_settings\
   ├─ steam_appid.txt               480   (the emulator reads this one first)
   ├─ force_listen_port.txt         47584
   ├─ force_account_name.txt        Spacewar Player
   └─ custom_broadcasts.txt         optional, for the fallback below
```

| File | Change |
| --- | --- |
| `steam_api64.dll` | **replaced** — Goldberg emulator (1,958,912 B) instead of Valve's (262,944 B) |
| `steam_appid.txt` | new — `480` |
| `steam_settings\steam_appid.txt` | new — `480` |
| `steam_settings\force_listen_port.txt` | new — `47584` |
| `steam_settings\force_account_name.txt` | new — the name shown in the party list |
| `steam_settings\custom_broadcasts.txt` | new — comments only, for the fallback below |

No other game file is touched.

---

## How it works

Dimraeth has **no Steam DRM** — no `.bind` section, no `CSteamDRM`, no reference to
Steam of any kind in `Dimraeth.exe`. Without DRM the Steam client only *starts* the
executable; it does **not** replace or validate `steam_api64.dll` in the game
folder. So the emulator you copy in is the one that loads, and the Steam Play
button keeps working normally.

Measured, launched through Steam: the game process's parent is `steam`, the
emulator binds **UDP and TCP 47584**, and the AppID the game sees is **480**.

### Why AppID 480 is invisible in Steam

The emulator is its own Steam implementation and never talks to the Steam client.
Steam sees AppID `2402680` because it launched that; the emulator reports `480` to
the game. The two never meet, so Steam shows **"Dimraeth — Running"**, which is
what you want.

480 is a community convention, not a functional requirement. The emulator matches
peers on the AppID and the discovery port, so what actually matters is that
**every player uses the same pair of values**.

### Why each player needs a unique SteamID

The emulator indexes peers by SteamID, so two players with the same ID cannot
connect. It generates one on first run with `RtlGenRandom` (the Windows CSPRNG)
and stores it in:

```
%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt
```

**Nothing in this repository ships a SteamID.** If one were included, every player
copying the folder would inherit the same identity and nobody would connect. This
was a real bug during development, so it is stated loudly and the packaging script
refuses to build a zip if one is present.

### Why ZeroTier is required

The emulator finds peers by **broadcasting** on the local network. It has no relay
servers and no NAT traversal of its own, so two PCs behind different routers can
never see each other's broadcasts. ZeroTier provides the missing Layer 2 segment:
broadcast traffic flows across it exactly as if both machines were on the same
network cable.

```
   Your PC                                          Friend's PC
   ┌──────────────────────┐                        ┌──────────────────────┐
   │ Dimraeth.exe         │                        │ Dimraeth.exe         │
   │   └─ steam_api64.dll │  (emulator)            │   └─ steam_api64.dll │
   └──────────┬───────────┘                        └──────────┬───────────┘
              │  UDP + TCP 47584                              │  UDP + TCP 47584
              │  broadcast "I am here, AppID 480"             │
              ▼                                               ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │                     ZeroTier virtual network                         │
   │                     e.g. 10.147.20.7  ←→  10.147.20.42               │
   └──────────────────────────────────────────────────────────────────────┘
```

---

## Install

### Requirements

- Dimraeth installed through Steam (Windows 10 or 11, x64 build)
- [ZeroTier One](https://www.zerotier.com/download/) on both machines
- The **same game version** on both machines — the game checks this when joining
- About 10 minutes, once

You do **not** need a second Steam copy, to forward any port on your router, or to
disable your antivirus permanently.

### Manual install

1. Find your Dimraeth folder. In Steam: right-click **Dimraeth** →
   **Manage** → **Browse local files**. By default:

   ```
   C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\
   ```

2. Copy the **`Dimraeth_Data`** folder from `package\` into it.

3. Windows will ask whether to merge folders. Say **yes**, and accept the
   **Replace the file in the destination** prompt for `steam_api64.dll` — that is
   the one file that already exists and must be overwritten.

4. Press **Play** in Steam.

When you are done the game folder looks like this:

```
Dimraeth\
├─ Dimraeth.exe                              (untouched)
├─ UnityPlayer.dll                           (untouched)
├─ Dimraeth_Data\
│  └─ Plugins\
│     └─ x86_64\
        ├─ fmodstudio.dll                    (untouched)
        ├─ steam_api64.dll                   ← REPLACED
        ├─ steam_appid.txt                   ← new
        └─ steam_settings\                   ← new
           └─ ... four files
```

> **Do not** copy only `steam_api64.dll`. The four files in `steam_settings\`
> control the AppID, the network port and your display name. Without them the
> emulator falls back to defaults, and if your default port differs from your
> friend's you will never find each other.

### Or let the script do it

```powershell
pwsh -File .\tools\scripts\Install-OnlineFix.ps1
```

It backs the original DLL up as `steam_api64.dll.original` before overwriting, and
`-Remove` restores it.

### Giving the fix to someone else

Send them `Dimraeth-OnlineFix.zip` (built by `dev\packaging\make-package.ps1`, or
downloaded from Releases). It contains the payload plus a short README for the
recipient. They extract it into their own Dimraeth folder and press Play. Every
machine generates its own SteamID automatically.

### After a game update, or using "Verify integrity of game files"

Steam restores the original `steam_api64.dll` and the fix disappears. Copy the
payload again, or run the install script.

---

## Networking with ZeroTier

Both players need to be on the same ZeroTier network. One player creates it; both
join it. This is done once.

### The player who creates the network

1. Sign up or log in at <https://my.zerotier.com/>.
2. Click **Create A Network**.
3. Open it and copy the **Network ID** — a 16-character hex string such as
   `8056c3393f4e5d21`.
4. Leave **Access Control** on **Private**, so nobody joins without approval.
5. Send the Network ID to the other player.

### Both players

Open **PowerShell** and join, substituting the real Network ID:

```powershell
& "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" join <NETWORK_ID>
```

Expected output: `200 join OK`.

### The network owner

The other player now appears in the **Members** list on the network's web page,
with a checkbox beside them. **Tick it to authorise them.** Until you do, they are
connected to nothing.

### Both players — confirm

```powershell
& "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks
```

You want your network with the status **`OK`** and a `10.x.x.x` address:

```
200 listnetworks <nwid> <name> <mac> <status> <type> <dev> <ZT assigned ips>
200 listnetworks 8056c3393f4e5d21 my-net xx:xx:xx:xx:xx:xx OK PRIVATE ztxxxxxxxx 10.147.20.7/24
```

| Status | Meaning |
| --- | --- |
| `OK` | Connected. |
| `ACCESS_DENIED` | The network owner has not ticked your checkbox yet. |
| `REQUESTING_CONFIGURATION` | Still connecting; wait a few seconds and re-run. |

**Write down your `10.x.x.x` address** — you each need the other's.

### Prove the tunnel works

Before blaming the game, `ping` the other player's address:

```powershell
ping 10.147.20.42
```

You want four replies. If this fails, the game will never work. Check that both
statuses are `OK`, that the owner authorised the member, and that
`zerotier-cli info` reports `ONLINE`. Windows Firewall may block ICMP echo, which
is not fatal on its own since the game uses UDP and TCP — but see
[Windows Firewall](#windows-firewall) and make sure the game itself is allowed.

---

## Playing

1. **Both** players start Dimraeth **through Steam** and reach the main menu.
2. **The host** creates a world or starts a multiplayer session.
3. **The host then enters the multiplayer menu.** This matters: the emulator
   creates its network socket and starts announcing only once you are in the
   multiplayer menus. Sitting in the main menu it is silent, and that is normal.
4. **The other player** opens the multiplayer menu and looks for the host's world
   in the lobby list. It should appear within a few seconds.
5. Join.

Discovery broadcasts every 5 seconds, so give it about 10 seconds before
concluding it did not work.

### The real confirmation

Once you are in, look at the game's **party / member panel**:

> Does the other player's name appear in the member list?

That is what proves success. Seeing the lobby in the list is **not** enough on its
own — seeing the lobby means matchmaking worked; appearing in the party means the
peer-to-peer data channel and the game's network layer accepted you. During
development the member count reached 2 while the host's `Player.log` did not change
at all and the party list stayed empty. If you see the lobby but joining does
nothing, the network path is fine and the problem is elsewhere.

---

## Windows Firewall

The first time you enter multiplayer, Windows will prompt:

> **Windows Defender Firewall has blocked some features of this app**

Click **Allow access** and make sure **Private networks** is ticked. If you
dismiss it or click Cancel, multiplayer fails silently.

To fix it by hand:

1. Press <kbd>Win</kbd>, type **Allow an app through Windows Firewall**.
2. Click **Change settings**.
3. Find **Dimraeth** and tick **Private** (and **Public** if you are unsure about
   your network profile).
4. If it is not listed: **Allow another app…** → **Browse** → select
   `Dimraeth.exe` from your game folder.

ZeroTier needs to be allowed too; its installer normally handles that itself.

---

## How to tell it is working

| Signal | Meaning |
| --- | --- |
| Steam shows "Dimraeth — Running" | Normal. Steam launched the game. |
| The game's AppID is 480 | The emulator is loaded and being believed. |
| `listnetworks` shows `OK` and a `10.x.x.x` address | The virtual network is up. |
| `ping` to the other player's `10.x.x.x` answers | You can reach each other. |
| The host's world appears in the lobby list | Announcements are getting through. |
| The other player's name appears in the party panel | **Success.** |

The first two are automatic once the six files are in place. The rest is ZeroTier.

---

## Troubleshooting

### The lobby list stays empty

Work through these in order.

1. **Is the host in the multiplayer menu?** The emulator does not announce from the
   main menu. This is by design and it is the most common false alarm.
2. **Are you both on the same port?** `steam_settings\force_listen_port.txt` must
   say `47584` on **both** machines.
3. **Can you ping each other over ZeroTier?** If not, this is a ZeroTier problem,
   not a game problem.
4. **Use the directed-broadcast fallback.** Some virtual networks and some Wi-Fi
   setups do not carry broadcast. Put the **other player's** ZeroTier address in
   `steam_settings\custom_broadcasts.txt`, one per line, with no `#`:

   ```
   10.147.20.42
   ```

   Save, close the game completely, reopen. This file is sent as **unicast**, so it
   works where broadcast does not. Both sides do this, each listing the other.
5. **Restart both games.** The discovery port stays bound briefly after exit. Close
   both, wait about a minute, reopen.

### "Cannot create lobby" or stuck loading

Same cause: the UDP port is still held by a previous instance that has not fully
exited. Close the game, wait a minute, reopen.

### Antivirus flags `steam_api64.dll`

Expected. The emulator is unsigned, and an unsigned DLL replacing Steam's own gets
flagged heuristically. Add your Dimraeth folder to your antivirus exclusions.

### The game shows "Spacewar Player"

That is the default from `force_account_name.txt`. Edit that file and restart the
game.

### We both show up but cannot join each other's world

Check that both machines run the **same game version** — the game records its
version in the lobby data and refuses a mismatch. Steam updates everyone
automatically, so make sure neither of you is mid-update.

### It worked yesterday and not today

Most often the ZeroTier address changed, or the game updated. Re-run
`listnetworks`; if the address changed, redo the reachability test.

More detail, including how to read the diagnostic report, is in
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## Uninstall

Steam → right-click **Dimraeth** → **Properties** → **Installed Files** →
**Verify integrity of game files**.

That restores Valve's `steam_api64.dll`. The added files (`steam_appid.txt`,
`steam_settings\`) are harmless leftovers; delete them for a spotless folder. Or:

```powershell
pwsh -File .\tools\scripts\Install-OnlineFix.ps1 -Remove
```

---

## Diagnostics and tools

The Goldberg **release build writes no log at all** — its "debug" packages contain
only a Readme, and the release binary has no `PRINT_DEBUG` strings compiled in.
Diagnostics therefore observe the system from outside: the process, the sockets
and the traffic.

```powershell
pwsh -File .\tools\scripts\Get-Diagnostics.ps1 -Seconds 30
```

It writes `Dimraeth-OnlineFix-logs\diagnostic-<timestamp>.txt` inside the game
folder, covering:

| Section | Content |
| --- | --- |
| 1. Process | PID, memory, threads, and whether `steam` launched it |
| 2. Fix state | emulator DLL, AppID, port, persona, generated SteamID (validated) |
| 3. Sockets | proof the emulator owns UDP and TCP 47584 |
| 4. Game logs | multiplayer state from both `Player.log` and `Player-prev.log` |
| 5. ZeroTier | network, IP, peers, MTU |
| 6. Packets | decodes the emulator's announce traffic on the wire |
| 7. Verdict | OK / WARNING per item |

The full toolset — the lobby harness, the packet sniffer and the rest — is
documented in [`tools/TOOLS.md`](tools/TOOLS.md).

### The emulator only announces in multiplayer

It broadcasts only once a **listen socket** exists, which happens when the game
enters its multiplayer menu. In the main menu there is nothing to announce, so it
stays quiet and the diagnostic reports "not announcing". **That is expected.** To
see traffic, create or host a lobby and run it again.

### Capturing without stealing the game's port

The game binds `0.0.0.0:47584`, which blocks any later wildcard bind on that port.
Windows still allows a **specific-address** bind (`127.0.0.1`, `10.x.x.x`) on the
same port, and because the emulator broadcasts to every interface those sockets
receive a copy. That is what `dev\src\CapSpecific\CapSpecific.cs` does. An earlier
version bound `0.0.0.0` and reported "no announce" even while a server was running
— a false negative worth remembering.

---

## Repository layout

```
.
├─ package/                  What you copy into the game folder
│  └─ Dimraeth_Data\...      the six files
├─ tools/
│  ├─ scripts/               optional PowerShell helpers (install, launch, diagnose, test)
│  └─ bin/                   built C# executables (gitignored)
├─ dev/
│  ├─ src/                   C# sources for the tools
│  └─ packaging/             build.ps1, make-package.ps1, player README
├─ docs/
│  ├─ HOW-IT-WORKS.md        the emulator and the protocol, in detail
│  ├─ TESTING.md             what was measured, and what was not
│  ├─ TROUBLESHOOTING.md     symptom-driven fixes
│  └─ archive/               full research trail and upstream source excerpts
├─ .gitignore
├─ LICENSE
└─ README.md
```

Only `package/` is needed to use the fix. Everything else is tooling, evidence, or
documentation.

### Building the tools

```powershell
pwsh -File .\dev\packaging\build.ps1
pwsh -File .\dev\packaging\make-package.ps1
```

The tools are plain C# console programs compiled with the **classic .NET Framework
`csc.exe`**. The .NET 10 Roslyn compiler refuses to run on Windows builds without
full CET support (`error: Your Windows doesn't fully support CET`), so the sources
are written in C# 5 style — no local functions, no tuples.

---

## Technical details

**Identity.** On first run the emulator generates a random SteamID64 for the
machine and stores it in `%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt`.
It is sent in the clear in the discovery announcements. You never need to touch it,
and you must never copy it between machines — the emulator keys peers by SteamID,
so two machines sharing one identity cannot connect.

**Ports.** The emulator binds **UDP and TCP 47584**. UDP carries the discovery
announcements (a broadcast every 5 seconds plus directed unicast); TCP is used for
the connection handshake. Only one process per machine can own UDP 47584 — start a
second copy and it falls back to 47585 and loses sight of the first, which is why
the quickest fix for a stale lobby is to close the game and wait a minute.

**Two ids per announce.** Each announcement carries both Goldberg's internal
connection key (`0x0130 0001…`, shown as `key=`) and the sender's real SteamID64
(`0x0110 0001…`, carried in `Announce.ids`). They are easy to confuse, and the
distinction matters when reading a packet capture. `docs\TESTING.md` has the full
decode.

**No Valve binary is redistributed.** The original `steam_api64.dll` is not in this
repository. `Install-OnlineFix.ps1` makes its own backup inside the game folder the
first time it runs, and Steam's *Verify integrity of game files* restores the
original regardless.

---

## Limits

- The emulator has **no relay and no NAT traversal**. ZeroTier is what makes two
  machines see each other. Without it, internet play does not work.
- You cannot join lobbies hosted by players running the genuine Steam version.
- The Steam client always shows the game as Dimraeth; AppID 480 exists only inside
  the emulator.
- Tested on one machine plus a real two-machine session over ZeroTier. What was and
  was not verified is written out in [`docs/TESTING.md`](docs/TESTING.md).

---

## Credits and licence

- [Goldberg Steam Emulator](https://gitlab.com/Mr_Goldberg/goldberg_emulator) by
  Mr_Goldberg — **LGPLv3**. The emulator binary in `package\` is redistributed
  unmodified under that licence; a snapshot of the relevant upstream headers is in
  `docs\archive\goldberg-upstream\`.
- [ZeroTier](https://www.zerotier.com/) provides the virtual network.
- The scripts, C# tools and documentation here are provided as-is, without
  warranty, under the MIT licence (see [LICENSE](LICENSE)).

This repository contains **no game files**. It is an interoperability layer that
replaces a proprietary API implementation with an open-source emulator so a game
you already own can run without the Steam client. It circumvents no copy
protection, because Dimraeth has none.
