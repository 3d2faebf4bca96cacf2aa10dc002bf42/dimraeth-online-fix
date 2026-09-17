# Internet co-op for Dimraeth (Steam 2402680) without a legitimate Steam license
Reverse-engineering research report. Every claim below is sourced; speculation is labelled **SPECULATION**; gaps are labelled **NOT FOUND**.

---

## 0. Ground truth established from this machine (primary evidence, not memory)

### 0.1 The install is already Goldberg'd, and already pinned to appid 480

| Fact | Value | Where |
|---|---|---|
| Engine | Unity **6000.0.61f1** (Unity 6), IL2CPP | `UnityPlayer.dll` ProductVersion; version string in `Dimraeth_Data/globalgamemanagers` |
| IL2CPP metadata version | **31** (`magic=0xFAB11BAF`) | first 8 bytes of `Dimraeth_Data/il2cpp_data/Metadata/global-metadata.dat` |
| `steam_api64.dll` | **1,958,912 bytes** = Goldberg (real stub is ~250-400 KB) | `Dimraeth_Data/Plugins/x86_64/` |
| Original API | backed up as `steam_api64.dll.bak`, **262,944 bytes** | same dir |
| `steam_appid.txt` | **`480`** — in BOTH `Plugins/x86_64/` and `Plugins/x86_64/steam_settings/` | same dir |
| Goldberg per-game settings | `steam_settings/force_account_name.txt` = `Spacewar Player`, `force_language.txt`, `supported_languages.txt`, `controller/Default.txt` | same dir |
| Goldberg global settings | `account_name=Noob`, `listen_port=47584`, `user_steam_id=76561199754221087` | `%APPDATA%\Goldberg SteamEmu Saves\settings\` |
| **No** `steamnetworkingsockets64.dll` | the standalone Valve SNS library is absent | `Plugins/x86_64/` listing |
| Relevant managed assemblies | `Facepunch Transport for Netcode for GameObjects.dll`, `Facepunch.Steamworks.Win64.dll`, `Unity.Netcode.Runtime.dll`, **`Unity.Multiplayer.Tools.Adapters.Utp2.dll`** | `Dimraeth_Data/ScriptingAssemblies.json` |
| Game shape | 1-8 player "seamless drop-in/drop-out co-op", host is a player, no dedicated servers | [Steam appdetails 2402680](https://store.steampowered.com/api/appdetails?appids=2402680) |

**Nothing net-new is needed to start**: everything relevant is already in place and reversible (`steam_api64.dll.bak`).

### 0.2 Every Steam call in this game goes through `steam_api64.dll` (decisive for technique 4)

String scan of `GameAssembly.dll` (the IL2CPP native output) found the P/Invoke targets:
`SteamAPI_SteamNetworkingSockets_v008`, `SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P`, `SteamAPI_ISteamNetworkingSockets_ConnectP2P`,
`SteamAPI_ISteamNetworkingSockets_ConnectP2PCustomSignaling`, `..._CreateListenSocketIP`, `..._ConnectByIPAddress`.
`global-metadata.dat` contains the literal **`steam_api64`** as the DllImport library name, and does **not** contain a `steamnetworkingsockets*` library name.

→ All Steam networking (flat API) is resolved from **`steam_api64.dll`**. That single DLL is the one and only native interception point (unless you go the IL2CPP/Harmony route, §3).

### 0.3 Exact code path the game exercises

Facepunch transport → Facepunch.Steamworks → flat exports:

```
FacepunchTransport.StartServer()  → SteamNetworkingSockets.CreateRelaySocket<SocketManager>()
                                  → ISteamNetworkingSockets::CreateListenSocketP2P(0, 0, nullptr)
FacepunchTransport.StartClient()  → SteamNetworkingSockets.ConnectRelay<ConnectionManager>(targetSteamId)
                                  → ISteamNetworkingSockets::ConnectP2P(identity=SteamID, 0, 0, nullptr)
FacepunchTransport.OnEarlyUpdate()→ SteamNetworkingUtils.InitRelayNetworkAccess()
```
Sources: [FacepunchTransport.cs](https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs), [Facepunch.Steamworks SteamNetworkingSockets.cs](https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs), [Facepunch wiki](https://wiki.facepunch.com/steamworks/SteamNetworkingSockets.CreateRelaySocket).
The transport connects **by SteamID**, never by IP: `steamAppId` default is literally `480`, with the in-source comment *"Technically you're not allowed to use 480, but Valve doesn't do anything about it so it's fine for testing purposes."* Same conclusion from Unity's own SNS transport README: *"The Steam networking sockets APIs address via CSteamID, not IP/Port."* ([README](https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.steamnetworkingsockets/README.md))

### 0.4 What Goldberg does with those calls (this is why it is LAN-only)

Goldberg implements `CreateListenSocketP2P` / `ConnectP2P` itself inside `dll/steam_networking_sockets.h`, tunnelling a **custom protobuf handshake** (`CONNECTION_REQUEST` / `CONNECTION_ACCEPTED` / `DATA`) over its own peer layer. There is no SDR, no rendezvous service, no Valve backend.
Sources: [dll/steam_networking_sockets.h](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_sockets.h) (contains the author's own TODO: *"right now this only supports connecting with steam id, might need to make ip/port connections work in the future"*).

Discovery is the single choke point, in `dll/network.cpp`:
* `send_announce_broadcasts()` every **5 s** (`BROADCAST_INTERVAL`) sends a protobuf `Announce(PING)` to
  1. `INADDR_BROADCAST` = **255.255.255.255**,
  2. the **per-interface subnet broadcast** of every adapter (`get_broadcast_info`, Windows `GetAdaptersInfo`),
  3. **every entry in `custom_broadcasts.txt`, as unicast**;
* the announce carries **`tcp_port`**; the receiving side records `ip_port` from `recvfrom()` and then connects **TCP** to `sourceIP : announced_tcp_port`;
* reliable traffic runs over **TCP**; unreliable over UDP; heartbeats every 10 s on TCP.
* `DEFAULT_PORT` is **47584** and both UDP and TCP bind it (falling back +i up to 1000).
Sources: [dll/network.cpp](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.cpp), [dll/network.h](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.h).

**Critical consequence (important, easy to get wrong):** Goldberg's *IP-address* connect path also depends on discovery. `Networking::sendToIPPort()` only iterates already-known `connections` and matches on `tcp_ip_port.ip`; if no announce from that IP has arrived, nothing is sent. So `ConnectByIPAddress` under Goldberg is **not** a shortcut around the broadcast/`custom_broadcasts.txt` requirement.
**And:** because the TCP port is taken from the announce payload (the *local* bind port), a port-forward must map **external 47584 → internal 47584**; forwarding WAN:12345→LAN:47584 would make the peer dial `publicIP:47584`. (**Inference from the code — label: SPECULATION, though strongly grounded in `handle_announce()`.**)

---

## 1. LAN-over-WAN VPNs — which ones carry Goldberg's broadcast?

Goldberg broadcasts to `255.255.255.255` and to the *subnet broadcast* of every local adapter. Whether that survives a VPN is exactly the question, so here is the documented answer per product.

| VPN | Layer | Does it carry 255.255.255.255 / L2 broadcast? | Source | Confidence |
|---|---|---|---|---|
| **Radmin VPN** | **L2 / TAP (Ethernet)** | **Yes on Windows** — its NDIS miniport "advertises itself as the preferred interface" for UDP `255.255.255.255` and multicast `224.0.0.0/4`. On Linux you must add routes yourself. | [radmin-vpn-linux README, "LAN games don't see other peers"](https://github.com/baptisterajaut/radmin-vpn-linux) | **High** (reverse-engineered primary doc) |
| **Hamachi** | **L2** | **Yes** — "Hamachi creates a single broadcast domain between all clients. This makes it possible to use LAN protocols that rely on IP broadcasts for discovery… Hamachi currently handles tunneling of IP traffic including broadcasts and multicast." | [Wikipedia: LogMeIn Hamachi](https://en.wikipedia.org/wiki/Hamachi_(software)) | **High** (tertiary but explicit) |
| **ZeroTier** | **L2 Ethernet emulation (VL2)** | **Yes, in principle** — "Broadcast (Ethernet ff:ff:ff:ff:ff:ff) is treated as a multicast group to which all members subscribe. It can be disabled at the network level." Caveats: a **multicast limit** is set on the controller; **ad-hoc networks (`ff…`) permit only IPv6 unicast — no broadcast**. One contested field report (Android) of 255.255.255.255 not reaching peers, to which a maintainer replied "We *technically* support multicast and broadcast on Android, but we can't do things outside what the OS permits." | [ZeroTier protocol docs](https://docs.zerotier.com/protocol/), [ZeroTierOne #884 + comments](https://github.com/zerotier/ZeroTierOne/issues/884) | **Medium-High** (docs high; end-to-end Goldberg+ZeroTier report **NOT FOUND**) |
| **Tailscale** | **L3, point-to-point (WireGuard)** | **NO.** Official: "Currently there is no support for broadcast or multicast due to the point-to-point nature of the connections." Staff: "Tailscale doesn't create a broadcast domain." | [Tailscale forum thread 156](https://forum.tailscale.com/t/broadcast-multicast-support/156) | **Very High** |
| **NetBird** | **L3 (WireGuard)** | **Effectively no.** Open feature request "Multicast not working" (#1435, since Jan 2024, still open, updated 2026-07): user can ping but LAN broadcast discovery fails. | [netbird#1435](https://github.com/netbirdio/netbird/issues/1435) | **High** |
| **SoftEther VPN** | **L2 (has explicit L2 bridge)** | **Yes** — "The multiple LANs … will be logically connected as a single Ethernet network (**broadcast domain segment**) once they are connected via bridge connections." Heavier setup (server + virtual hub + local bridge). | [SoftEther manual 10.5](https://www.softether.org/4-docs/1-manual/A/10.5) | **High** (but untested with Goldberg → **NOT FOUND**) |

### The universal fallback that makes L3 VPNs work anyway
Because `custom_broadcasts.txt` sends the announce as **plain unicast UDP**, discovery does not *need* broadcast at all — it needs the peer to be reachable by unicast. So:

> **Put the peer's VPN IP into `custom_broadcasts.txt` and even Tailscale/NetBird become viable.**

* Mechanism: line in `<game>/steam_settings/custom_broadcasts.txt` (highest priority) or `%APPDATA%\Goldberg SteamEmu Saves\settings\custom_broadcasts.txt` (global). Format is **one IP or domain per line**, optionally `ip:port`; the shipped example is exactly:
  `192.168.3.255 / 127.8.9.10 / 192.168.66.99 / 192.168.7.99 / removethis.test.domain.com`
  Source: [custom_broadcasts.EXAMPLE.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/files_example/steam_settings.EXAMPLE/custom_broadcasts.EXAMPLE.txt), [Readme_release.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt) ("If you want to set custom ips (**or domains**) which the emulator will send broadcast packets to").
* Both peers should list each other (the announce is how each side learns the other's SteamID→IP mapping).
* Whether this is *documented* for Tailscale specifically: **NOT FOUND**. That it must work given the code is **SPECULATION** but very well grounded (unicast UDP over Tailscale/WireGuard is ordinary routed traffic).
* gbe_fork (the maintained Goldberg fork) keeps the identical feature and still says *"You must all be on the same LAN for it to work."* ([gbe_fork release README](https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md))

### Practical ranking for technique 1
1. **Radmin VPN** — best-documented fit for broadcast-based LAN discovery; the online-fix community material also lists "Emulador LAN (Radmin/Hamachi)" as the stable non-fix method ([citygame explainer](https://citygame.com.ar/how-to-use-online-fix/)). Free, Windows, zero config, ~"Medium" difficulty.
2. **ZeroTier** (a normal controller-managed network, **not** an ad-hoc `ff…` network; leave broadcast enabled; 2-4 members so the multicast limit is irrelevant).
3. **Hamachi** (documented single broadcast domain; free tier limits apply).
4. **Tailscale / NetBird** — only *with* `custom_broadcasts.txt`.
5. **SoftEther** — most robust L2, most setup.

No Dimraeth-specific "worked for me" report was found for any of these: **NOT FOUND**.

---

## 2. Goldberg `custom_broadcasts.txt` over the open internet (port forwarding)

**This is documented to work — by the Goldberg contributor who wrote the feature.**

Direct quote from merge request !41 (ptremor, "Custom broadcasts improvement to add support for specifying ports"):

> "Prior to this patch, **Internet play could be achieved with port forwarding + adding each other's IP addresses to each other's custom_broadcasts.txt files.** However, when two or more peers share the same public IP (eg. are both behind the same NAT), only one of them would be able to have its port forwarded. … Players sharing the same public IP just gotta change their `listen_port.txt` ports to distinct values and forward those ports. Then, all peers just gotta update their own `custom_broadcasts.txt` file specifying the other ones addresses (including their respective ports). BOOOM. It just works. **I've manually tested it thoroughly with some friends and can assure it in fact does work.**"

Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41>

### Exact recipe
| Item | Value |
|---|---|
| File (per-game, highest priority) | `<Dimraeth>\Dimraeth_Data\Plugins\x86_64\steam_settings\custom_broadcasts.txt` |
| File (global) | `%APPDATA%\Goldberg SteamEmu Saves\settings\custom_broadcasts.txt` (gbe_fork: `GSE Saves`) |
| Content | host: client's public IP (or domain), one per line. Client: host's public IP. Optional `IP:PORT`. |
| Ports to forward | **UDP 47584 AND TCP 47584** (Goldberg's `DEFAULT_PORT`; UDP for announce/unreliable, TCP for reliable + heartbeats) |
| Direction | map **WAN 47584 → LAN 47584** (see §0.4 inference) |
| Port override | global `listen_port.txt`; per-game/forced `force_listen_port.txt` in `steam_settings/` (both documented in the release readme; MR !41 uses the older name `listen_port.txt`). All peers must use the **same** port unless each peer's port is given explicitly in `custom_broadcasts.txt`. |
| Multi-player NAT caveat | only one peer per public IP can own 47584; give peers behind the same NAT distinct ports and list them as `ip:port`. |
| The stated nudge | the official release readme literally still says *"Edit this file if you want to change the UDP/TCP port the emulator listens on (**You should probably not change this because everyone needs to use the same port or you won't find yourselves on the network**)"*. |

Sources: [Readme_release.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt), [MR !41](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41), [config hierarchy gist](https://gist.github.com/ElektroStudios/1bf5c35f819afc21ef18f0a77b8d9092) (documents `force_listen_port.txt` lives in the per-user/per-game settings dir, and is not supported in the global dir).

**Honest reliability:** documented and manually tested by the feature author, but for a **2-peer, host-forwarded** setup. Requirements: at least the host has a real public IP (**fails behind CGNAT**), firewall rules, and the *receiving* side must also be able to reach the other peer's port for the TCP leg in some topologies. Difficulty: low-medium (one config line + one router rule), but topology-sensitive. Confidence: **High** for the mechanism, **Medium** for reliability in a given household.

---

## 3. Replacing / redistributing the transport on an IL2CPP build

Reality check: you cannot "drop in" a new Unity package — the C# is compiled into `GameAssembly.dll`. There are three physically possible interception layers.

### 3a. Native: shim `steam_api64.dll` (no mod loader at all)
Replace the flat `SteamAPI_ISteamNetworkingSockets_*` exports with your own implementation (raw UDP + relay / ENet / GameNetworkingSockets), forwarding every other export to Goldberg.
* Precedent that this architecture works: Goldberg itself ships a **`steamnetworkingsockets64.dll`** target that is nothing but a forwarding shim for the SNS flat exports, ~200 lines — [steamnetworkingsockets.cpp](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/steamnetworkingsockets.cpp), [CMakeLists.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/CMakeLists.txt).
* Export-forwarding skeleton: [857seif/atuo-DLL-Proxy-generator](https://github.com/857seif/atuo-DLL-Proxy-generator); full export list in [Steamworks.NET `steam_api_flat.h`](https://github.com/rlabrecque/Steamworks.NET/blob/master/CodeGen/steam/steam_api_flat.h).
* Cost: you must reimplement connection state, reliable/unreliable messaging, fragmentation, `SteamNetConnectionStatusChangedCallback_t` dispatch, and `ReceiveMessages`. Est. 1–3k LOC. No off-the-shelf project does this: **NOT FOUND**.

### 3b. Managed: BepInEx 6 (IL2CPP) + HarmonyX — the realistic modding route
Dimraeth is **Unity 6 / IL2CPP metadata v31**.
* **BepInEx 6 bleeding-edge** publishes `BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.<n>` builds continuously; latest observed is **build 788 (2026-09-01)** with Cpp2IL/Il2CppInterop bumped (Il2CppInterop 1.5.3 in be.777). [builds.bepinex.dev/projects/bepinex_be](https://builds.bepinex.dev/projects/bepinex_be)
* Metadata coverage is version-specific and moves: BepInEx issue **#1274** shows *metadata version 39 unsupported* (newer than v31) — i.e. v31 is inside the supported window, but do not assume forever. [BepInEx#1274](https://github.com/BepInEx/BepInEx/issues/1274)
* **MelonLoader is currently the weaker option for Unity 6**: open issue #1100 "[Bug]: Unity 6 (6000.2.10f1) - Metadata 31.1 - LibCpp2ILInitializationException". [MelonLoader#1100](https://github.com/LavaGang/MelonLoader/issues/1100)
* Confidence: **Medium-High** that BepInEx 6 BE will inject into this game; **must be tested**.

What you would patch (all in `FacepunchTransport`):
| Patch | Effect | Difficulty |
|---|---|---|
| `StartServer()`: `CreateRelaySocket` → `CreateNormalSocket(NetAddress.Any(port))` | host listens on **IP:port** instead of SteamID | Small |
| `StartClient()`: `ConnectRelay(targetSteamId)` → `ConnectNormal(NetAddress.From(hostIp, port))` | client dials **IP:port** directly → works over plain internet with **one UDP port forward, no VPN, no broadcast** | Small |
| Reroute `targetSteamId`/lobby plumbing to carry a host IP string | lobby "join" must deliver an IP instead of a SteamID | Medium |
| Or: swap `NetworkManager.NetworkConfig.NetworkTransport` to Unity's `UnityTransport` and `SetConnectionData(ip, port)` | bypasses Steam entirely | Medium |

**Strong hint that Unity Transport is already in the build:** `Unity.Multiplayer.Tools.Adapters.Utp2.dll` is present in `ScriptingAssemblies.json`, implying the Unity Transport (UTP2) package ships with the game. (**SPECULATION** — presence of the profiler adapter strongly suggests it, but I did not verify at runtime.)

* Important caveat under Goldberg: `ConnectNormal`/`ConnectByIPAddress` still routes through Goldberg's connection table, which is only populated by discovery (§0.4). So with Goldberg, the IP path buys you nothing extra. The IP path pays off either (a) over **real Steam** (where Valve's backend resolves it), or (b) with your own native shim (3a).

### 3c. LAN-only mod
**NOT FOUND.** No Dimraeth mod exists at all (game is brand new / Early Access). Any "LAN mod" would have to be the 3b patch written from scratch.

### 3d. Tools that hook `SteamNetworkingSockets` to build a "virtual LAN"
**NOT FOUND.** I found no project that traps `SteamNetworkingSockets` P2P and redirects it to a LAN/relay. The closest analogues are the emulators themselves (Goldberg/gbe_fork/OnlineFix) and Steam-client hooks (§6), none of which do what was described.

---

## 4. Custom Steam Datagram Relay / self-hosted relay — does a shim project exist?

**Answer: the library exists, but it is not a drop-in, and no shim project exists. NOT FOUND for the shim.**

* **GameNetworkingSockets** (Valve, open source) implements the same API subset, has working reliable/unreliable messaging, fragmentation, encryption, and **P2P via ICE** — but:
  * *"some features are only available on Steam, such as Steam's authentication service, signaling service, and the SDR relay service"* and *"the SDR support code is not opensource."* [README](https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README.md)
  * P2P requires **three services you must run yourself**: a pluggable **signaling service**, **STUN**, and **TURN** relay fallback. There is a `trivial_signaling_server.py` example and a `test_p2p` test. *"LAN beacon support, so P2P connections can be made even when signaling is down"* is an unimplemented roadmap item. [README_P2P.md](https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README_P2P.md)
  * **`CreateListenSocketP2P` in the OSS build requires `nSteamConnectVirtualPort = -1`** — verbatim in the header comment that Goldberg copied: *"In the open-source version of this API, you must pass -1 for nSteamConnectVirtualPort"*. A game calling `CreateListenSocketP2P(0)` therefore fails on GNS.
  * `ConnectP2P` with an **identity type `k_ESteamNetworkingIdentityType_SteamID`** is meaningless outside Steam: GNS cannot resolve a SteamID to anything.
  * Real-world confirmation that `ConnectP2P` is bound to Valve's backend: Facepunch issue #400 — a self-connect via `ConnectRelay` died with *"reason code 4003 (Bad cert: CA key is not known to us)"*. [Facepunch#400](https://github.com/Facepunch/Facepunch.Steamworks/issues/400)
* Therefore: **GNS cannot substitute for the game's transport without also changing the game to use IP identities** (i.e. combining §3a/§3b with §4).
* **No project was found** that proxies `steam_api64.dll` and redirects `SteamNetworkingSockets` flat exports to GameNetworkingSockets, ENet, or any custom relay. Closest artefacts, all *not* that:
  * Goldberg's own `steamnetworkingsockets.cpp` shim (forwards to the emulator, not to a relay);
  * [DLL proxy generators](https://github.com/857seif/atuo-DLL-Proxy-generator);
  * Steam-client hooks ([OpenSteamTool](https://github.com/OpenSteam001/OpenSteamTool), LumaCore/SteaMidra, GreenLuma) which hook `steamclient64.dll` IPC, not the flat API;
  * [FizzySteamworks](https://github.com/Dellacurtais/FizzySteamworks) — a *different* transport (Mirror) using Steamworks.NET; precedent for transport replacement, not a shim.
* **Verdict:** writing the shim is a genuine, bounded engineering project (architecture proven by Goldberg's own target); acquiring one off the shelf is **NOT FOUND**.

---

## 5. Splitting lobby (matchmaking) from transport (P2P)

Facts that decide this:
1. Both layers are **SteamID-keyed**: `JoinLobby(lobbyId)` for the lobby, `ConnectP2P(SteamID, virtualPort)` for the transport.
2. Goldberg implements lobbies over its own UDP/TCP layer ([dll/steam_matchmaking.h](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_matchmaking.h)) and **lobbies are discovered by the same announce mechanism** — README: *"Custom Broadcast ips: If you want to set custom ips (or domains) which the emulator will send broadcast packets to…"*; and the release readme still says *"You must all be on the same LAN."*
3. `targetSteamId` comes from the lobby / friend-invite layer (`OnGameLobbyJoinRequested`), so the client can only dial a SteamID it has *already* discovered.
4. Goldberg ships **`lobby_connect`** precisely to solve "start the game already pointed at a peer": *"This is a small tool that discovers people playing on the network using my emu and lets you launch your game with parameters that will connect you to their games… Most steam games also let you join lobbies in game without having started the game by starting the game with `+connect_lobby <lobby id>`."* — note it **discovers over the network**; it does not dial a public IP. [Readme_lobby_connect.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_lobby_connect.txt)

**Conclusion:** under Goldberg you *cannot* decouple the two by "faking lobbies locally and relaying only the P2P", because Goldberg's SteamID→connection map is populated **only** by the announce discovery. One discovery layer feeds both. The only real splits are:
* **(A) Keep Goldberg for both** and make discovery work over WAN → §1 VPN or §2 port-forward. This is the 1-line solution.
* **(B) Bypass Goldberg's networking entirely** at the managed layer (Harmony): patch `FacepunchTransport.StartClient/StartServer` to IP-based sockets and patch the lobby-join path to carry a host IP instead of a SteamID (technique 3b). Then a plain UDP port-forward **or** a UDP relay (e.g. a small socat/`n2n`/WireGuard-on-a-VPS setup) is all you need — no broadcast, no Steam, works behind CGNAT.
* **(C) Bypass at the native layer** (§3a) with your own `steam_api64` shim, which can implement SteamID→relay-endpoint mapping itself (e.g. SteamID → entry in a JSON config → your relay). Technically the cleanest "split", and the most work.

Existing tool that does this split for a Steam game: **NOT FOUND**. The nearest real-world thing is the OnlineFix ecosystem (§6), which replaces the whole Steam API + redirects to community servers; the explainer describes precisely this shape — *"the fix intercepts the call the game tries to make to Steam's servers … emulates a successful authentication response or redirects the connection to a peer-to-peer network or unofficial servers maintained by the community"*, and notes that *"a player with a legal copy is connected to the official Steam servers, [the fixed player] to an emulated/alternative network. They are two parallel worlds that do not cross."* ([citygame explainer](https://citygame.com.ar/how-to-use-online-fix/))

---

## 6. The appid-480 (Spacewar) route — real, documented, and the best option for this game

**Yes, it is real and it is actively maintained. It is the strongest technique available, because it gives you Valve's REAL lobbies, REAL Steam Datagram Relay, and therefore genuine internet co-op with no VPN, no port forwarding, and works behind CGNAT.**

### 6.1 The "plain" form — documented and confirmed by users
Steam Community guide **"Play Dark Souls PTDE Online 2024"** (Vector50cal, Nov 2023, last edited Jun 2024; comments: *"This is freaking incredible! Thank you for This!"*):

> 3. Create a text file called **"steam_appid.txt"** in the DATA folder … write **"480"** in it. **This will fool Steam into thinking that Dark Souls is a game called "Spacewar"; this will enable online functionality for Dark Souls.**
> 4. **Launch the game exe directly; do not launch through Steam.**
> 5. If your controller isn't working … Find "Spacewar" in your game library then click on Steam's controller support for the game …

Source: <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/>

This install is **already configured for exactly this** (`steam_appid.txt` = `480` twice, account name "Spacewar Player").

### 6.2 The modern, maintained form — `-onlinefix` client hook
* **OpenSteamTool** (open source, C++): *"**Online Fix** — Add `-onlinefix` to the Steam launch parameters to enable **480-based online play in games that use lobby matchmaking**. The current limitation is that only one such game can run at a time."* Its debug logs include `onlinefix.log` / `LOG_ONLINEFIX_*` described as **"Online fix (480 AppId spoofing)"**. [README](https://raw.githubusercontent.com/OpenSteam001/OpenSteamTool/main/README.md)
* **SteaMidra / SFF**: *"**LC Online Fix** — toggle `-onlinefix` on a chosen App ID in `localconfig.vdf` … **LumaCore handles the appid-480 redirect at launch so the overlay, Steam Input, and screenshots still tag the real game.**"* [README](https://raw.githubusercontent.com/Midrags/SFF/main/README.md)
* **Unsteam** (documented in the Chinese cracking guide, with an `unsteam.ini`): `real_app_id=<game appid>`, `fake_app_id=480`, run `unsteam_loader64.exe`, Steam client must be logged in, success indicator = **Steam status shows "playing Spacewar"**. The guide's own summary of the two strategies:
  * 在线联机 → **Unsteam / 480 spoof**, *"borrowing Steam's official networking"*;
  * 单机/局域网 → **GBE Fork (Goldberg)**: *"does not depend on the Steam client, but cannot do public internet matchmaking — LAN only."*
  Sources: [blog mirror](https://blog.syouiti.com/%E6%B8%B8%E6%88%8F%E7%A0%B4%E8%A7%A3%E6%8C%87%E5%8D%97/), original author [nite07](https://www.nite07.com/zh-cn/posts/game-crack-tutorial/)
* Steam's own SDR is what makes this valuable — Valve's hosted relay/backbone, no NAT punch needed ([SDR docs](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay); Facepunch transport routes over it per the [CreateRelaySocket wiki](https://wiki.facepunch.com/steamworks/SteamNetworkingSockets.CreateRelaySocket)).

### 6.3 Exact steps for Dimraeth
1. Restore the real library: rename `steam_api64.dll.bak` → `steam_api64.dll` (removing Goldberg). Goldberg and real Steam are mutually exclusive.
2. Keep `steam_appid.txt` = `480` next to it, and/or use the client-hook form if the shipped `FacepunchTransport` prefab hardcodes `steamAppId = 2402680` (the field exists and its C# default is 480, but the scene value is unknown → if step 4 shows the game reporting appid 2402680, use OpenSteamTool `-onlinefix` or Unsteam with `real_app_id=2402680`).
3. Start Steam, log in with any (free) account. Spacewar/480 is a free placeholder app every account can run.
4. Launch `Dimraeth.exe` **directly** (not through the Steam library) so Steam does not inject `SteamAppId=2402680`.
5. Verify: Steam friends-list status should read "Spacewar". Then create/join a lobby in game; friends doing the same land in the same 480 pool and connect over real SDR.

### 6.4 Honest caveats
* Requires the **real Steam client** and a (free) Steam account; this is "no license for Dimraeth", not "no Steam".
* The 480 pool is **shared with every other 480-spoofer** of every other game → stranger lobbies may appear; prefer invite/`+connect_lobby` with a private lobby.
* Whether a **legitimate Dimraeth owner** (real appid 2402680) can be in the same lobby as a 480-spoofer: the Spanish explainer says plainly **no** (parallel networks); the Chinese guide's phrasing ("联机对象不限破解玩家") implies yes. **Contradictory sources → treat as UNRESOLVED; for your purpose it does not matter, since all friends would use the same method.**
* Steam ToS / ban risk is low but non-zero (per the explainer: *"the risk is low, but not zero"*).
* Client-hook builds break on Steam client updates until the community re-ships signatures (OpenSteamTool re-fetches patterns for `steamclient64.dll`/`steamui.dll` on every launch precisely for this).
* The plain `steam_appid.txt` form may be defeated if the game's own `SteamClient.Init()` passes an explicit appid that overrides the file (Facepunch's `steamAppId` field) → that is exactly when you need the client hook.

---

## 7. Recommendation, ranked by (probability of success ÷ effort)

| Rank | Technique | Effort | Works behind CGNAT? | Internet quality | Documented for this exact stack? |
|---|---|---|---|---|---|
| **1** | **appid-480 via real Steam** (§6): restore `.bak`, keep `steam_appid.txt=480`, launch exe directly; escalate to OpenSteamTool `-onlinefix` / Unsteam if needed | ~15 min | **Yes** | **Best** (Valve SDR, ~real latency) | Yes for the mechanism; not for Dimraeth → **NOT FOUND** game-specific |
| **2** | **Radmin VPN** (or ZeroTier non-ad-hoc) + both peers; if clients don't appear, add the peer's VPN IP to `custom_broadcasts.txt` | ~20 min | Yes | Peer-to-peer, VPN-dependent | VPN broadcast documented; Goldberg+Radmin **NOT FOUND** |
| **3** | **Public-IP port forwarding** of UDP+TCP 47584 + each peer's public IP in `custom_broadcasts.txt` (§2) | ~30 min | **No** | Direct | Yes — MR !41, author-tested |
| **4** | **Tailscale/NetBird + `custom_broadcasts.txt`** to the peer's 100.x address | ~20 min | Yes | Good | Tailscale limitation documented; the workaround is **SPECULATION** |
| **5** | **BepInEx 6 (BE ≥777) + Harmony**: swap `ConnectRelay`→`ConnectNormal` and lobby SteamID→host IP (§3b) | Hours-days | Yes (with any UDP relay/forward) | As good as your relay | No prior art → novel work |
| **6** | **Native `steam_api64.dll` shim** implementing the SNS flat exports over your own relay (§3a/§4) | Days-weeks | Yes | As good as your relay | Architecture precedent only (Goldberg's own shim) → project **NOT FOUND** |

### Fastest decisive experiment (do this first, ~1 test)
Restore `steam_api64.dll.bak` → confirm `steam_appid.txt`=480 → start Steam logged in → run `Dimraeth.exe` directly → check whether Steam's friends list shows **"Spacewar"** and whether an in-game lobby can be created. If yes, technique 1 is solved today. If the game insists on 2402680, add OpenSteamTool's `-onlinefix`, which spoofs 480 at the Steam IPC layer.

---

## 8. Explicit NOT FOUND list
* Any off-the-shelf `steam_api64` proxy/shim that redirects `SteamNetworkingSockets` to GameNetworkingSockets / ENet / a self-hosted relay — **NOT FOUND**.
* Any project that hooks `SteamNetworkingSockets` to create a "virtual LAN" for Steam games — **NOT FOUND**.
* Any Dimraeth-specific mod, LAN mod, or co-op fix — **NOT FOUND**.
* Any confirmed report of Goldberg + Radmin/ZeroTier/Hamachi working for Dimraeth — **NOT FOUND**.
* Any documented Goldberg + Tailscale/NetBird report (broadcast is documented as unsupported; the `custom_broadcasts.txt` workaround is inference) — **NOT FOUND**.
* Any authoritative statement on whether a 480-spoofer can share a lobby with a legitimate owner in general — **NOT FOUND / contradictory sources**.

## 9. Source index
Goldberg: [README](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/README.md) · [Readme_release.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt) · [Readme_lobby_connect.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_lobby_connect.txt) · [dll/network.cpp](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.cpp) · [dll/network.h](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.h) · [dll/steam_networking_sockets.h](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_sockets.h) · [steamnetworkingsockets.cpp](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/steamnetworkingsockets.cpp) · [CMakeLists.txt](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/CMakeLists.txt) · [MR !41](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41) · [custom_broadcasts example](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/files_example/steam_settings.EXAMPLE/custom_broadcasts.EXAMPLE.txt) · [official site](https://mr_goldberg.gitlab.io/goldberg_emulator/) · [config-hierarchy gist](https://gist.github.com/ElektroStudios/1bf5c35f819afc21ef18f0a77b8d9092) · [gbe_fork release readme](https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md) · [DeepWiki usage guide](https://deepwiki.com/inflation/goldberg_emulator/1.2-usage-guide)
Transport: [FacepunchTransport.cs](https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs) · [Facepunch.Steamworks SteamNetworkingSockets.cs](https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs) · [Facepunch wiki](https://wiki.facepunch.com/steamworks/SteamNetworkingSockets.CreateRelaySocket) · [Facepunch #400](https://github.com/Facepunch/Facepunch.Steamworks/issues/400) · [Unity SNS transport README](https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.steamnetworkingsockets/README.md) · [Steamworks.NET flat header](https://github.com/rlabrecque/Steamworks.NET/blob/master/CodeGen/steam/steam_api_flat.h)
VPNs: [ZeroTier protocol](https://docs.zerotier.com/protocol/) · [ZeroTier L2 bridge](https://docs.zerotier.com/bridging/) · [ZeroTierOne #884](https://github.com/zerotier/ZeroTierOne/issues/884) · [Tailscale forum 156](https://forum.tailscale.com/t/broadcast-multicast-support/156) · [Radmin VPN Linux (reverse-engineered)](https://github.com/baptisterajaut/radmin-vpn-linux) · [Hamachi (Wikipedia)](https://en.wikipedia.org/wiki/Hamachi_(software)) · [NetBird #1435](https://github.com/netbirdio/netbird/issues/1435) · [SoftEther 10.5](https://www.softether.org/4-docs/1-manual/A/10.5)
Relay/modding: [GameNetworkingSockets README](https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README.md) · [GNS README_P2P](https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README_P2P.md) · [BepInEx BE builds](https://builds.bepinex.dev/projects/bepinex_be) · [BepInEx releases](https://github.com/BepInEx/BepInEx/releases) · [BepInEx #1274](https://github.com/BepInEx/BepInEx/issues/1274) · [MelonLoader #1100](https://github.com/LavaGang/MelonLoader/issues/1100) · [DLL proxy generator](https://github.com/857seif/atuo-DLL-Proxy-generator) · [FizzySteamworks](https://github.com/Dellacurtais/FizzySteamworks)
480 route: [Dark Souls PTDE 2024 guide](https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/) · [OpenSteamTool](https://raw.githubusercontent.com/OpenSteam001/OpenSteamTool/main/README.md) · [SteaMidra/SFF](https://raw.githubusercontent.com/Midrags/SFF/main/README.md) · [Chinese cracking guide (mirror)](https://blog.syouiti.com/%E6%B8%B8%E6%88%8F%E7%A0%B4%E8%A7%A3%E6%8C%87%E5%8D%97/) · [citygame online-fix explainer](https://citygame.com.ar/how-to-use-online-fix/) · [Steam SDR docs](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay) · [Dimraeth store data](https://store.steampowered.com/api/appdetails?appids=2402680)
