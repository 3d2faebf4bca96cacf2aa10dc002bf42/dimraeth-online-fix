# Testing - what was measured, and what was not

This document records exactly what was verified on real hardware, including the
false conclusions reached along the way. It exists so the project's claims can be
checked rather than trusted.

Test machine: Windows 10 (19045), RTX 4070 Ti, Dimraeth `buildid 25350646`
(game version `eDev 0.107.7694`).

---

## Verified

### The game has no Steam DRM

`Dimraeth.exe` (672,256 bytes) contains no `.bind` section, no `CSteamDRM`, no
`steam_api64.dll` import and no `SteamAPI_Init` string. Confirmed by direct byte
scan of the executable.

Consequence: the Steam client starts the executable but does not replace or
validate `steam_api64.dll`, which is what makes the whole approach work.

### The fix installs from 6 files and survives a Steam launch

Copying `package\` into the game folder and pressing **Play** in Steam:

| Check | Result |
| --- | --- |
| Game process parent | `steam` |
| Emulator sockets | UDP **and** TCP `0.0.0.0:47584` |
| Effective AppID (`ISteamUtils::GetAppID`) | **480** |
| `steam_api64.dll` after launch | 1,958,912 B, hash unchanged (Steam did not touch it) |
| Game memory footprint | ~1.6 GB rising to ~3.6 GB in-session |

The AppID stays 480 even though Steam injects `SteamAppId=2402680`, because the
emulator reads `steam_settings\steam_appid.txt` before consulting the environment.

### Each machine generates its own SteamID

Three clean emulator instances, with `%APPDATA%\Goldberg SteamEmu Saves` deleted
between runs, produced three distinct valid SteamID64s:

```
76561198011111111   (account 250853825)
76561198022222222   (account 251962018)
76561198033333333   (account 253070211)
```

Each was validated by arithmetic: account id positive and below 2^32, account
type 1 (individual), universe 1 (public).

Source confirmation from `dll/base.cpp`:

```c
static unsigned generate_account_id() {
    int a;
    randombytes((char *)&a, sizeof(a));   // RtlGenRandom on Windows
    a = abs(a);
    if (!a) ++a;
    return a;
}
CSteamID generate_steam_id_user() {
    return CSteamID(generate_account_id(), k_unSteamUserDefaultInstance,
                    k_EUniversePublic, k_EAccountTypeIndividual);
}
```

This is why no SteamID is shipped: it is per-machine and random, and a fixed one
would collide.

### The emulator announces over ZeroTier

With the game hosting, the announce traffic was captured and decoded:

```
[ 1] PING from 192.168.1.10:47584      appid=480  tcp_port=47584  key=85568397359096796  peers=0
[ 2] PING from 10.147.20.7:47584   appid=480  tcp_port=47584  key=85568397359096796  peers=0
[ 4] PONG from 10.147.20.7:47584   appid=480  tcp_port=47584  key=85568397359096796  peers=1

announces: 60   senders: 2  [192.168.1.10:47584, 10.147.20.7:47584]
```

Here `key=` is the summary column, which prints `source_id` -- the internal key,
not a SteamID64. That is explained in the next section.

`10.147.20.7` is the ZeroTier address, so the announce is leaving through the
interface a remote player would use.

#### Careful: an announce carries two different ids

This is the part that is easy to get wrong, and an earlier revision of this
document did get it wrong. Run `PacketSniffer --hex` and every field is dumped
verbatim, including the raw bytes:

```
. raw field 1 varint: tag=08 bytes=DC C7 DA C4 90 80 80 98 01 value=85568397359096796
. raw field 3 length: tag=1A lenbytes=1B len=27
    . field 2 bytes[18] = DC C7 DA C4 90 80 80 98 01 A5 D4 87 D2 96 80 80 88 01
    . field 3 varint bytes=E0 F3 02 value=47584
    . field 5 varint bytes=E0 03 value=480
```

The `field 2` blob is two varints back to back. Decoded below; the raw bytes are
from a real capture, while the sender's SteamID64 is shown as the placeholder
used throughout this document:

| where | raw bytes | decoded | what it is |
|---|---|---|---|
| `Common_Message.source_id` (field 1) | `DC C7 DA C4 90 80 80 98 01` | `85568397359096796` = `0x013000010896A3DC` | Goldberg's internal connection key |
| `Announce.ids[0]` | the same bytes again | the same value | the same internal key, repeated |
| `Announce.ids[1]` | `A5 D4 87 D2 96 80 80 88 01` | the sender's SteamID64, shape `0x0110 0001 xxxxxxxx` | **the real SteamID64** |

To sanity-check a decoder, these are the two encodings for the placeholder
identity and the internal key:

```
SteamID64     76561198000000001  = 0x01100001025E4C01  ->  varint 81 98 F9 92 90 80 80 88 01
internal key  85568397359096796  = 0x013000010896A3DC  ->  varint DC C7 DA C4 90 80 80 98 01
```

The second id, in the real capture, was byte-for-byte the value stored in
`%APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt` on the machine that
sent it -- so the real identity is in the packet, in the clear, and a decoder does
not need to undo anything. The two ids are easy to tell apart by their tail: a
real SteamID64 ends `... 80 80 88 01` (the `0x0110 0001 xxxxxxxx` shape: universe
1, individual account), while the internal key ends `... 80 80 98 01` and has the
`0x0130 0001` prefix.

What the internal key is derived from was **not** established. It is not a byte
swap and not an XOR of the SteamID; three different instances gave three values
with no consistent relationship to their SteamIDs, and the release build of the
emulator has its debug strings stripped, so the construction could not be read out
of the binary. For every practical purpose it does not matter: it is a stable
per-instance handle, and the real SteamID is always available in `Announce.ids`.

Practical consequence: when checking whether another player was seen, do **not**
compare `source_id` against `user_steam_id.txt`. Look for the second id in
`Announce.ids`, or simply search the raw capture for their SteamID64:

```powershell
# the other player's SteamID64, read from their own settings file
$their = "76561198000000001"
& .\tools\bin\PacketSniffer.exe --seconds 20 --listen-only --ports 47584 --log capture.txt
Select-String -Path capture.txt -Pattern $their    # a hit means they are announcing to us
```

`PacketSniffer` prints both kinds of id and labels them: `real steamid =` for the
SteamID64 and a `key=` column for the internal one. The final block of its report,
`real SteamIDs heard`, is the list to compare against `user_steam_id.txt`. The
internal key is stable per emulator instance and useful for telling instances
apart, but it is not a SteamID and will not match any settings file.

#### What a live capture showed

With the game in multiplayer and repeated captures over ZeroTier, three distinct
real SteamIDs appeared across the announces, one per participating emulator
instance, and the one belonging to the first machine matched its
`user_steam_id.txt` exactly. That is the check worth repeating when a connection
is not working: if the other player's SteamID never appears in a capture, their
announce is not reaching this machine, and the problem is the network path (see
`TROUBLESHOOTING.md`), not the game.
