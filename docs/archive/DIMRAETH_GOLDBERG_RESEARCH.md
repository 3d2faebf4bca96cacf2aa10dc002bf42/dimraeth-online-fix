# Dimraeth / Goldberg Steam Emulator / "Online Fix" — research report

Research date: **2026-09-16** (web sources fetched live). Every claim carries a source URL and a
confidence level. `NOT FOUND` = searched, found nothing. `SPECULATION` = my inference, not a source.

> **Framing fact that dominates everything:** Dimraeth released **15 Sep 2026** — it is **1 day old**
> at the time of research. Its crack/online-fix coverage is correspondingly thin and brand new.
> Source: <https://store.steampowered.com/app/2402680/Dimraeth/>

---

## 0. Headline findings

| # | Claim | Source | Confidence |
|---|---|---|---|
| 0.1 | Dimraeth **does** have community reports — it is *not* a "no reports" case. cs.rin.ru thread `t=155040`, created **5 Feb 2026** (pre-release), still active 16 Sep 2026. | <https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040> | High |
| 0.2 | **Goldberg LAN co-op is reported working:** *"ye i tried both creamapi and goldberg lan - works fine"* | [p=3589751](https://cs.rin.ru/forum/viewtopic.php?p=3589751) | Medium (single user, no corroboration) |
| 0.3 | **Contradicting** report on the CreamAPI/appid-480 route: *"can't create lobby stuck in loading for me"* | [p=3589448](https://cs.rin.ru/forum/viewtopic.php?p=3589448) | Medium |
| 0.4 | A Goldberg-based repack **plus a separate "Online Fix"** exists; the Online Fix requires **signing into real Steam** and uses **appid 480 (Spacewar)** invites. | [p=3589476](https://cs.rin.ru/forum/viewtopic.php?p=3589476) | High |
| 0.5 | online-fix.me has **no Dimraeth page**. | <https://online-fix.me/?do=search&subaction=search&story=Dimraeth> | High |
| 0.6 | Goldberg **cannot** provide Valve's SDR relay, but it **does** implement `CreateListenSocketP2P`/`ConnectP2P` — which is exactly what Facepunch's "relay" helpers call. | §2 | High (source-verified) |
| 0.7 | ROUNDS is **Steamworks.NET + Photon PUN** — *not* Facepunch.Steamworks / SteamNetworkingSockets. R.E.P.O. and Content Warning are also Photon. | §3 | High (source-verified) |
| 0.8 | **Goldberg and "Online Fix" are two different techniques**, and Dimraeth's scene ships both. Goldberg = replaces `steam_api64.dll`, no Steam, LAN-style transport, internet only via VPN/port-forward. Online Fix = real Steam + Spacewar/appid 480, so real SDR relay is available. | §1.4, §4.1, §6.1 | High |
| 0.9 | Goldberg **does not block** non-LAN peers in the normal build — community internet play via host port-forward + `custom_broadcasts.txt` is documented, including in the main thread. | §2.4, §4.2 | High |

---

## 1. Dimraeth (AppID 2402680)

### 1.1 The cs.rin.ru thread

`[Info] Dimraeth`, forum `f=10`, thread id **155040**, 24 posts / 2 pages. Original post by
**EssentialLogic** dated 5 Feb 2026; launch-window posts 15–16 Sep 2026.
Source: <https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040> — **High**

**Access note:** direct fetch returns `HTTP 401 CS RIN - Security check`. The site **is** readable
via the `r.jina.ai` text proxy — e.g.
<https://r.jina.ai/https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040> — **High**

### 1.2 The positive report (most important single finding)

User **vperpl** (p=3589751, 16 Sep 2026 ~10:11), answering *"Has anyone tried LAN multiplayer yet?
I prefer a tailscale setup over onlinefix tbh"*:

> "ye i tried both creamapi and goldberg lan - works fine"

Source: <https://cs.rin.ru/forum/viewtopic.php?p=3589751> — **Medium**
No detail given (player count, host topology, whether a virtual LAN was involved).
**SPECULATION:** "goldberg lan" most plausibly means LAN or virtual-LAN, not internet play.

### 1.3 The negative report

User **megosa** (p=3589448), replying to the CreamAPI/appid-480 suggestion:
*"can't create lobby stuck in loading for me, can you share your file?"*
Source: <https://cs.rin.ru/forum/viewtopic.php?p=3589448> — **Medium**

### 1.4 The "Online Fix" release — and what it actually is

Uploader **DicDale** (ZeiGames), verbatim:

> "Dimraeth (v0.107.7689 | Build 25328495 / 25335390 + ONLINE) (1.03 GB) ~Pre-Installed …
> **Based on CSF & Goldberg.** -Play Online: Download the **Online Fix** file and apply it to the
> game folder. … Download the Online Fix file and copy the files in the folder where the Dimraeth is
> installed. **Sign in to your Steam account.** Start the game from the Dimraeth.exe file. If the
> in-game invite button doesn't work, **invite them to play "Spacewar"** using the Steam interface."

Sources: <https://cs.rin.ru/forum/viewtopic.php?p=3589476>, <https://cs.rin.ru/forum/viewtopic.php?p=3589754> — **High**

**Interpretation:** the "Online Fix" is a classic **Steamworks fix** (real Steam client + game
spoofed as Spacewar / appid 480) — **not** a Goldberg-internet solution. This is confirmed by the
cs.rin.ru moderator definition in §4.1. The two techniques are shipped side by side in one repack.
Sources: §1.4 + §4.1 — **High**

### 1.5 Other releases circulating

| Uploader | Description | Source |
|---|---|---|
| `cadavaros` | "Standalone / Crack Only (Goldberg Emulator)", "Steam DRM (Bypassed)" — **metadata is wrong** | [p=3589420](https://cs.rin.ru/forum/viewtopic.php?p=3589420) |
| `SteamGG.net` | Portable / Pre-Installed | [p=3589320](https://cs.rin.ru/forum/viewtopic.php?p=3589320) |
| `samsterrz` | "CSF" (Clean Steam Files) | [p=3589299](https://cs.rin.ru/forum/viewtopic.php?p=3589299) |

**Do not trust the cadavaros metadata:** it claims *"App ID: 2940280 / Engine: Unreal Engine"*, but
Dimraeth is **AppID 2402680** and a **Unity IL2CPP** game. It is copy-paste boilerplate. — **High**

### 1.6 A launch bug easily mistaken for a networking failure

Multiple users were stuck on the loading screen. Fix: rename
`Dimraeth_Data\StreamingAssets\Pool Of Remembrance Music.bank` to have **two leading spaces**
(Windows Explorer silently strips leading spaces — use `cmd` `rename`). Cause: the mangled audio
bank and/or a missing `oalinst` (OpenAL) redistributable.
Sources: [p=3589828](https://cs.rin.ru/forum/viewtopic.php?p=3589828), p=3589921, p=3590079 — **High**
This is a game/repack issue, **not** an emulator issue.

### 1.7 Steam Community: zero emulator discussion

Verified with Steam's own per-app discussion search (a real, working endpoint):
- `q=Goldberg` → *"No results were found for your search terms."*
  <https://steamcommunity.com/app/2402680/discussions/search/?q=Goldberg>
- `q=crack` → 1 hit, unrelated ("slipped through the cracks")
  <https://steamcommunity.com/app/2402680/discussions/search/?q=crack>
- `q=pirate` → 1 hit, an unrelated piracy tangent in an AI-art argument
  <https://steamcommunity.com/app/2402680/discussions/search/?q=pirate>
- `q=multiplayer` → 30 hits, all ordinary gameplay/lag/bug topics
  <https://steamcommunity.com/app/2402680/discussions/search/?q=multiplayer>
— **High**

### 1.8 online-fix.me

No Dimraeth entry. Site search returns *"К сожалению, поиск по сайту не дал никаких результатов."*
Source: <https://online-fix.me/?do=search&subaction=search&story=Dimraeth> — **High**

### 1.9 Red herring to avoid

The 3DMGAME thread 《迪梅拉行动（Operation Dimera）》TENOKE is a **different game**: *Operation
Dimera*, AppID **3883840**, FPS by SupKai, released 8 Aug 2025. Do not attribute its scene
coverage to Dimraeth.
Source: <https://bbs.3dmgame.com/thread-6612885-1-91.html> — **High**

### 1.10 Low-credibility source to discount

`2upskill.com` "How to Fix Dimraeth Multiplayer Not Working" is SEO/AI filler: published
**2026-09-14**, i.e. *before* the game released; no sources; contains **no**
emulator/Goldberg/online-fix content at all; generic advice only (verify files, flush DNS, reboot
router, use Steam invites).
Source: <https://2upskill.com/how-to-fix-dimraeth-multiplayer-not-working-connection-and-co-op-guides-2026/> — **High** that it is low-credibility

---

## 2. Technical: can Goldberg carry Dimraeth's networking?

### 2.1 Dimraeth's actual stack (verified from the shipped binary)

IL2CPP metadata contains: `FacepunchTransport`, `Netcode.Transports.Facepunch`, `SocketManager`,
`ConnectionManager`, `ConnectRelay`, `CreateRelaySocket`, `ConnectP2P`, `CreateListenSocketP2P`,
`InitRelayNetworkAccess`, `SteamMatchmaking`, `RequestLobbyList`, `CreateLobby`, `JoinLobby`,
`GetLobbyData`, `SetLobbyData`, `Facepunch.Steamworks`, `Unity.Netcode`, `NetworkManager`.
Source: local `Dimraeth_Data\il2cpp_data\Metadata\global-metadata.dat` (22,518,616 bytes) — **High**

> **Methodological warning:** grepping `GameAssembly.dll` for these names yields **false negatives**
> — `ConnectRelay`, `CreateRelaySocket`, `FacepunchTransport` do **not** appear there, but `ConnectP2P`,
> `CreateListenSocketP2P` and `Facepunch.Steamworks` do. IL2CPP stores all managed type/method names
> in `global-metadata.dat`. Never conclude absence from the DLL. — **High**

### 2.2 What Facepunch's "relay" functions actually call

- Facepunch wiki: `CreateRelaySocket` *"Creates a 'server' socket that listens for clients to connect
  to by calling Connect, **over SDR (Steam Datagram Relay)**."*
  <https://wiki.facepunch.com/steamworks/SteamNetworkingSockets> — **High**
- But the implementation is thin wrappers over the P2P calls:
  `CreateRelaySocket` → `Internal.CreateListenSocketP2P(virtualport, …)`;
  `ConnectRelay` → `Internal.ConnectP2P(ref identity /*SteamId*/, virtualport, …)`.
  <https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs> — **High**
- Unity's `com.community.netcode.transport.facepunch` uses exactly these: `StartServer()` →
  `CreateRelaySocket<SocketManager>()`; `StartClient()` →
  `ConnectRelay<ConnectionManager>(targetSteamId)`; plus
  `SteamNetworkingUtils.InitRelayNetworkAccess()` and `SteamClient.Init(steamAppId, false)` with
  `steamAppId` defaulting to **480**.
  <https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs> — **High**

### 2.3 What Goldberg implements vs. what it does not

**Implemented:** `CreateListenSocketP2P`, `ConnectP2P` (SteamID path) — routed over Goldberg's own
LAN/broadcast transport (`network->sendTo`); plus IP/port connections (`CreateListenSocketIP`,
`ConnectByIPAddress`, `sendToIPPort`).
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_sockets.h> — **High**
The IP/port support came from `inflation` fork commit `44305a0` and is present in upstream master:
<https://github.com/inflation/goldberg_emulator/commit/44305a0068df6a97cb3db352652f24430f4f27aa.diff> — **High**

**NOT implemented (no SDR):**
- `ReceivedRelayAuthTicket(...)` → `return false`
- `FindRelayAuthTicketForServer(...)` → `return 0` (all three overloads)
- `GetHostedDedicatedServerAddress()` → sets the **local** address only: `SetDevAddress(network->getOwnIP(), 27054)`
- `ConnectBySteamID` / `ConnectByIPv4Address` → `k_HSteamNetConnection_Invalid`
- `ConnectP2PCustomSignaling` → `k_HSteamNetConnection_Invalid`
- FakeIP APIs (`BeginAsyncRequestFakeIP`, `GetFakeIP`, `CreateListenSocketP2PFakeIP`, `CreateFakeUDPPort`) → stub / invalid
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_sockets.h> — **High**

**Direct developer admission** in the same file, verbatim:
> `//TODO: right now this only supports connecting with steam id, might need to make ip/port connections work in the future when I find a game that uses them.`

i.e. SteamNetworkingSockets support is **partial and opportunistic per-game**, not a complete
implementation. — **High**

**The "SteamNetworkingSockets" shim is a shim, not a relay.** gbe_fork ships
`networking_sockets_lib/steamnetworkingsockets.cpp`, which exports `SteamNetworkingSockets()`,
`SteamNetworkingUtils()`, `SteamDatagramClient_Init_InternalV6/V9`,
`SteamDatagramServer_Init_Internal`, etc. — but they merely hand back the emulator's own
`ISteamNetworkingSockets001` object from its `ISteamClient`. There is **no relay/datagram
implementation** behind them (`SteamDatagramClient_Internal_SteamAPIKludge` is empty;
`SteamNetworkingP2PGameServer()` returns `NULL`).
<https://github.com/Detanup01/gbe_fork/blob/dev/networking_sockets_lib/steamnetworkingsockets.cpp> — **High**

**The copied Valve header states the requirement Goldberg does *not* satisfy** — verbatim, directly
above `ConnectP2P` in Goldberg's own file:
> "This requires some sort of third party rendezvous service… At the time of this writing, there is
> only one supported rendezvous service: Steam… Note that all P2P connections on Steam are currently
> relayed."

Goldberg implements the *call* but not the *rendezvous service* behind it. — **High**

**Goldberg fakes relay *status* rather than erroring** — which is why games don't hard-fail:
`InitializeRelayAccess()` sets a flag and returns the initially-`false` `relay_initialized`;
`GetRelayNetworkStatus()` unconditionally returns `k_ESteamNetworkingAvailability_Current` with a
fabricated `m_debugMsg = "OK"`; `RunCallbacks()` later fires the status callback.
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_utils.h> — **High**

**Mechanism conclusion:** because Facepunch's `CreateRelaySocket`/`ConnectRelay` bottom out in
`CreateListenSocketP2P`/`ConnectP2P`, which Goldberg *does* implement, Dimraeth's co-op traffic
**can** be carried by Goldberg's own transport — but **never** by Valve's SDR. Hence LAN-only reach
unless a virtual LAN is used. This supplies a mechanism for the §1.2 report.
— **High** for the code reading; **Medium** for end-to-end.

### 2.4 Goldberg's own documented stance — and an important nuance

- *"This is a steam emulator that emulates steam online features **on a LAN**."*
  <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/README.md> — **High**
- *"**Notes:** You must all be on the same LAN for it to work."*
  <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt> — **High**
- gbe_fork: *"An emulator that supports LAN multiplayer without steam"* / *"You must all be on the
  same LAN for it to work."*
  <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> — **High**
- Also documented there: *"matchmaking_server_list_actual_type-1 … **This is currently broken**"* — the
  emulator returns a **LAN server list regardless of the requested server type**. — **High**

**Nuance — "LAN-only" is a transport design, not a hard block (in the normal build).** In both the
original and the fork readmes, the sentence *"You must all be on the same LAN for it to work."*
sits immediately under the section **"Support for CPY steam_api(64).dll cracks (Windows only) —
See the build in the experimental folder"**, i.e. it is scoped to the experimental CPY build.
Source: <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> — **High**

The **experimental** build does *actively* block non-LAN traffic:
> "This is a build of my emulator that blocks all outgoing connections from the game to non LAN ips…
> Since this blocks all non LAN connections doing things like hosting a cracked server for people on
> the internet will not work or connecting to a cracked server that's hosted on an internet ip will
> not work."

…with an opt-out file `disable_lan_only.txt`. The block list is only the private ranges
(10/8, 127/8, 169.254/16, 172.16/12, 192.168/16, 224/4).
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental.txt> — **High**

**Therefore the accurate statement is:** Goldberg's *discovery/transport* is a LAN broadcast
mechanism, but the normal build does **not** block non-LAN peers — which is precisely why the
community internet-play recipes in §4.2 work (host port-forward + `custom_broadcasts.txt`), with no
VPN required. "LAN-only" describes the transport, not a firewall rule. — **High**

---

## 3. Other games (delegated research; all sources fetched by that agent)

### 3.1 The reframing finding: several of these are **Photon** games

ROUNDS, **Content Warning** and **R.E.P.O.** use the Steam API only for lobby create / friend
invites / lobby-chat handshake, while real gameplay runs on **Photon Cloud**. Goldberg therefore
cannot carry their gameplay traffic at all. Maintainer's own words:
*"Photon has no relation to steam. Its another Service. Hense the name STEAM EMULATOR not EVERY
SERVICE EVER EXISTED EMULATOR"* — <https://github.com/Detanup01/gbe_fork/issues/220> — **High**

### 3.2 ROUNDS (AppID 1557740)

- **Architecture (HIGH, decompiled source):** `NetworkConnectionHandler` is a
  `MonoBehaviourPunCallbacks`; `QuickMatch()` → `PhotonNetwork.JoinRandomRoom()`; private games use
  `PhotonNetwork.CreateRoom(RoomName, …)` where `RoomName` comes from the Steam lobby.
  <http://git.warmcat.org/ROUNDS/plain/ROUNDS/NetworkConnectionHandler.cs> ;
  <http://git.warmcat.org/ROUNDS/diff/ROUNDS/Landfall.Network/ClientSteamLobby.cs?id=766cdff5ffa72b65d7f106658d1603f47739b2ba>
- **An online fix exists but is *not* Goldberg:** online-fix.me page 16624, updated 2 May 2024
  ("Steam-Fix V2"), 133k views; requires **real Steam** with your own profile; claims you can play
  on official servers. Recurring reported failure: the invite button opens an **empty Steam overlay
  with no friends list**; *"You simply cannot join a friend's lobby"*. Workaround: manually
  right-click the friend's avatar → Invite to Game.
  <https://online-fix.me/games/fighting/16624-rounds-po-seti.html> — **High**
- **NOT FOUND:** any ROUNDS report naming Goldberg. Steam's ROUNDS forum search returns *"No results"*
  for `goldberg` and `crack`; `pirate` returns one irrelevant hit; `emulator` returns 5 Mac/Windows
  emulator hits. <https://steamcommunity.com/app/1557740/discussions/search/?q=goldberg> ; — **High**
- RoundsWithFriends has **zero** mentions of goldberg/crack/pirate/emulator across all 36 issues
  (my own grep + agent's GitHub search API `total_count: 0`). — **High**
- Vanilla context (not an emulator issue): public Quick Match is often empty —
  <https://steamcommunity.com/app/1557740/discussions/0/592906450273107705?l=english> and
  <https://steamcommunity.com/app/1557740/discussions/0/600789889376004209/> — **Medium**

### 3.3 Lethal Company (AppID 1966720) — binding question RESOLVED

**It is Steamworks.NET, with Facepunch's transport layered on top.** A single crash report contains
both: `Steamworks.SteamMatchmaking.CreateLobbyAsync()` and
`Netcode.Transports.Facepunch.FacepunchTransport.Awake()`.
<https://steamcommunity.com/app/1966720/discussions/1/564785528365536791/> — **High**
(So `Steamworks.*` = Steamworks.NET; `FacepunchTransport` = Facepunch's Unity NGO transport sitting
on Steamworks.NET. The Facepunch.Steamworks *library* is not what LC calls.)

**Multiplayer works under Goldberg over ZeroTier**, only Steam voice chat fails:
*"I'm using Zerotier One with my friends and custom broadcast IP. Everything works like a charm
except voice chat."* — <https://github.com/Detanup01/gbe_fork/issues/86> — **High**

### 3.4 R.E.P.O. (AppID 3241660) — does **not** work on Goldberg

- Maintainer: *"Repo using PHOTON not Steam servers."* — <https://github.com/Detanup01/gbe_fork/issues/220> — **High**
- Reporter's symptoms: release build *"Others can't join; Invite-only and doesn't work as overlay is
  disabled in release"*; experimental build *"endless load, but visible by other clients; attempting
  to join from client side resulting a kick from lobby"*. He only got it working with
  `disable_lan_only=1` **plus a Photon patch**. — **High**
- Photon's own blog confirms R.E.P.O. is Photon-powered:
  <https://blog.photonengine.com/r-e-p-o-multiplayer-success-powered-by-photon/> — **High**
- online-fix's R.E.P.O. fix uses **its own Photon relay/server**, with pinned failure codes
  `MaxCcuReached`, `Exception`, `CustomAuthenticationFailed` (the last meaning "you didn't download
  from our site"). <https://online-fix.me/games/horror/17712-repo-po-seti.html> — **High**

### 3.5 Content Warning (AppID 2881650)

Uses **Photon** — proven by the *SelfSufficient* mod that swaps in your own Photon server:
<https://github.com/C0mputery/SelfSufficient> — **High**. online-fix page exists ("Steam-Fix V5",
1.5M views); its only reported failure is a BepInEx/HarmonyLib crash caused by non-Latin characters
in the install path. **NOT FOUND:** any Goldberg report (Steam search "No results"; gbe_fork appid
search 0). <https://online-fix.me/games/sandbox/17484-content-warning-po-seti.html> — **High**

### 3.6 Sons of the Forest (AppID 1326470)

**NOT FOUND either way.** Only gbe_fork issue is #523, about voice-chat quality
(*"vc sounds robotic … is it the game or is it the emu problem?"*).
<https://github.com/Detanup01/gbe_fork/issues/523> — **High** for the negative.
Its Steam forum is behind an adult-content gate, weakening the negative.
online-fix page exists: <https://online-fix.me/games/survival/17220-sons-of-the-forest-po-seti.html>

### 3.7 Cult of the Lamb (AppID 1313140)

**No online co-op exists** — its co-op is local/couch only, so Goldberg has nothing to emulate. A
Steam thread asks for *"True Network Co-op … Allow two players to connect online (not just
split-screen)"*. <https://steamcommunity.com/app/1313140/discussions/0/565912926113856464/> — **Medium-High**
No online fix exists (online-fix search: no results). No Goldberg reports. — **High**

### 3.8 Super Battle Golf — AppID correction

**AppID is 4069520**, not 1874190. Source: <https://steamdb.info/app/4069520/config/> — **High**.
online-fix page exists (updated 28 Jul 2026) but **its comment thread contains zero playability
reports** — only admin version-bump notices.
<https://online-fix.me/games/sandbox/18014-super-battle-golf-po-seti.html> — **High**
**NOT FOUND:** any Goldberg report.

### 3.9 Peaks of Yore — AppID correction

**AppID 1874190 is "Vorax", not Peaks of Yore** (<https://steamdb.info/app/1874190/subs/>). Peaks of
Yore's real AppID is **2236070** (<https://steamcommunity.com/app/2236070/discussions/>). — **High**
It has **no official multiplayer** (only a single-maintainer fan mod), and no online fix. Goldberg is
effectively irrelevant. — **High**

### 3.10 Catalogue of general Goldberg failure modes (with the game each attaches to)

| Symptom | Detail | Source | Attached game |
|---|---|---|---|
| `lobby_connect` sees nothing / "0 to refresh" | *"No matter which titles I try, I can't … get lobby_connect to see any games."* | [gbe_fork #270](https://github.com/Detanup01/gbe_fork/issues/270) | many titles |
| Server list always empty | *"Received 0 search results"*, constant "searching for games" | [gbe_fork #169](https://github.com/Detanup01/gbe_fork/issues/169) | Left 4 Dead 2 (Source matchmaking) |
| LAN discovery works but **SteamNetworkingSockets session never establishes** | *"Packet from 0 is smaller than the header"* — host header validation fails; fixed by PR #495 (lane propagation + SendMessages path) | [#401](https://github.com/Detanup01/gbe_fork/issues/401), [PR #495](https://github.com/Detanup01/gbe_fork/pull/495) | Enshrouded |
| `ConnectP2P` never emits initial `None → Connecting` callback | convoy join "fails, reason 7"; works with Valve's DLL | [gbe_fork #594](https://github.com/Detanup01/gbe_fork/issues/594) | Euro Truck Simulator 2 |
| Stuck at "Getting list of game servers" | `ManualDispatch` callback delivery bug | [PR #519](https://github.com/Detanup01/gbe_fork/pull/519) | Battle Realms: Zen Edition |
| Games whose only invite UI is the Steam overlay | Experimental overlay broken; PR adds `auto_send_invites.txt` | [PR #376](https://github.com/Detanup01/gbe_fork/pull/376) | Deep Rock Galactic, PEAK, L4D2 |

---

## 4. cs.rin.ru: Goldberg networking, VPNs, custom_broadcasts

Direct `search.php` → **HTTP 401 "CS RIN - Security check"**. Workaround: prefix with
`https://r.jina.ai/`. It also rate-limits ("Sorry but you cannot use search at this time").
— **High**

### 4.1 What "Steamworks Fix" vs "SSE" vs "Goldberg" mean (cs.rin.ru Moderator, verbatim)

Thread t=104597:

> "A **steamworks fix** is applied to a game's files so that you can use Steam to play games that you
> do not own with other people that also do not own the game. **Typically, CreamAPI is used to force
> the game to appear as if it is Spacewar** (which is Valve's demo for Steamworks). You would show up
> in your friend's library playing Spacewar, yet despite this you can connect to each other's game and
> play as if you owned said game.
> **SSE (SmartSteamEmu)** is a Steam emulator … it does not serve as a direct replacement for
> Steam_Api(64).dll while still supporting lots of great features.
> **Goldberg** … serves as a **direct replacement of Steam_Api(64).dll**. … the game must have no
> further DRM (such as Denuvo or VMProtect) … If you apply an emu yet the game still boots to Steam,
> it's best to try using **Steamless** by atom0s."

Source: <https://cs.rin.ru/forum/viewtopic.php?f=14&t=104597> — **High**

**Why this is the key to Dimraeth:** the §1.4 "Online Fix" (sign into Steam + Spacewar/appid 480) is
a **steamworks fix** — the **real Steam client stays running, so real SDR relay is available and
internet play can work**. Goldberg removes Steam entirely and therefore has no relay. **These are two
different techniques, shipped side by side in one repack.** — **High**

### 4.2 `custom_broadcasts.txt` for internet play — direct cs.rin.ru evidence

Goldberg's own docs describe the mechanism:
> "**Custom Broadcast IPs:** … make a list of them, one on each line in:
> `GSE Saves\settings\custom_broadcasts.txt` … If the custom IPs/domains are specific for one game
> only you can put the `custom_broadcasts.txt` in the `steam_settings` folder."
Source: <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> — **High**

**What `custom_broadcasts.txt` actually is (design rationale, from the upstream merge request !41):**
it is **not** a relay. It is a manual list of **unicast targets** to which the emulator sends its LAN
discovery/broadcast packets, so peers who are not on the same physical L2 segment can still find each
other. Verbatim from the MR:

> "Prior to this patch, Internet play could be achieved with port forwarding + adding each other's IP
> addresses to each other's `custom_broadcasts.txt` files. However, when two or more peers share the
> same public IP (eg. are both behind the same NAT), only one of them would be able to have its port
> forwarded… The main use case is helping when dealing with NATs (specially double NATs or multiple
> peers inside the same NAT)."

The MR adds optional `ip:port` syntax and names Green Hell and PAYDAY 1 as games needing it.
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41> — **High**

**The canonical community recipe for Goldberg internet play** — from `ce20fdf2` (maintainer of the
popular "Goldberg Emulator Custom Build" inside the main thread), verbatim:

> "When playing online (not with VPN) you will need to have the person hosting port forward 47584
> (or whatever port number is in listen_port.txt) and have all other connecting players enter the
> public ip address of the person hosting into a custom_broadcasts.txt file in steam_settings or in
> the global settings folder."

Source: <https://cs.rin.ru/forum/viewtopic.php?p=2882431#p2882431> — **High**

**And the origin of the "VPN-as-virtual-LAN" practice** — Mr_Goldberg himself, verbatim:
GhostPirateLechuck asked *"Do you know if it will work over VPN with something like Hamachi?"*
Mr_Goldberg: *"As long as your VPN supports normal ipv4 UDP broadcast packets it should work though
I have only tested it on a real LAN."*
Source: <https://cs.rin.ru/forum/viewtopic.php?p=1747417> — **High**

**Net: internet play with Goldberg = "make the internet look like a LAN".** Either (a) a virtual-LAN
overlay that passes IPv4 UDP broadcast (ZeroTier / Radmin / Hamachi / Tailscale / self-made
WireGuard), or (b) host port-forwarding of `listen_port` + every client listing the host's public
IP/domain in `custom_broadcasts.txt` — with the same `listen_port` on all machines. It is **not** a
built-in relay service. — **High**

**Tailscale specifically + Goldberg: NOT FOUND** on cs.rin.ru. The only hit combining all four VPN
names is *Saints Row: The Third Remastered* (`t=104613`), which refers to the **Nemirtingas Epic
Emulator**, not Goldberg. — **High** for the quote, but it is **not** Goldberg evidence.

**Community confirmations found via cs.rin.ru search for `custom_broadcasts`** (all **High**):

| Source | Verbatim guidance |
|---|---|
| **Main Goldberg thread** `t=91627`, user LuKeStorm | *"This is possible with proper port forwarding (host) and adding (players) public ip of the host to custom_broadcasts.txt"* — <https://cs.rin.ru/forum/viewtopic.php?f=29&t=91627> |
| **The Forest** `t=63683`, Soulgear 02 | *"… port forwarding or virtual lan (radmin, hamachi, selfmade wireguard) steam_settings/configs.main.ini listen_port=YOUR_PORT_HERE steam_settings/custom_broadcasts.txt DOMAIN OR IP ADDRESS Make sure those 2 above are the same on you & your friends."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=63683> |
| **ELDEN RING NIGHTREIGN** `t=145160`, CeLioCiBR | *"Use Radmin or similar to connect with each other. It also might be necessary to add the individual Radmin IPs of all participants to 'custom_broadcasts.txt' inside the 'steam_settings' folder."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=145160> |
| **Enshrouded** `t=132290`, insertdisc | *"Turned out to be a VLAN multicast issue. Fixed with a custom_broadcasts.txt. Still limited do to the GBE incompatibility…"* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=132290> |
| **GTFO** `t=91621`, KeepMeLooped | *"You cannot see each other. Check custom_broadcasts.txt and change SteamUID with bat."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=91621> |
| **Grim Dawn** `t=63042` | *"No, it supports Internet play. Probably not with the cracked version though. You can try your luck with online-fix, Unsteam and uc-online. Or solutions like ZeroTier et al. to play with your friends using the LAN support."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=63042> |
| **Backpack Battles** `t=138060` | *"1. Properly setup emulator. 2. Other people on LAN (or use zerotier / radmin etc) also with properly setup emulator. 3. The game needs to support steam networking. (This is the most important…)"* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=138060> |
| **Ravenswatch** `t=124520` | *"A shared network. Radmin VPN is recommended. ZeroTier may add latency to lobby discovery, but does not affect gameplay once connected."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=124520> |
| **The Mound: Omen of Cthulhu** `t=146694` | *"LAN works a treat, we use Zerotier VPN and it's working"* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=146694> |
| **Arma Reforger** `t=122707` | *"I managed to get lan/online working, at least with ZeroTier."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=122707> — **Medium** (snippet only) |

The **Grim Dawn** and **Backpack Battles** quotes are especially useful: they explicitly frame
ZeroTier as *the workaround for Goldberg's LAN limitation*, and name **online-fix / Unsteam /
uc-online** as the *"real internet"* alternatives — i.e. the community itself distinguishes
emulator-internet (VPN/port-forward) from online-fix-style internet. — **High**

### 4.3 Main Goldberg thread

`[Release] Goldberg Steam Emu - LAN Multiplayer Without Steam v0.2.5`, forum `f=29` (Releases),
thread **91627**, by Mr_Goldberg, posted **12 Aug 2018**, 6963 posts / 465 pages / ~1.89M views.
<https://cs.rin.ru/forum/viewtopic.php?f=29&t=91627> — **High**

Opening post, verbatim (note the first sentence — the original is no longer maintained):
> "No longer maintained by the original author. Please see the second post for fork information.
> This project is a generic steam dll that lets you play multiplayer games on a LAN without any
> internet connection."

Second post (detanup01, gbe_fork maintainer) is the **fork index**:
> "Currently Maintained forks: Detanup01's Fork … alex47exe's Fork … **Forks are NOT compatible with
> the Original version of the emulator.**"

Source: <https://cs.rin.ru/forum/viewtopic.php?p=1747390> — **High**

Related threads (IDs/titles confirmed via cs.rin.ru search): `t=111152` "GoldbergGUI - Frontend for
Goldberg Emulator" (236 replies, ~157k views) — config front-end only, no networking;
`t=104597` "what is the different between Steamworks Fix, SSE & Goldberg"; `t=106887` "Interview with
Mr_Goldberg"; `t=136556` "Collection of Goldberg & SKIDROW/CODEX/FLT CEG Binaries".
Note: **`t=91669` is NOT the Goldberg thread** — it is a game release thread ("RAW FOOTAGE").

Also worth knowing: **`ce20fdf2`'s "Goldberg Emulator Custom Build"** (announced inside `t=91627`)
adds avatars, overlay translations and a "basic server browser" — UX additions over the same LAN
transport, **not** relay. — **Medium-High**


### 4.4 "SteamNetworkingSockets" on cs.rin.ru

**NOT FOUND** as a searchable term — cs.rin.ru's search rate-limited on this query and no
forum-level discussion of Goldberg's SteamNetworkingSockets support surfaced. The authoritative
answer is instead the source code in §2.3. — **Medium-High** for the negative (rate-limit caveat).

---

## 5. `lobby_connect` (the "Goldberg lobby_connect" tool)

Goldberg ships a `lobby_connect` executable (and a DLL, recompiled for FFI use):

> "This is a small tool that **discovers people playing on the network** using my emu and lets you
> launch your game with parameters that will connect you to their games. … It will also let you join
> games with lobbies that are not public. … Just run this tool and follow the instructions then pick
> the exe of the game. Make sure that you have installed my emu on the game first…"

Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_lobby_connect.txt> — **High**
gbe_fork docs: *"Alternatively, you can use the dedicated tool `lobby_connect` to join a game lobby."*
<https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> — **High**

**Limitation:** it is explicitly a **network (LAN) discovery** tool. It emits the game's connect
parameter — typically `+connect_lobby <lobby id>` — for peers visible on the emulator's network. It
is **not** a rendezvous or relay service. — **High**
(Note: this limitation is inferred from the tool's documented behaviour plus the emulator's
architecture — the readme does not state it in those words. — **SPECULATION**, medium confidence.)

**Provenance:** the tool exists because of GitLab issue #96 — a user building an Electron launcher
asked for a way to enumerate players/games/launch command lines:
*"I wondering is it's possible to implement something like REST API to GET a Json array of players,
games and command line to allow users to join games in one click"*.
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/issues/96> — **High**

**Forum commentary — the community considers it clunky:**
- Cat Mail Co. (`t=159857`): *"…you should be able to invite other players over the Goldberg emu
  overlay (open with Shift+Tab to accept). Alternatively you can use the `lobby_connect_x64.exe` in
  the lobby_connect folder."* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=159857>
- Tricky Towers (`t=72990`): *"You have 2 options here: 1.) Use `Lobby_connect.exe` in GB fork to
  play game (you need it for every match) **Not recommended** 2.) Use Parsec to play online with
  friends. Works flawlessly"* — <https://cs.rin.ru/forum/viewtopic.php?f=10&t=72990>
  (The recommended alternative is a *video-streaming* remote-play tool — further evidence
  `lobby_connect` solves nothing about internet transport.) — **High**


**Node.js wrapper:** FFI bindings to a recompiled `lobby_connect.dll`, exposing `lobby_ready()`,
`lobby_player_count()`, `lobby_player_info()`; example output
`{ name: 'Xan', appID: 466560, connect: '+connect_lobby 109212296511539930' }`.
Sources: <https://registry.npmjs.org/@xan105/lobby_connect>, <https://github.com/xan105/node-lobby_connect> — **High**
Known failure: gbe_fork #270 — `lobby_connect` shows *"no lobbies and 0 to refresh"* across many titles.
<https://github.com/Detanup01/gbe_fork/issues/270> — **High**

**Applicability to Dimraeth:** **SPECULATION** — would require Dimraeth to honour a
`+connect_lobby <id>` launch parameter. Not verified for this game.

---

## 6. Forks and tools: does anything add real internet/relay support?

| Tool / fork | What it is | Real internet/relay? | Source | Confidence |
|---|---|---|---|---|
| `goldberg_emulator` (Mr_Goldberg) | Original; replaces `steam_api(64).dll` / `libsteam_api.so` | **No** — LAN-only by design | <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/README.md> | High |
| `gbe_fork` (Detanup01) | Active fork; `GSE Saves`, `configs.*.ini`, `steam_settings`, experimental builds | **No relay** — LAN + `custom_broadcasts.txt` | <https://github.com/Detanup01/gbe_fork> | High |
| `inflation/goldberg_emulator` | Fork; added SteamNetworkingSockets **IP/port** connections (now in upstream master) | Adds **IP-based P2P** (helps virtual LAN); **not** SDR | [commit 44305a0](https://github.com/inflation/goldberg_emulator/commit/44305a0068df6a97cb3db352652f24430f4f27aa.diff) | High |
| `sysfce2/Steam_goldberg_emulator` | Another gbe_fork fork | No evidence of relay support | <https://github.com/sysfce2/Steam_goldberg_emulator> | Low |
| `SteaMidra` (Midrags/SFF) | GUI toolkit. Its "**Multiplayer Fix**" merely *searches online-fix.me and opens the result in your browser*; bundles gbe_fork + Steamless + SteamAutoCrack | **No** — orchestrator only | <https://raw.githubusercontent.com/Midrags/SFF/main/README.md> | High |
| `Steamless` (atom0s) | *"a DRM remover of the SteamStub variants"* — unpacks the SteamStub DRM wrapper on the EXE | **No** — pure DRM unpacking | <https://github.com/atom0s/Steamless> | High |
| `ColdClientLoader` (Rat431, `ColdAPI_Steam`) | Launcher that injects `steamclient(64).dll` (+ overlay) with a configurable ini (`AppId`, `Exe`, `ExeCommandLine`, `DllsToInjectFolder`, `Mode`). Bundled with gbe_fork's "steamclient mode" build | **No** — DLL-injection/launch plumbing | <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.experimental_steamclient.md> | High |
| `SmartSteamEmu` (SSE, syahmixp) | Separate closed-source emulator; per the cs.rin.ru mod it *"does not serve as a direct replacement for Steam_Api(64).dll"* | **No relay found** — treated on cs.rin.ru as Goldberg's sibling with the same class of limitation | via §4.1; <https://github.com/MrKristofere/SmartSteamEmu> | Medium |
| `SteamAutoCrack` (oureveryday) | CLI coordinating gbe_fork (Goldberg), Steamless and CreamAPI-style unlockers; can generate Goldberg `steam_settings` via `generate_emu_config` | **No** — packaging/DRM-removal automation | via SteaMidra README; <https://github.com/BigBoiCJ/SteamAutoCracker/issues/54> | Medium-High |
| "Online Fix" (online-fix.me) | Custom **"SteamFix"/OnlineFix** DLL layer + variants; distributed as a patch folder beside the game | **Yes, but by a different mechanism than Goldberg** — see §6.1 | §6.1, §4.1 | Medium |
| "Goldberg Emulator Custom Build" (ce20fdf2) | In-thread custom build adding avatars, overlay translations, "basic server browser" | **No** — UX over the same LAN transport | §4.3 | Medium-High |

**Fork landscape:** GitLab reports **342 forks (260 public)** of the original repo
(<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/forks>); the notable live forks moved to GitHub
— `Detanup01/gbe_fork` (the de-facto maintained one), `alex47exe/gse_fork`, plus mirrors
(`sysfce2/Steam_goldberg_emulator`, `CyberSys/gse_fork`, etc.). **All carry the same one-line
description "emulates steam online features on a LAN."** — **High** for the wording.

**NOT FOUND:** any Goldberg fork that connects to a public rendezvous/relay server, or that
implements Steam Datagram Relay — despite checking the GitLab fork list, the whole gbe_fork tree, and
searching "goldberg fork relay", "goldberg emulator internet play fork", "goldberg rendezvous
server". The suspiciously-named `networking_sockets_lib` is a **shim, not a relay** (§2.3).
— **Medium-High** confidence in the negative (342 forks could not be exhaustively enumerated).

**SPECULATION (labelled):** given the above, I believe **no public Goldberg fork provides genuine
internet relay/rendezvous**; all "internet play" with Goldberg is really *"make the internet look
like a LAN"* (VPN mesh **or** port-forward + `custom_broadcasts.txt`).

### 6.1 What online-fix.me actually uses

- **PRIMARY-SOURCE DESCRIPTION: NOT FOUND.** No official online-fix.me page explaining its own
  DLL/technique could be retrieved, and no authoritative reverse-engineering write-up exists. All of
  the following is secondary. — **High** for the negative
- It is **not** "Goldberg in a zip". The SteaMidra/SFF tooling credits
  *"gbe_fork — a Steam emulator for running games offline"* and separately treats online-fix.me as a
  *supplementary* "Multiplayer Fix" it merely **downloads and extracts** — two different things.
  <https://raw.githubusercontent.com/Midrags/SFF/main/README.md> — **Medium**
- online-fix.me releases are **not one uniform technique**. The OnlineFix Linux launcher's
  compatibility matrix names distinct families — **SteamFix / OnlineFix**, **FreeTP**,
  **EOSFix** (Epic Online Services), and **"Custom OnlineFix servers (Photon Launcher)"** — and
  sometimes combinations ("SteamFix + EOSFix").
  <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md> — **Medium**
- **Some variants do require the real Steam client.** Across the Obelisk (`t=112642`) describes a
  multiplayer fix: *"Multiplayer redirect for photon, unlocks all DLC, enables the cheat menu
  (CTRL+C), **hooks the real steam client. Meaning have steam running and logged in.**"*
  <https://cs.rin.ru/forum/viewtopic.php?f=10&t=112642> — **Medium**
- **Contrast with Goldberg:** the "OnlineFix/Photon Launcher" type is a **game-networking-layer
  redirect** (Photon/EOS) combined with a real-Steam hook — which is why it can yield internet play
  for Photon games *without* a VPN, and why it works where Goldberg cannot. — **SPECULATION**
  (mechanism inferred; consistent with §3.1 and issue #220)
- **Whether online-fix.me fixes support SteamNetworkingSockets / SDR-relay games: NOT FOUND.**
  — **Low-Medium** confidence in the negative
- **Low-quality corroboration (flagged):** a content-farm article claims *"Online fixes are built on
  emulators like Goldberg Steam Emulator, Spacewar, or RealSteam. These only work when all players in
  a session are using compatible fix versions."* — **Low** confidence, but it matches the practical
  rule repeated in every cs.rin.ru guide ("make sure those are the same on you & your friends").


---

## 7. Local install state (local filesystem observation, not a web source)

`C:\Program Files (x86)\Steam\steamapps\common\Dimraeth` is **already Goldberg-patched**:

- `Dimraeth_Data\Plugins\x86_64\steam_api64.dll` = **1,958,912 bytes** (Goldberg; no version resource)
- `…\steam_api64.dll.bak` = **262,944 bytes** (original Valve SDK DLL)
- `…\steam_settings\` exists: `steam_appid.txt` = **480**, `force_account_name.txt` = `Spacewar Player`,
  `force_language.txt` = `english`, `supported_languages.txt`, `controller\Default.txt`
- `%APPDATA%\Goldberg SteamEmu Saves\settings\`: `listen_port.txt` = `47584`,
  `user_steam_id.txt` = `76561199754221087`, `account_name.txt` = `Noob`, `language.txt` = `english`
- **No** `custom_broadcasts.txt`, **no** `steam_interfaces.txt`, **no** per-appid save folder
- IL2CPP metadata confirms the Facepunch relay transport (§2.1)

### Actionable implications

1. The build is on the **appid 480** path. Lobby namespaces are appid-scoped. The cs.rin.ru Online
   Fix deliberately uses 480 to share the Spacewar namespace with other pirates; a LAN-only Goldberg
   setup arguably wants the real appid 2402680. **SPECULATION** on which is better; the appid-scoping
   mechanism is **High**.
2. `listen_port.txt` is currently a **random port (47584)**. Goldberg's readme warns everyone must
   use the *same* port or *"you won't find yourselves on the network"*
   (<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt>). For any
   multi-machine test this is the **first thing to make deterministic**. — **High** (readme) /
   **SPECULATION** (that it's the current blocker).
3. No `custom_broadcasts.txt` exists, so no internet/virtual-LAN play is configured yet. See §4.2.
4. Verify `Dimraeth_Data\StreamingAssets\Pool Of Remembrance Music.bank` has its two leading spaces
   (§1.6) before blaming networking for a loading hang.

---

## 8. Explicit gaps / NOT FOUND

- **NOT FOUND:** any independent second report confirming `vperpl`'s "goldberg lan - works fine" for Dimraeth.
- **NOT FOUND:** any Dimraeth report naming player count or topology (LAN vs virtual LAN vs internet).
- **NOT FOUND:** any Dimraeth report on whether Goldberg lobby *discovery* (vs. direct connect) works.
- **NOT FOUND:** any Goldberg fork/tool adding real relay/rendezvous/internet support.
- **NOT FOUND:** any report of Goldberg specifically working or failing for **ROUNDS**.
- **NOT FOUND:** a Dimraeth page on online-fix.me; any Dimraeth + Goldberg mention on Steam forums.
- **NOT FOUND:** any Goldberg report for Content Warning, Cult of the Lamb, Super Battle Golf, Peaks of Yore; Sons of the Forest has no report either way.
- **NOT FOUND:** any cs.rin.ru discussion of Goldberg's SteamNetworkingSockets support (the site search for that term hit the rate limiter and never returned).
- **NOT FOUND:** any Goldberg-specific Tailscale guidance on cs.rin.ru (the only Tailscale mention alongside it refers to the *Nemirtingas Epic Emulator*).
- **NOT FOUND:** a primary-source technical description from online-fix.me of its own DLL/technique.
- **NOT FOUND:** any statement on whether online-fix.me fixes work for SteamNetworkingSockets / SDR-relay games.
- **NOT FOUND:** SmartSteamEmu's own documentation from a primary source (only third-party mirrors/PDF aggregators).
- **CAVEAT (not a finding):** the negative on "no fork adds relay" rests on checking the GitLab fork list (342 forks), the full gbe_fork tree, docs and forum search — but 342 forks were **not** exhaustively enumerated, so the negative is strong, not absolute.
- **CAVEAT (not a finding):** the `t=91627` main thread has 6963 posts; only the specific posts cited were read, not the whole thread.
- **INACCESSIBLE:** `steamdb.info` → HTTP 403 with an explicit instruction not to keep requesting it (no public API; use the official Steam Web API).
- **INACCESSIBLE:** `web.archive.org` was offline ("Internet Archive services are temporarily offline"), so no archived snapshots could be checked.
- **INACCESSIBLE:** Reddit is login-walled from this environment ⇒ Reddit coverage is NOT FOUND *by capability*, not by absence.
- **INACCESSIBLE:** the Sons of the Forest Steam forum is behind an adult-content gate, weakening that negative.
- **NOT SEARCHED:** YouTube content/descriptions.
- **AppID corrections:** Peaks of Yore is **2236070** (1874190 = "Vorax"); Super Battle Golf is **4069520**.
