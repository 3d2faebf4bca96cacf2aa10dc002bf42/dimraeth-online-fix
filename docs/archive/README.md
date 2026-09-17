# Research archive

Historical notes from building this fix. **Nothing here is needed to use it** —
these are the raw evidence behind [`../HOW-IT-WORKS.md`](../HOW-IT-WORKS.md) and
[`../TESTING.md`](../TESTING.md), kept so the reasoning can be checked rather than
taken on trust.

## Reports

| File | Covers |
| --- | --- |
| `DIMRAETH_NETWORKING_REPORT.md` | How the game talks to Steam: the Facepunch transport, the `ISteamNetworkingSockets` calls it makes, and why the emulator is compatible. |
| `REPORT_goldberg_steamclient_appid480.md` | The emulator itself: build layout, AppID 480, the `steamclient` variant, and how its configuration is resolved. |
| `DIMRAETH_GOLDBERG_RESEARCH.md` | Interface-by-interface comparison of what the game expects and what the emulator implements. |
| `_internet_coop_research.md` | Whether the emulator can work over the internet at all — its LAN-only design, and what `custom_broadcasts` actually does. |
| `steam-appid-480-sdr-report.md` | Steam Datagram Relay and why 480 does not give you free relay infrastructure. |
| `OnlineFix_Technical_Report.md` | How commercial "online fix" packages are built, for comparison. Concludes the architecture is convergent, not copied. |

## Source excerpts

`goldberg-upstream/` holds the upstream Goldberg files that the conclusions above
rest on — `dll/network.cpp` (the discovery and announce protocol),
`dll/steam_networking_sockets.h` (the modern P2P API the game actually uses, as
opposed to the legacy `SendP2PPacket`), the matchmaking interface, and the release
readmes that document `force_listen_port.txt` and `custom_broadcasts.txt`.

They are snapshots, not a build tree. For the current source and the licence, see
<https://gitlab.com/Mr_Goldberg/goldberg_emulator>.

## A note on their age

These were written during development and some earlier statements in them were
later corrected by measurement — most notably about SteamID encoding, which is
documented properly in [`../TESTING.md`](../TESTING.md). Where a report and
`TESTING.md` disagree, `TESTING.md` is the one that was verified on real captures.
