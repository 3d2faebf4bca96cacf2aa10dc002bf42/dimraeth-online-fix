# Troubleshooting

Run `tools\scripts\Get-Diagnostics.ps1` first and read the verdict section. It catches
most of what follows.

---

## The lobby list is empty

The most common symptom. Work through these in order.

1. **Is the host actually hosting?** Not in the main menu — hosting a world. The
   emulator only announces once a listen socket exists, which happens when the
   game enters multiplayer.

2. **Are both machines on the same ZeroTier network, with status `OK`?**

   ```powershell
   & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks
   ```

   The network is private: a new member stays invisible until the owner ticks
   "Auth" at <https://my.zerotier.com>.

3. **Can the machines reach each other?** `ping <other player's 10.x.x.x>`.

4. **Fallback — seed the peer address manually.** Some virtual networks do not
   carry broadcast traffic (Tailscale, for instance, documents no broadcast or
   multicast support). Create or edit:

   ```
   Dimraeth_Data\Plugins\x86_64\steam_settings\custom_broadcasts.txt
   ```

   Put the **other player's** ZeroTier IP in it, one per line, with no `#`:

   ```
   10.147.20.7
   ```

   Save, restart the game. Both sides do this, each listing the other. This file
   is sent as unicast, which is why it works where broadcast does not.

5. **Are both on AppID 480 and port 47584?** The emulator keys peer matching on
   both. A mismatch means mutual invisibility.

---

## "Not announcing" in the diagnostics

Expected when the game is in the main menu. The emulator has no listen socket
there and stays quiet on purpose. Create or host a lobby and run the diagnostics
again — section 6 should then show PING packets leaving through your ZeroTier
address.

If you are hosting and it still shows nothing, check that nothing else holds port
47584:

```powershell
Get-NetUDPEndpoint | Where-Object { $_.LocalPort -eq 47584 }
```

---

## The emulator is not on port 47584

It walks upward (`47585`, `47586`, …) when the port is taken, which breaks
discovery because peers broadcast to 47584. Find the offender, close it, and wait
for `TIME_WAIT` to clear (up to ~2 minutes) before relaunching.

---

## The game does not start, or Steam ignores the fix

**The fix is only active if `steam_api64.dll` in the game folder is the emulator
(1,958,912 bytes).** Steam restores the original after a reinstall or a "Verify
integrity of game files". Re-run the installer.

Verify:

```powershell
(Get-Item "...\Dimraeth_Data\Plugins\x86_64\steam_api64.dll").Length
```

`1958912` means the fix is installed; `262944` means it is not.

---

## Two players cannot connect, or the member list misbehaves

Both players must have **different SteamIDs**. The emulator uses the SteamID as
the peer key, so identical IDs collide and cannot connect.

Each machine generates its own on first run. Check yours:

```
%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt
```

If two machines somehow ended up with the same one, delete that file on one of
them — a new ID is generated on the next launch.

**Never ship a `steam_settings\force_steamid.txt` inside a package meant for
several people.** That is exactly how the collision happens.

---

## Antivirus flags steam_api64.dll

The Goldberg emulator is unsigned, so some scanners object. Add the game folder to
your exclusions. This is an open-source Steam API emulator (LGPLv3), not malware.

---

## "Cannot create lobby" / stuck loading

Close both games, wait about a minute, and relaunch. The discovery port lingers
after the process exits. Confirm nothing else is holding 47584 in the meantime.

---

## A player joins the lobby but never appears in the party

This is the one case that cannot be confirmed from a single machine. Gather
evidence and open an issue:

1. `tools\scripts\Get-Diagnostics.ps1` on **both** machines, while both are in the
   lobby.
2. Both `Player.log` files.

Useful signals: whether the host's log shows any `Connection`/`Approved` lines,
whether the announce packets list growing `peers`, and whether both sides report
the same AppID and port.

---

## Restoring the game to normal

Steam → right-click Dimraeth → **Properties** → **Installed Files** →
**Verify integrity of game files**.

That restores the original `steam_api64.dll` without needing a backup. To also
remove the leftover text files:

```powershell
pwsh -File .\tools\scripts\Install-OnlineFix.ps1 -Remove
```
