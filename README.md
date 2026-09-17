# Dimraeth — Online Co-op Fix

Play **Dimraeth** in co-op with a friend over the internet, without a Steam
lobby, without a dedicated server, and without owning the game twice.

You replace six files in your game folder. Then you both install **ZeroTier**,
which puts your two PCs on a private virtual network so the game can see each
other. Then one of you hosts and the other joins — exactly as if you were sitting
on the same LAN.

> **Scope:** this is a personal co-op setup shared between friends. It is not
> affiliated with the game's developers or with Valve.

---

## Table of contents

- [How it works](#how-it-works)
- [What you need](#what-you-need)
- [Step 1 — You do not need to back anything up](#step-1--you-do-not-need-to-back-anything-up)
- [Step 2 — Copy the files](#step-2--copy-the-files)
- [Step 3 — Launch the game](#step-3--launch-the-game)
- [Step 4 — Install ZeroTier](#step-4--install-zerotier)
- [Step 5 — Join the same network](#step-5--join-the-same-network)
- [Step 6 — Test that you can reach each other](#step-6--test-that-you-can-reach-each-other)
- [Step 7 — Play](#step-7--play)
- [Windows Firewall](#windows-firewall)
- [How to tell it is working](#how-to-tell-it-is-working)
- [Troubleshooting](#troubleshooting)
- [Removing the fix](#removing-the-fix)
- [Technical details](#technical-details)
- [Licence](#licence)

---

## How it works

Dimraeth uses Steam only for **multiplayer matchmaking and peer-to-peer
connections**. It has no Steam DRM — nothing in `Dimraeth.exe` checks that you own
the game. That means the Steam client will happily start the game no matter which
`steam_api64.dll` sits next to it.

So we swap that one DLL for an open-source reimplementation of the Steam API
(the [Goldberg Steam Emulator](https://github.com/mr_goldberg/goldberg_emulator)),
re-badged as **Steam AppID 480 (Spacewar)**. The emulator pretends to be Steam: it
answers every Steam call the game makes, generates a unique identity for your
machine, and broadcasts a "who is here" announcement on your local network so that
other copies of the emulator can find each other.

That last part is the catch: the emulator only looks for peers on the **local
network**. It has no relay servers and no NAT traversal of its own. Two PCs behind
different routers cannot see each other's broadcasts.

**ZeroTier solves exactly that.** It creates a virtual Ethernet segment between
your machines and gives each one an IP address on it. Broadcast traffic — which is
what the emulator uses for discovery — flows across it just like on a real LAN.

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

## What you need

| Requirement | Notes |
|---|---|
| Dimraeth installed through Steam | The fix replaces files inside its folder. |
| Windows 10 or 11 | Tested with the x64 build of the game. |
| ZeroTier One | Free, about 10 MB. Both players install it. |
| The same game version | The game checks version compatibility when joining a world. |
| About 10 minutes | Most of it is ZeroTier setup, and you only do it once. |

You do **not** need:

- a Steam copy of the game for the second player;
- to disable your antivirus permanently (see [Windows Firewall](#windows-firewall));
- to forward any port on your router.

---

## Step 1 — You do not need to back anything up

You do not need to save the original `steam_api64.dll`. If you ever want the game
back to normal, Steam restores it:

> Steam → right-click **Dimraeth** → **Properties** → **Installed Files** →
> **Verify integrity of game files**

That single button undoes everything on this page. There is nothing to back up by
hand.

---

## Step 2 — Copy the files

Both players do this on their own PC.

1. Find your Dimraeth folder. In Steam: right-click **Dimraeth** →
   **Manage** → **Browse local files**. By default it is:

   ```
   C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\
   ```

2. Copy the **`Dimraeth_Data`** folder from this repository into it.

3. Windows will ask whether to merge folders. Say **yes**, and accept the
   **Replace the file in the destination** prompt for `steam_api64.dll`. This is
   the one file that already exists and must be overwritten.

When you are done, the game folder must look exactly like this:

```
Dimraeth\
├─ Dimraeth.exe                              (untouched)
├─ UnityPlayer.dll                           (untouched)
├─ Dimraeth_Data\
│  └─ Plugins\
│     └─ x86_64\
        ├─ fmodstudio.dll                    (untouched)
        ├─ steam_api64.dll                   ← REPLACED with the emulator
        ├─ steam_appid.txt                   ← new
        └─ steam_settings\                   ← new
           ├─ steam_appid.txt
           ├─ force_listen_port.txt
           ├─ force_account_name.txt
           └─ custom_broadcasts.txt
```

That is **6 files: 1 replaced and 5 new.** No other game file is touched.

> **Do not** copy only `steam_api64.dll`. The four files in `steam_settings\`
> control the AppID, the network port and your display name. Without them the
> emulator falls back to defaults, and if your default port differs from your
> friend's, you will never find each other.

### What each file does

| File | Value | Purpose |
|---|---|---|
| `steam_api64.dll` | 1,958,912 bytes | The emulator. Replaces Valve's DLL. |
| `steam_appid.txt` | `480` | AppID the game is told it is running as. |
| `steam_settings\steam_appid.txt` | `480` | Same value. The emulator reads this one first, so it must exist too. |
| `steam_settings\force_listen_port.txt` | `47584` | The discovery port. **Both players must use the same one.** |
| `steam_settings\force_account_name.txt` | `Spacewar Player` | The name shown in the game's party / player list. Change it to whatever you like. |
| `steam_settings\custom_broadcasts.txt` | — | Optional. See [Troubleshooting](#the-lobby-list-is-empty). |

---

## Step 3 — Launch the game

Just press **Play** in Steam, exactly as you always have.

Do not launch `Dimraeth.exe` directly, and do not launch it from a file manager.
Going through Steam gives the process the right environment and keeps Steam's
playtime and overlay behaviour intact.

Steam will show **"Dimraeth — Running"**. That is correct and expected. Steam
still thinks it launched AppID 2402680; the emulator separately tells the *game*
that it is AppID 480. Steam never learns about 480 — the two never talk to each
other, which is exactly why this works.

At this point the game runs offline normally. Multiplayer comes next.

---

## Step 4 — Install ZeroTier

Both players do this.

1. Download and install **ZeroTier One** for Windows:
   <https://www.zerotier.com/download/>

2. Leave the service running. The installer starts it automatically; you can
   confirm it later with `zerotier-cli info`.

ZeroTier is a peer-to-peer VPN. Traffic between the two of you is end-to-end
encrypted and normally goes directly from one PC to the other. Free accounts
support up to 25 devices, far more than you need.

---

## Step 5 — Join the same network

One player creates the network; both players join it. Creating it takes two
minutes and only has to be done once.

### The player who creates the network

1. Sign up or log in at <https://my.zerotier.com/>.
2. Click **Create A Network**.
3. Open the new network and copy its **Network ID** — a 16-character hex string
   like `8056c3393f4e5d21`.
4. Leave **Access Control** set to **Private**. This means nobody can join without
   your approval.
5. Send the Network ID to the other player.

### Both players

Open **PowerShell** and run this, replacing the Network ID with the real one:

```powershell
& "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" join <NETWORK_ID>
```

Expected output:

```
200 join OK
```

### The player who created the network

The other player now appears in the **Members** list on the network's page, with a
checkbox on the left. **Tick it** to authorise them. Until you do, they are
connected to nothing.

### Both players — confirm you are in

```powershell
& "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks
```

You want to see your network with the status **`OK`** and a `10.x.x.x` address
assigned to it:

```
200 listnetworks <nwid> <name> <mac> <status> <type> <dev> <ZT assigned ips>
200 listnetworks 8056c3393f4e5d21 my-net xx:xx:xx:xx:xx:xx OK PRIVATE ztxxxxxxxx 10.147.20.7/24
```

- `OK` — you are connected.
- `ACCESS_DENIED` — the network owner has not ticked your checkbox yet.
- `REQUESTING_CONFIGURATION` — still connecting; wait a few seconds and re-run.

**Write down your `10.x.x.x` address.** You both need each other's.

---

## Step 6 — Test that you can reach each other

Before blaming the game, prove the tunnel works. Have each player send their
ZeroTier address to the other, then each of you runs:

```powershell
ping 10.147.20.42
```

(substituting the other player's address)

You want four replies. If `ping` fails here, **the game will never work** — fix
ZeroTier first:

- Is the other player's status `OK` in `listnetworks`?
- Did the network owner tick the authorisation checkbox?
- Is ZeroTier's service actually running? `zerotier-cli info` should report
  `ONLINE`.
- Windows Firewall may be blocking ICMP echo. That alone is not fatal, since the
  game uses UDP and TCP, but see [Windows Firewall](#windows-firewall) and make
  sure the game itself is allowed.

---

## Step 7 — Play

Now the actual game.

1. **Both** players start Dimraeth **through Steam** and get to the main menu.
2. **The host** creates a world or starts a multiplayer session.
3. **The host then enters the multiplayer menu** — the lobby or "join game"
   screen. This matters: the emulator creates its network socket and starts
   announcing only once you are in the multiplayer menus. Sitting in the main
   menu it is silent, and that is normal.
4. **The other player** opens the multiplayer menu and looks for the host's world
   in the lobby list. It should appear within a few seconds.
5. Join it.

Discovery is a broadcast every 5 seconds, so give it up to about 10 seconds before
concluding it did not work.

### The real confirmation

Once you are in, look at the game's **party / member panel**:

> Does the other player's name appear in the member list?

That is what proves success. Seeing the lobby in the list is *not* enough on its
own — seeing the lobby means matchmaking worked; appearing in the party means the
peer-to-peer data channel and the game's network layer accepted you. If you see
the lobby but joining does nothing, the network path is fine and the problem is
elsewhere — see [Troubleshooting](#troubleshooting).

---

## Windows Firewall

The first time you enter multiplayer, Windows will show a prompt:

> **Windows Defender Firewall has blocked some features of this app**

Click **Allow access**, and make sure **Private networks** is ticked. If you
dismiss this prompt or click Cancel, multiplayer will silently fail to connect.

If you missed the prompt, allow it by hand:

1. Press <kbd>Win</kbd> and type **Allow an app through Windows Firewall**.
2. Click **Change settings**.
3. Find **Dimraeth** in the list and tick **Private** (and **Public** if you are
   unsure about your network profile).
4. If Dimraeth is not listed, click **Allow another app…** → **Browse** → select
   `Dimraeth.exe` from your game folder.

ZeroTier needs to be allowed as well; its installer normally handles that itself.

---

## How to tell it is working

| Signal | Meaning |
|---|---|
| Steam shows "Dimraeth — Running" | Normal. Steam launched the game. |
| AppID inside the game is 480 | The emulator is loaded and being believed. |
| `zerotier-cli listnetworks` shows `OK` and a `10.x.x.x` address | The virtual network is up. |
| `ping` to the other player's `10.x.x.x` answers | You can reach each other. |
| The host's world appears in the lobby list | The emulator's announcements are getting through. |
| The other player's name appears in the party panel | **Success.** You are genuinely playing together. |

The first two are automatic once the six files are in place. The rest is ZeroTier.

---

## Troubleshooting

### The lobby list is empty

Work through these in order.

**1. Is the host actually in the multiplayer menu?**
The emulator does not announce anything from the main menu. This is by design, and
it is the single most common false alarm.

**2. Are you both on the same port?**
`steam_settings\force_listen_port.txt` must say `47584` on **both** machines.

**3. Can you ping each other over ZeroTier?**
If not, this is a ZeroTier problem, not a game problem.

**4. Use the directed-broadcast fallback.**
Some virtual networks and some Wi-Fi setups do not carry broadcast traffic. The
emulator can instead be told the other player's address directly.

Open `Dimraeth_Data\Plugins\x86_64\steam_settings\custom_broadcasts.txt` and add
the other player's ZeroTier address on its own line — no `#` in front:

```
10.147.20.42
```

Save the file, close the game completely, and reopen it. The other player does the
same with your address. This file is sent as **unicast**, so it works even where
broadcast does not.

**5. Restart both games.**
The discovery port stays bound for a short while after the game exits. Close both
games, wait about a minute, then reopen.

### "Cannot create lobby" / stuck on loading

Same cause as above: the UDP port is still held by a previous instance that has
not fully exited. Close the game, wait a minute, reopen.

### Antivirus flags `steam_api64.dll`

Expected. The emulator is unsigned, and an unsigned DLL that replaces Steam's own
gets flagged heuristically. Add your Dimraeth folder to your antivirus
exclusions. Windows Defender on its own normally does not object once you have
allowed the game through the firewall.

### The game shows "Spacewar Player" instead of my name

That is the name from `force_account_name.txt`. Edit that file and restart the
game.

### We both show up but cannot join each other's world

Check that the two of you are running the **same game version**. The game records
its version in the lobby data and refuses a mismatch. Steam updates everyone
automatically, so make sure neither of you is mid-update.

### It worked yesterday and not today

Most often the ZeroTier address changed, or the game updated. Re-run
`listnetworks` and compare the address; if it changed, redo
[Step 6](#step-6--test-that-you-can-reach-each-other).

---

## Removing the fix

Do this if you want the game back to normal, or before playing with strangers
online.

1. Steam → right-click **Dimraeth** → **Properties** → **Installed Files** →
   **Verify integrity of game files**.

Steam replaces the emulator DLL with the original and the game behaves normally
again. The extra files (`steam_appid.txt`, `steam_settings\`) are harmless
leftovers; delete them if you want a spotless folder.

---

## Technical details

For the curious, and for anyone debugging this.

**Why the missing Steam DRM matters.**
Dimraeth's executable has no `.bind` section, no `CSteamDRM`, and contains no
references to Steam at all. Without DRM, the Steam client merely *starts* the
process — it does not inject, validate or replace `steam_api64.dll`. So the DLL
you drop in is the one that loads, and the Play button keeps working.

**AppID 480.**
480 is Spacewar, a freely available test app. It is a community convention, not a
functional requirement. What actually matters is that **every player uses the same
AppID and the same discovery port**, because the emulator matches peers on those
two values.

**The identity is generated, not configured.**
On first run the emulator creates a random SteamID64 for your machine and stores
it in `%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt`. It is unique
per machine, it is sent in the clear in the discovery announcements, and you never
need to touch it. **Do not copy a SteamID from one machine to another** — the
emulator keys peers by SteamID, so two machines sharing one identity cannot
connect to each other.

**Ports.**
The emulator binds **UDP and TCP 47584**. UDP carries the discovery announcements
(a broadcast every 5 seconds, plus directed unicast); TCP is used for the
connection handshake. Only one process per machine can own UDP 47584 — start a
second copy of the game and it will fall back to 47585 and lose sight of the
first, which is also why the quickest fix for a stale lobby is to close the game
and wait a minute.

**ZeroTier's role.**
The emulator has no relay and no NAT traversal. ZeroTier provides the Layer 2
segment that makes broadcast work across the internet, and its traffic is
end-to-end encrypted. Nothing here opens a port on your router.

**Version note.**
The emulator bundled here is Goldberg Steam Emulator. Its release build writes no
log file of its own, which is why all troubleshooting above is based on external
observation — ZeroTier status, `ping`, and the game's party panel — rather than on
emulator logs.

---

## Licence

The configuration and documentation in this repository are provided as is, for
personal co-op use between friends, under the MIT licence.

`steam_api64.dll` is the **Goldberg Steam Emulator**, an independent open-source
project licensed under the **LGPLv3**. It is not my work and is not covered by the
MIT licence above. See <https://github.com/mr_goldberg/goldberg_emulator>.

Dimraeth is the property of its developers. This project is unofficial and is not
affiliated with or endorsed by them.
