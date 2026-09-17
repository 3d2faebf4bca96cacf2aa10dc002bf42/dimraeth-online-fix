# Dimraeth (Steam AppID 2402680) — Online-Fix Feasibility: Technical Report

> **Note on provenance.** This is the **regenerated** copy. The original was written to
> `…\Dimraeth\_dsh_onlinefix\notes\DIMRAETH_NETWORKING_REPORT.md` and was **deleted when the parent agent cleaned
> up the `_dsh_onlinefix` staging tree** (along with four parallel-agent reports). Content is unchanged apart
> from this note and the addition of §1.4.
>
> **Method.** Every load-bearing claim is either (a) read directly from source code or from files on this
> machine, or (b) cited to a URL. Anything unverified is explicitly labelled **SPECULATION** or **NOT FOUND**.
> Findings from three parallel research agents are integrated, with their mutual conflicts **adjudicated in
> §9.2** rather than averaged.

---

## 0. Executive verdicts

| # | Question | Verdict |
|---|---|---|
| 1 | Which Steam API does `FacepunchTransport.cs` use? | **The NEWER `ISteamNetworkingSockets` P2P API** — `CreateListenSocketP2P` / `ConnectP2P` / `CreatePollGroup` / `SendMessageToConnection` / `ReceiveMessagesOnConnection`+`PollGroup` / `AcceptConnection`, plus `ISteamNetworkingUtils::InitRelayNetworkAccess`. It does **not** use the legacy `SendP2PPacket` path. |
| 2 | What does Goldberg implement? | **Both** legacy `ISteamNetworking` and new `ISteamNetworkingSockets` are **really implemented** (not stubbed) — but **on top of Goldberg's own LAN layer**. Matchmaking/lobbies are likewise implemented over that layer. **No automatic internet play. README: "You must all be on the same LAN for it to work."** |
| 3 | Does Goldberg provide `steamclient64.dll` / `steamnetworkingsockets64.dll`? | **`steamclient64.dll` yes** (two different files — a 17-line shim *and* the full emulator; see §4.1/§9.1). **No capability difference.** `steamnetworkingsockets64.dll`: Goldberg has an **unfinished 196-line stub** that is **not shipped** in the release; Valve ships no such file either. **Not needed.** |
| 4 | Does the "AppID 480 (Spacewar)" trick help? | **It is the only route to *true* internet co-op — but it requires the REAL Steam client, not Goldberg.** With the genuine Valve `steam_api64.dll` restored and Steam logged in, running as 480 borrows Valve's **real lobbies + Steam Datagram Relay** (works over the internet, behind CGNAT, no VPN). Documented + maintained (OpenSteamTool `-onlinefix`, SteaMidra/LumaCore, Unsteam, OnlineFix). **Under Goldberg it does nothing** — Goldberg never contacts Valve. The two routes are **mutually exclusive**. |
| 5 | Practical internet co-op? | Two **mutually exclusive** families: **(i) keep Goldberg** → no relay exists, so you need a **virtual LAN** (Radmin/Hamachi/ZeroTier carry broadcast; **Tailscale officially does NOT** but works via `custom_broadcasts.txt` unicast) or **`custom_broadcasts.txt` + port-forwarding** (documented, author-tested, fails behind CGNAT). **(ii) real Steam client in the loop** → genuine Valve SDR, works behind CGNAT. |
| 6 | Community reports for Dimraeth? | **They exist**, and Goldberg **LAN** co-op is reported working by one user; another reports a hanging lobby. See §7. |

**One-line answer for the parent's build:** the transport path *is* emulated by Goldberg (so LAN co-op is
genuinely viable), but Goldberg has **no relay** — internet co-op requires either a VPN/`custom_broadcasts.txt`
(Goldberg route) or the **real Steam client** (SDR route).

---

## 1. Ground truth: on-disk state of this install

### 1.1 Files
| Path | Size | Meaning |
|---|---|---|
| `Dimraeth_Data\Plugins\x86_64\steam_api64.dll` | **1,958,912** | **Goldberg**, *regular release* build |
| `Dimraeth_Data\Plugins\x86_64\steam_api64.dll.bak` | **262,944** | **genuine Valve** `steam_api64.dll` (`Valve` string present; ~995 exports incl. the full `ISteamNetworkingSockets` surface) |
| `GameAssembly.dll` | 103,245,824 | Unity **IL2CPP** output — all managed code (incl. `Facepunch.Steamworks.Win64.dll`) compiled in |
| `Dimraeth_Data\il2cpp_data\Metadata\global-metadata.dat` | — | holds managed **type/field names** (metadata v31, Unity **6000.0.61f1**) |

**There are no physical `Facepunch*.dll` / `Unity.Netcode*.dll` files on disk** — only *names* in
`Dimraeth_Data\ScriptingAssemblies.json`. This matters: you cannot "swap the transport DLL"; it is compiled into
`GameAssembly.dll`.

### 1.2 Assemblies compiled into the build (`ScriptingAssemblies.json`, 204 total)
Confirmed present: `Facepunch Transport for Netcode for GameObjects.dll`, `Facepunch.Steamworks.Win64.dll`,
`Unity.Netcode.Runtime.dll`, `Unity.Networking.Transport.dll` (UTP),
`Unity.Multiplayer.Tools.Adapters.Utp2.dll`, `Unity.Multiplayer.Tools.Adapters.Ngo1WithUtp2.dll`.
*(The Utp2 entries are the **Network Profiler adapters** shipped by `com.unity.multiplayer.tools`, which exist
regardless of which transport the game uses — so their presence does **not** prove the game uses UTP2. Treat any
"swap to UnityTransport" idea as SPECULATION.)*

### 1.3 Which Goldberg build is installed — verified by string scan
The installed DLL contains `custom_broadcasts`, `force_listen_port`, `disable_networking` but has **no**
`Valve` string and **none** of `is_lan_ip`, `set_whitelist_ips`, `Mine_SendTo`, `Mine_Connect`, `DetourAttach`,
`disable_lan_only`. Therefore it is the **plain release build** (`build_win_release.bat`:
`cl /LD /DEMU_RELEASE_BUILD /DNDEBUG …`), **not** the experimental build — so the hard LAN-blocking hooks (§3.7)
are **absent**. This is the *better* build for WAN.

### 1.4 Runtime evidence, the applied workaround, and final config
**Goldberg initialised successfully** (artifacts created on launch):
`Goldberg SteamEmu Saves\settings\` → `account_name.txt` = `Noob`, `language.txt` = `english`,
`listen_port.txt` = **`47584`**, `user_steam_id.txt` = `76561199754221087` (valid individual SteamID64).
`Dimraeth_Data\LocalLow\Mudtek\Dimraeth\Player.log` (62 lines) shows Unity 6000.0.61f1 / D3D11 boot and ends at a
game-specific `Developer private key not found.` warning.
> **Do not over-read that log:** `FacepunchTransport` only logs at `LogLevel.Developer` (NGO default is
> `Normal`), so the absence of transport lines proves nothing either way.

**The known loading-screen workaround is already applied** — verified at byte level: the StreamingAssets file is
literally named with **two leading spaces** (`0x20,0x20` then `P`,`o`; total length 32 = 2 + 30):
```
'  Pool Of Remembrance Music.bank'
```

**Final observed config** (changed several times during the session; parent working in parallel):
`steam_appid.txt` = `480` (both in `Plugins\x86_64\` **and** `steam_settings\`), `force_account_name.txt` =
`Spacewar Player`, `force_language.txt` = `english`, `force_listen_port.txt` = **`47584`** (correct — matches
`DEFAULT_PORT`), `custom_broadcasts.txt` = **comment-only template, no peer addresses yet**,
`local_save.txt` = `Goldberg SteamEmu Saves` (redirects the save dir beside the DLL), and
`steam_settings\depots.txt` / `branches.json` / `configs.*.ini` were **removed**.

---

## 2. Q1 — `FacepunchTransport.cs` internals: which Steam APIs?

### 2.1 The package (canonical source, quoted)
`Unity-Technologies/multiplayer-community-contributions`,
`Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs`:

```csharp
using Steamworks;  using Steamworks.Data;  using Unity.Netcode;
namespace Netcode.Transports.Facepunch
{
    using SocketConnection = Connection;
    public class FacepunchTransport : NetworkTransport, IConnectionManager, ISocketManager
    {
        [SerializeField] private uint steamAppId = 480;   // <-- default is 480
        [SerializeField] public ulong targetSteamId;
        [SerializeField] private ulong userSteamId;

        protected override void OnEarlyUpdate()
        {
            SteamClient.RunCallbacks();
            if (!m_SteamInitialized && SteamClient.IsValid)
            {
                m_SteamInitialized = true;
                SteamNetworkingUtils.InitRelayNetworkAccess();   // <-- ISteamNetworkingUtils
        ...
        public override bool StartClient()
        {
            connectionManager = SteamNetworkingSockets.ConnectRelay<ConnectionManager>(targetSteamId);
            return true;
        }
        public override bool StartServer()
        {
            socketManager = SteamNetworkingSockets.CreateRelaySocket<SocketManager>();
            return true;
        }
```
with the tooltip: *"The Steam App ID of your game. Technically you're not allowed to use 480, but Valve doesn't
do anything about it so it's fine for testing purposes."*

**Verdict:** the **newer** `ISteamNetworkingSockets` API. It never calls `SteamNetworking.SendP2PPacket`,
`ReadP2PPacket`, `AcceptP2PSessionWithUser` or `AllowP2PPacketRelay`, and does not use `ISteamNetworking` at all.

### 2.2 Resolution chain — proven from source, not inferred
`Facepunch.Steamworks/SteamNetworkingSockets.cs`:
```csharp
public static T CreateRelaySocket<T>( int virtualport = 0 ) where T : SocketManager, new()
{
    t.Socket = Internal.CreateListenSocketP2P( virtualport, options.Length, options );   // CreateListenSocketP2P
}
public static T ConnectRelay<T>( SteamId serverId, int virtualport = 0 ) where T : ConnectionManager, new()
{
    NetIdentity identity = serverId;
    t.Connection = Internal.ConnectP2P( ref identity, virtualport, options.Length, options );  // ConnectP2P
}
```
Generated bindings reference the flat exports `SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P`,
`_ConnectP2P`, `_SendMessageToConnection`, `_CreatePollGroup`, `_ReceiveMessagesOnConnection`, and the managers use:
* `SocketManager.Initialize()` → `CreatePollGroup()`; `OnConnected()` → `SetConnectionPollGroup(...)`;
  `Receive()` → `ReceiveMessagesOnPollGroup(...)`
* `ConnectionManager.Receive()` → `ReceiveMessagesOnConnection(...)`

Facepunch's wiki describes these as *"Creates a "server" socket … **over SDR (Steam Datagram Relay)**"* — the
naming is **nominal** under Goldberg (§3.2).

### 2.3 Independent confirmation from the game binary
`GameAssembly.dll` contains: `SteamAPI_SteamNetworkingSockets_v008`,
`SteamAPI_SteamNetworkingUtils_v003`, `SteamAPI_SteamGameServerNetworkingSockets_v008`,
`SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P`, `_ConnectP2P`, `_CreateSocketPair`,
`_SendMessageToConnection`, `_ReceiveMessagesOnConnection`, `_ReceiveMessagesOnPollGroup`,
`_CreatePollGroup`, `_SetConnectionPollGroup`, `_AcceptConnection`, `_ReceivedRelayAuthTicket`,
`_FindRelayAuthTicketForServer`, `SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess`,
`SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus`, the full `SteamAPI_ISteamMatchmaking_*` lobby surface,
and `Facepunch.Steamworks.Win64.dll`.

> **Caveat (prevents a wrong conclusion):** a flat-API string in `GameAssembly.dll` only proves Facepunch
> *declares a binding* for it — the library binds the whole flat API. The authoritative evidence for which API
> the **transport** uses is the source in §2.1.

**Methodological warning:** do **not** grep `GameAssembly.dll` for `ConnectRelay` / `CreateRelaySocket` /
`FacepunchTransport` — those managed names live in `global-metadata.dat`, and grepping the DLL produces a
**false negative**.

### 2.4 Version compatibility — a good sign
The game targets **`ISteamNetworkingSockets008`** + **`ISteamNetworkingUtils003`** (Facepunch master today
targets `…_SteamAPI_v012`, so the game embeds an older release). Goldberg declares:
```cpp
class Steam_Networking_Sockets : public ISteamNetworkingSockets001, 002, 003, 004, 006, 008, 009, ISteamNetworkingSockets
class Steam_Networking_Utils   : public ISteamNetworkingUtils001, 002, 003, ISteamNetworkingUtils
```
So **interface negotiation succeeds** — Goldberg hands the game a working v008/v003 interface, which is why the
install behaves plausibly rather than erroring.

---

## 3. Q2 — Goldberg networking: exactly what is implemented

Repo `https://gitlab.com/Mr_Goldberg/goldberg_emulator` (branch `master`).

**File layout (important):** there is **no** `networking.cpp`, **no** `steam_networking.cpp`, **no**
`steam_networking_sockets.cpp`, **no** `steam_matchmaking.cpp`. Those interfaces are **header-only**
(`steam_networking.h`, `steam_networking_sockets.h`, `steam_matchmaking.h`). The real transport is
**`dll/network.cpp` + `dll/network.h`**.

### 3.1 Legacy `ISteamNetworking` → **YES, fully implemented (not stubbed)**
`dll/steam_networking.h` implements all of: `SendP2PPacket`, `IsP2PPacketAvailable`, `ReadP2PPacket`,
`AcceptP2PSessionWithUser`, `CloseP2PSessionWithUser`, `CloseP2PChannelWithUser`, `GetP2PSessionState`,
`AllowP2PPacketRelay`, `CreateListenSocket`, `CreateP2PConnectionSocket`, `CreateConnectionSocket`,
`DestroySocket`, `DestroyListenSocket`, `SendDataOnSocket`, `IsDataAvailableOnSocket`,
`RetrieveDataFromSocket`, `IsDataAvailable`, `RetrieveData`, `GetSocketInfo`, `GetListenSocketInfo`,
`GetSocketConnectionType`, `GetMaxPacketSize`.

`AllowP2PPacketRelay` is a **no-op returning `true`** (there is no relay to allow):
```cpp
bool AllowP2PPacketRelay( bool bAllow ) { return true; }
```
and sends route into Goldberg's own transport, not Steam:
```cpp
bool SendP2PPacket( CSteamID steamIDRemote, const void *pubData, uint32 cubData, EP2PSend eP2PSendType, int nChannel)
{
    ...
    struct Steam_Networking_Connection *conn = get_or_create_connection(steamIDRemote);
    bool ret = network->sendTo(&msg, reliable);
}
```

### 3.2 Newer `ISteamNetworkingSockets` → **core is real; exotic parts are stubs**

**Implemented** (real bodies, routed through `network->sendTo()`): `CreateListenSocket(int,uint32,uint16)`,
`CreateListenSocketIP` (×3), **`CreateListenSocketP2P`** (×2) → `new_listen_socket(nVirtualPort, SNS_DISABLED_PORT)`,
`ConnectByIPAddress` (×3), **`ConnectP2P`** (×3) → `new_connect_socket(...)` + `send_packet_new_connection(...)`,
`AcceptConnection`, `SendMessageToConnection` (×3), `SendMessages`, `ReceiveMessagesOnConnection`,
`ReceiveMessagesOnPollGroup`, `CreatePollGroup`/`DestroyPollGroup`/`SetConnectionPollGroup`,
`GetConnectionInfo`, `GetDetailedConnectionStatus`, `CloseConnection`, `CloseListenSocket`,
`FlushMessagesOnConnection`, `GetIdentity`, `SetConnectionUserData`, `SetConnectionName`, `CreateSocketPair`.

`SendMessageToConnection` proves data never touches Steam:
```cpp
EResult SendMessageToConnection( HSteamNetConnection hConn, const void *pData, uint32 cbData, int nSendFlags, int64 *pOutMessageNumber )
{
    ...
    msg.mutable_networking_sockets()->set_data(pData, cbData);
    bool reliable = false;
    if (nSendFlags & k_nSteamNetworkingSend_Reliable) reliable = true;
    if (network->sendTo(&msg, reliable)) { ... return k_EResultOK; }
    return k_EResultFail;
}
```

**Stubbed / hard-failed:** `CreateListenSocketP2PFakeIP` → `k_HSteamListenSocket_Invalid`;
`BeginAsyncRequestFakeIP` → `false`; `GetFakeIP`/`GetRemoteFakeIPForConnection`/`CreateFakeUDPPort` →
void/`k_EResultNone`/`NULL`; `ConnectP2PCustomSignaling` → `k_HSteamNetConnection_Invalid`;
`ReceivedP2PCustomSignal` → `false`; `GetCertificateRequest`/`SetCertificate` → `false`;
`GetGameCoordinatorServerLogin` → `k_EResultFail`; `GetConfigurationValue`/`GetConfigurationString` → `-1`;
`SetConfigurationString`/`SetConnectionConfigurationValue` → `false`; `GetConfigurationValueName`/
`GetConfigurationStringName` → `NULL`; `ConnectBySteamID`/`ConnectByIPv4Address` → `k_HSteamNetConnection_Invalid`.
Relay-ticket APIs: `ReceivedRelayAuthTicket` → `false`, `FindRelayAuthTicketForServer` → `0`; the author's own
TODO admits *"right now this only supports connecting with steam id"*.

### 3.3 `InitRelayNetworkAccess` / relay status are **faked to succeed**
`dll/steam_networking_utils.h` — this is why the game's relay gate passes with no relay present:
```cpp
bool InitializeRelayAccess() { init_relay = true; return relay_initialized; }

SteamRelayNetworkStatus_t get_network_status()
{
    SteamRelayNetworkStatus_t data = {};
    data.m_eAvail = k_ESteamNetworkingAvailability_Current;
    data.m_eAvailAnyRelay = k_ESteamNetworkingAvailability_Current;
    data.m_eAvailNetworkConfig = k_ESteamNetworkingAvailability_Current;
    strcpy(data.m_debugMsg, "OK");
    return data;
}
```
`GetRelayNetworkStatus()` **always** returns `k_ESteamNetworkingAvailability_Current` / `"OK"` without ever
contacting Valve. Ping helpers are equally fake (`EstimatePingTimeBetweenTwoLocations` → `10`, `GetPOPCount` → `0`).

### 3.4 `ISteamMatchmaking` → implemented, but **LAN-only**
`dll/steam_matchmaking.h` implements `CreateLobby`, `JoinLobby`, `LeaveLobby`, `RequestLobbyList`,
`GetLobbyByIndex`, `SetLobbyData`/`GetLobbyData`, `SetLobbyMemberData`, `InviteUserToLobby`,
`SendLobbyChatMsg`/`GetLobbyChatEntry`, `SetLobbyOwner`, `RequestLobbyData`, `SetLobbyGameServer`, etc.
Propagation is over Goldberg's own network:
```cpp
void send_lobby_data()
{
    for(auto & l: lobbies) {
        ... msg.set_allocated_lobby(new Lobby(l));
        network->sendToAllIndividuals(&msg, true);
    }
}
```
`RequestLobbyList()` queries **no server** — it searches Goldberg's locally accumulated `lobbies` vector,
populated only from peers discovered by the LAN announce (`#define LOBBY_SEARCH_TIMEOUT 0.2`).
`JoinLobby()` sends `Lobby_Messages::JOIN` via `network->sendTo(...)`; chat uses
`Lobby_Messages::CHAT_MESSAGE`.

**AppID filter (critical):** lobby updates are only accepted when AppIDs match:
```cpp
if (msg->lobby().owner() != settings->get_local_steam_id().ConvertToUint64()
    && msg->lobby().appid() == settings->get_local_game_id().AppID()) {
```

### 3.5 Cross-machine discovery → **UDP broadcast, LAN-only**
`dll/network.h`: `#define DEFAULT_PORT 47584`, `std::vector<IP_PORT> custom_broadcasts;`
`dll/network.cpp`: `get_broadcast_info()` enumerates adapters and computes each interface's directed subnet
broadcast (`broadcast_ip = iface_ip | ~subnet_mask`); `send_announce_broadcasts()` (every
`#define BROADCAST_INTERVAL 5.0` s) targets:
1. **`INADDR_BROADCAST` (255.255.255.255)** — unconditionally:
```cpp
    IP_PORT main_broadcast;  main_broadcast.ip = INADDR_BROADCAST;  main_broadcast.port = port;
    int ret = send_packet_to(sock, main_broadcast, data, length);
```
2. every per-interface subnet broadcast address;
3. **every `custom_broadcasts` entry, as plain unicast** (resolved by `Networking::resolve_ip()` via
   `getaddrinfo()`, so IPs **and domains**, optional `host:port`), which are also added to the IP allow-list
   (`set_whitelist_ips(...)`).

Reliable data → TCP, unreliable → UDP (`sendTo()` chooses); heartbeats/timeouts `HEARTBEAT_TIMEOUT 20.0`,
`USER_TIMEOUT 20.0`. **No rendezvous, no NAT traversal, no relay.** `sendToIPPort()` still carries
`//TODO: actually send to ip/port`, which means **`ConnectByIPAddress` is not a shortcut around discovery** —
it only matches *already-known* connections.

### 3.6 Confirm or refute: "Goldberg does internet play without a VPN"
**Precise verdict: no automatic internet play, but internet play WITHOUT a VPN IS achievable** via
`custom_broadcasts.txt` + port-forwarding (§6.2), which is **documented and author-tested**.

Goldberg's README, verbatim: **"An emulator that supports LAN multiplayer without steam."** and, under a
top-level `Notes:` heading, **"You must all be on the same LAN for it to work."**

> **Structural check (refuting a parallel agent's claim).** An agent asserted this note is *scoped under*
> "Support for CPY steam_api(64).dll cracks". **I verified the actual README and this is a misreading.** The
> order is: `Support for CPY steam_api(64).dll cracks: …` (a one-line paragraph) → **`Notes:`** → the LAN
> sentence → **`IMPORTANT:`** → … → `Overlay` → `Controller` → `DLC:` … So `Notes:` is a **top-level heading**,
> a peer of `IMPORTANT:`/`Overlay`/`DLC:`. Source:
> `https://raw.githubusercontent.com/kameralarda/goldberg_emulator/master/Readme_release.txt`
> The agent's *other* point is correct and already reflected in §1.3/§3.7: the *hard enforcement* is
> experimental-only, and the release build does not block WAN — it simply has no way to *discover* WAN peers
> except `custom_broadcasts.txt`. That is precisely why the port-forward recipe works.

Also documented: *"**Custom Broadcast ips:** If you want to set custom ips (or domains) which the emulator will
send broadcast packets to, make a list of them, one on each line in:
`Goldberg SteamEmu Saves\settings\custom_broadcasts.txt`. If the custom ips/domains are specific for one game
only you can put the `custom_broadcasts.txt` in the `steam_settings\` folder."*

### 3.7 The experimental build's hard LAN-only block
`dll/base.cpp`, guarded by `#ifdef EMU_EXPERIMENTAL_BUILD` + `#ifdef __WINDOWS__`, Detours-hooks
`sendto`/`connect`/`WSAConnect`:
```cpp
static int WINAPI Mine_SendTo( SOCKET s, const char *buf, int len, int flags, const sockaddr *to, int tolen) {
    if (is_lan_ip(to, tolen)) { return Real_SendTo( s, buf, len, flags, to, tolen ); }
    else { return len; }                       // silently DISCARDED, reports success
}
static int WINAPI Mine_Connect( SOCKET s, const sockaddr *addr, int namelen ) {
    if (is_lan_ip(addr, namelen)) { return Real_Connect(s, addr, namelen); }
    else { WSASetLastError(WSAECONNREFUSED); return SOCKET_ERROR; }
}
```
`is_lan_ipv4()` allows: whitelisted ranges, `127.x`, `10.x`, `192.168.x`, `169.254.x`, `172.16–31.x`,
**`100.64.0.0/10` (CGNAT = Tailscale)**, `239.x`, `0.x`, `192.18/19`, `>=224`, plus any `custom_broadcasts`
entry. Disabled by `disable_lan_only.txt` in `steam_settings\`. `Mine_WinHttpConnect` also redirects non-LAN
WinHTTP to `127.1.33.7`. The `experimental` readme states explicitly that *"hosting a cracked server for people
on the internet will not work"* — so **the experimental build is strictly *less* capable for WAN**. Do not
"upgrade" to it. **Your release build does not have this block (§1.3).**

---

## 4. Q3 — `steamclient64.dll` and `steamnetworkingsockets64.dll`

### 4.1 `steamclient64.dll` — ships, but is **not** a cracked Steam client, and adds no capability
Two *different* files exist (this refines a common conflation):

| File | Size | What it is |
|---|---|---|
| `experimental\steamclient64.dll` | 89,600 B | A **~17-line forwarding shim**: `LoadLibraryA("steam_api64.dll")` then forwards `CreateInterface` → `SteamInternal_CreateInterface`. Imports only `KERNEL32.dll`; its only other referenced DLL is `steam_api64.dll`. |
| `experimental_steamclient\steamclient64.dll` | 3,019,776 B | The **full emulator** built as a steamclient library: 9 sections incl. `.detourc/.detourd`, imports WINMM/XINPUT/USER32/GDI32/dwmapi, exports **38** symbols = `CreateInterface` + legacy Steam2 `Steam_*` flat API (`Steam_LogOn`, `Steam_GSLogOn`, `Steam_BLoggedOn`, …) + `Breakpad_*`. |

`build_win_release_experimental_steamclient.bat` compiles **the same `dll/*.cpp`** with `-DSTEAMCLIENT_DLL`.
Official `Readme_experimental_steamclient.txt`: *"…in steamclient mode with an included loader. … Make sure you
put the right appid in the ini file."* `ColdClientLoader.ini` keys: `Exe=`, `ExeRunDir=`, `ExeCommandLine=`,
`AppId=`, `SteamClientDll=`, `SteamClient64Dll=`.

**ColdClientLoader mechanism:** reads the ini, aborts if `AppId` is empty, sets env `SteamAppId`/`SteamGameId`,
launches with `CreateProcessW(..., CREATE_SUSPENDED)`, plants `HKCU\Software\Valve\Steam\ActiveProcess\{SteamClientDll,
SteamClientDll64, ActiveUser, pid, Universe}` (`ActiveUser` hardcoded `0x03100004771F810D`), `ResumeThread`,
restores on exit — Valve's own registry contract, redirected at the emulator.

**Purpose:** for games that load via the real Steam client path (Steam DRM / `SteamAPI_RestartAppIfNecessary`
flows). **Key point: because the networking code is identical, the `steamclient64.dll` route gives *no*
internet/relay capability beyond the `steam_api64.dll` route.** It changes *how the DLL is loaded*, not *how
peers are found*.

### 4.2 `steamnetworkingsockets64.dll` — not shipped, unfinished, and not needed
* Goldberg's repo **does** contain `steamnetworkingsockets.cpp` and a `steamnetworkingsockets` CMake target —
  but the file is a **196-line unfinished stub**: it forwards
  `CreateInterface(... "SteamNetworkingSockets001")` **back into the emulator's own implementation**, stubs the
  datagram/P2P entry points with placeholder virtuals literally named `a()`…`j()`, and carries the author's
  comment `//not sure if these are the correct functions`.
* It exports the **standalone SDR SDK** entry points (`SteamDatagramClient_Init_InternalV6`,
  `SteamDatagramServer_Init_Internal`, `SteamNetworkingSockets()`, `SteamNetworkingUtils()`,
  `SteamNetworkingP2P()`) — **not** the Steam flat API.
* **The release zip ships no such DLL**, and Goldberg's `steam_api64.dll` exports **zero** `_LibV*` symbols, so
  it is not even link-compatible with Valve's standalone-library API.
* **Valve ships no such file either:** the SDK's `redistributable_bin/win64` contains only `steam_api64.dll` +
  `.lib`. The name belongs to Valve's **`STEAMNETWORKINGSOCKETS_STANDALONELIB`** mode = the open-source
  *GameNetworkingSockets* product (different product, own API).

The implementation therefore lives **inside `steam_api64.dll`** — confirmed here: the genuine Valve DLL
(262,944 B, ~995 exports) has the complete `SteamAPI_ISteamNetworkingSockets_*` / `SteamAPI_ISteamNetworkingUtils_*`
surface incl. `SteamAPI_SteamNetworkingSockets_v008` and `_InitRelayNetworkAccess`.

**Answer: no — it would not help, and a Goldberg install never needs it.** A binary scan confirms the game's
**only** `DllImport` library is `steam_api64`, making `steam_api64.dll` the single native interception point.

---

## 5. Q4 — The "use Spacewar / AppID 480" technique

### 5.1 What AppID 480 is, and where the practice comes from
**480 = "Spacewar"**, Valve's official free **Steamworks SDK sample app**. The practice originates in **Valve's
own documentation**: the Steamworks API overview documents `steam_appid.txt` using **`480` as the literal
example** (*"This overrides the value that Steam provides… Example: `480`"*). It is free, has no store page
(`appdetails?appids=480` → `success:false`), and has Steam's multiplayer features enabled.

### 5.2 (a) real/emulated Steam client as 480 vs (b) standalone Goldberg
| | **(a) real Steam client, game as 480 (OnlineFix / OpenSteamTool / Unsteam / LumaCore)** | **(b) standalone Goldberg `steam_api64.dll`** |
|---|---|---|
| Who terminates traffic | **Valve**: real lobbies + **Steam Datagram Relay (SDR)** | **Goldberg**: own UDP-broadcast + TCP layer |
| Lobby/matchmaking | real Steam lobby servers | local `lobbies` vector over LAN |
| P2P transport | real SDR (`CreateListenSocketP2P`/`ConnectP2P` serviced by Valve) | Goldberg's `Network` class |
| Files | genuine Valve `steam_api64.dll` (+ tool DLL/hooks); OnlineFix uses `RealAppId`/`FakeAppId` and requires `steam_appid.txt` **absent** | Goldberg `steam_api64.dll` + `steam_settings\` |
| Internet co-op | **Yes** — over the open internet, behind CGNAT, no VPN | **No** (LAN / virtual-LAN, or `custom_broadcasts.txt` + port-forward) |
| Requirement | real Steam client running **and logged in** | none |

**This is the crux:** (a) enables true internet co-op because it delegates to **Valve's** servers; (b) replaces
them with a local LAN protocol. The practical difference is **who owns the sockets**.

**Why (a) is mechanically legitimate (not "fooling" anything):** Valve's SDR page states it *"does not restrict
who can attempt to connect, aside from **verifying that the player is signed into Steam and owns the game**."*
The account genuinely owns the free 480 — only *which app the local process claims to be* is spoofed, via a
documented Valve dev feature. **The folklore to discard** is "cracked DLLs fool Valve's servers": nothing is
fooled at authentication.

### 5.3 Why 480 specifically
Free, publicly available to any Steam account, with Steam networking enabled — so a re-badged game can use
Valve's lobbies/relay without owning the real title.

### 5.4 Why 480 is worthless **under Goldberg**
1. **Goldberg never contacts Valve** (§3.5) — there is no endpoint whose behaviour an appid could change.
2. **Peers and lobbies are filtered by appid** — `create_announce()` stamps `announce->set_appid(this->appid)`;
   `handle_announce()` matches on it; `Steam_Matchmaking::Callback` requires
   `msg->lobby().appid() == settings->get_local_game_id().AppID()`; `run_callback_user()` ignores mismatched peers.
   **Therefore every machine must use the same appid** — and under Goldberg the appid is essentially a **local
   LAN peer-matching key**. Setting it to 480 gains nothing and risks **colliding with every other 480 game on
   the same LAN**.
3. A parallel agent therefore recommends keeping `2402680`. **My qualification:** what actually breaks
   multiplayer is a **mismatch between peers**, so the operative rule is *make all peers identical*. The current
   `480`/`480` is internally consistent and therefore fine for Goldberg; `2402680` is simply a less crowded
   namespace.

### 5.5 What decides the appid — and why it is UNDETERMINED here
Goldberg's README gives its file lookup order (*"`steam_settings` … is where the emulator checks first … it will
try opening it from the run path … then … beside my steam api dll…"*) and adds: *"The steam appid can also be
set using the `SteamAppId` or `SteamGameId` env variables."*
**That env clause matters, because Facepunch sets exactly those variables.** `Facepunch.Steamworks/SteamClient.cs`:
```csharp
public static void Init( uint appid, bool asyncCallbacks = true )
{
    System.Environment.SetEnvironmentVariable( "SteamAppId",  appid.ToString() );
    System.Environment.SetEnvironmentVariable( "SteamGameId", appid.ToString() );
    ...
    var result = SteamAPI.Init( interfaceVersions, out var error );
```
and `FacepunchTransport.Initialize()` calls `SteamClient.Init(steamAppId, false)` where
`steamAppId` is `[SerializeField] private uint steamAppId = 480;`. **So the game itself may set the effective appid
at runtime, and `steam_appid.txt` may not be the deciding input.** Goldberg's internal precedence between
`steam_settings\steam_appid.txt` and the `SteamAppId` env var was **not determined**.

**Attempted recovery of the game's serialized `steamAppId` — INCONCLUSIVE.** Field *names* exist only in
`global-metadata.dat`; *values* are stored positionally in the Unity serialized files. Expected record layout is
`steamAppId(u32)`, `targetSteamId(u64)`, `userSteamId(u64)` = a 20-byte pattern `[appid][0×8][0×8]`. I
byte-scanned every `.assets`/`level*`/`globalgamemanagers*` file:
* 2402680 variant: **exactly one** byte-exact hit, `sharedassets1.assets` @ `262730064`.
* 480 variant: **hundreds** (generic padding) — unusable.

The single 2402680 hit is **almost certainly not the transport** — its neighbours are narrative/quest strings:
```
abs=262730328  rel=+264   Tamsin's Shop
abs=262730544  rel=+480   AVillageInCrisis-Befr-1
abs=262730572  rel=+508   AFirstAdventure-Pre
abs=262730656  rel=+592   Befr-CorruptedTree
```
=> **The game's effective AppID is UNDETERMINED by static analysis.** Runtime determination: run until the game
writes stats, then see which `<appid>` folder appears under the Goldberg save dir.

**Net recommendation:** for the Goldberg route keep `steam_settings\steam_appid.txt` and `steam_appid.txt`
**consistent with each other and byte-identical across all peers.** For the **real-Steam route**, follow that
tool's own appid instructions — and note **OnlineFix requires `steam_appid.txt` to be ABSENT** while
OpenSteamTool/SteamMidra use launch flags.

---

## 6. Q5 — Realistic paths to internet co-op

The driving constraint: Goldberg has **no rendezvous server, no NAT traversal, no relay** (§3.5). Peer discovery
is UDP broadcast; data is direct UDP/TCP between discovered peers. Any working solution must make peers
**mutually discoverable and reachable**.

### 6.1 Technique 1 — LAN-over-WAN VPN
Put both players on one virtual network so Goldberg's broadcast (or a unicast `custom_broadcasts` entry) reaches
the peer, and the subsequent UDP/TCP traffic on **47584** routes between them.
* Goldberg binds **`DEFAULT_PORT 47584`** for **UDP and TCP** (confirmed at runtime). If taken it walks upward
  (`port + i`, ≤1000 tries), so **pin it** with `steam_settings\force_listen_port.txt` = `47584` on **every**
  peer. README: *"everyone needs to use the same port or you won't find yourselves on the network."*

| VPN | Layer | Carries `255.255.255.255` / L2 broadcast? | Source | Confidence |
|---|---|---|---|---|
| **Radmin VPN** | L2/TAP | **Yes** — driver advertises itself as preferred for UDP `255.255.255.255` and multicast; troubleshooting section is literally "LAN games don't see other peers" | `https://github.com/baptisterajaut/radmin-vpn-linux` | High |
| **Hamachi** | L2 | **Yes** — *"creates a single broadcast domain between all clients… handles tunneling of IP traffic including broadcasts and multicast"* | `https://en.wikipedia.org/wiki/Hamachi_(software)` | High |
| **ZeroTier** | L2 (VL2) | **Yes in principle** — *"Broadcast (Ethernet ff:ff:ff:ff:ff:ff) is treated as a multicast group to which all members subscribe."* **Caveat: ad-hoc (`ff…`) networks allow only IPv6 unicast → no broadcast; use a controller-managed network.** | `https://docs.zerotier.com/protocol/`, `https://github.com/zerotier/ZeroTierOne/issues/884` | Med-High |
| **Tailscale** | L3 (WireGuard) | **NO** — official: *"there is no support for broadcast or multicast due to the point-to-point nature of the connections."* | `https://forum.tailscale.com/t/broadcast-multicast-support/156` | **Very High** |
| **NetBird** | L3 | **No** — open issue "Multicast not working" (#1435) | `https://github.com/netbirdio/netbird/issues/1435` | High |
| **SoftEther** | L2 | **Yes** — explicit L2 bridge (single broadcast domain) | `https://www.softether.org/4-docs/1-manual/A/10.5` | High |

**Universal fix for L3 VPNs:** because `custom_broadcasts.txt` sends the announce as **plain unicast UDP**,
discovery does not need broadcast — it needs the peer to be **unicast-reachable**:
> **Put the peer's VPN IP into `custom_broadcasts.txt` and even Tailscale/NetBird become viable.**

Whether that is *documented* for Tailscale: **NOT FOUND** — it follows from the code (unicast UDP over WireGuard
is ordinary routed traffic) and is labelled **SPECULATION, well-grounded**. Tailscale's `100.64.0.0/10` range is
also on the *experimental* allow-list, but irrelevant for your release build.

### 6.2 Technique 2 — `custom_broadcasts.txt` (+ port-forwarding) — **documented and author-tested**
The feature's own author, in GitLab **MR !41**:
> *"Prior to this patch, **Internet play could be achieved with port forwarding + adding each other's IP
> addresses to each other's `custom_broadcasts.txt` files.** … all peers just gotta update their own
> `custom_broadcasts.txt` file specifying the other ones addresses (including their respective ports). BOOOM. It
> just works. **I've manually tested it thoroughly with some friends and can assure it in fact does work.**"*
> `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41`

| Item | Value / location |
|---|---|
| Ports to forward | **UDP 47584 AND TCP 47584**, mapped **WAN 47584 → LAN 47584** (the TCP port comes from the announce payload, so an arbitrary external port will **not** work) |
| Per-game peer list (highest priority) | `Dimraeth_Data\Plugins\x86_64\steam_settings\custom_broadcasts.txt` |
| Global peer list | `%APPDATA%\Goldberg SteamEmu Saves\settings\custom_broadcasts.txt` |
| Format | one IP **or domain** per line, optionally `ip:port` |
| Port pinning | `force_listen_port.txt` in `steam_settings\` (global dir does **not** honour `force_*`) |
| Same-port rule | all peers same port unless each peer's port is listed explicitly |

**Why it works end-to-end:** the client's announce reaches the host's forwarded port; the host's PONG teaches the
client the host's announced `tcp_port`; the client opens TCP **outbound** to `host_public_ip:47584`. Only **one
direction** of TCP needs to succeed because `sendTo()` prefers an already-established socket:
```cpp
if (reliable || !conn->udp_pinged) {
    if (conn->tcp_socket_incoming.received_data) { send_buffer_tcp(conn->tcp_socket_incoming, msg); ret = true; }
    else if (conn->tcp_socket_outgoing.received_data) { send_buffer_tcp(conn->tcp_socket_outgoing, msg); ret = true; }
}
```
So **the HOST is the side that must port-forward**; the client needs only outbound access.
**Confidence: HIGH for the mechanism** (author-tested; corroborated by per-game cs.rin.ru guides: ELDEN RING
NIGHTREIGN, The Forest, Enshrouded, GTFO, Grim Dawn). **Fails behind CGNAT/double-NAT**, and only one peer per
public IP can own the forwarded port.

### 6.3 Technique 3 — replacing/patching the transport
The game is **Unity 6000.0.61f1 + IL2CPP (metadata v31)**, so an in-process patch needs a Unity-6-capable IL2CPP
loader — **BepInEx 6 bleeding-edge** (`https://builds.bepinex.dev/projects/bepinex_be`) or MelonLoader (currently
worse for Unity 6 — open issue for metadata 31.1, `https://github.com/LavaGang/MelonLoader/issues/1100`) — plus
Harmony. Patch target: `StartServer` `CreateRelaySocket` → `CreateNormalSocket(NetAddress.Any(port))`,
`StartClient` `ConnectRelay(targetSteamId)` → `ConnectNormal(NetAddress.From(hostIp, port))`, **and** reroute the
lobby-join path to carry a host IP instead of a SteamID. That last part is essential — see §6.5.
`Unity.Networking.Transport.dll` + the `Utp2` profiler adapters *are* compiled in, so swapping
`NetworkManager.NetworkConfig.NetworkTransport` to `UnityTransport` is architecturally conceivable — but
**SPECULATION, untested**. **This is a substantial, version-fragile effort.**

### 6.4 Technique 4 — a custom SDR relay / `steam_api64.dll` shim
**NOT FOUND — no existing project does this**, and upstream explicitly refuses it:
* gbe_fork issue #94 asks for wrapper mode "just like online fix" → maintainer: **"Nope. Otherwise this wouldnt
  be an option for offline/lan play."**
* gbe_fork issue #127 → **"Leave the online stuff to online-fix and the likes."**
* gbe_fork **PR #457 ("add relay to use goldberg over internet") was closed unmerged ~16 seconds after opening.**
* gbe_fork docs concede matchmaking *"will always return LAN servers list"*.

Technically, Valve's `GameNetworkingSockets` is **not a drop-in**: its OSS build's `CreateListenSocketP2P`
**requires `nSteamConnectVirtualPort = -1`** (a game calling `CreateListenSocketP2P(0)` fails), SteamID identities
are unresolvable outside Steam, and *"the SDR support code is not opensource"* — you would have to run your own
signaling + STUN/TURN. Corroboration that `ConnectP2P` is bound to Valve's backend: Facepunch issue #400
(self-connect died with "reason code 4003 (Bad cert: CA key is not known to us)"). The *correct shape* of a real
fix is a Goldberg fork whose `Networking` class uses a rendezvous/relay instead of `255.255.255.255` — **no such
fork exists** (checked the GitLab fork list and the gbe_fork tree; gbe_fork's `networking_sockets_lib/…` is a
*shim* returning the emulator's own interface).

### 6.5 Technique 5 — splitting lobby from transport
**Under Goldberg you cannot fake lobbies locally and relay only the P2P.** One discovery layer feeds both:
Goldberg's SteamID→connection map is populated **only** by announce discovery, lobbies use the same layer
(`dll/steam_matchmaking.h`), and `targetSteamId` comes from the lobby/invite layer. Goldberg's own `lobby_connect`
tool demonstrates the constraint — its README says it *"discovers people playing on the network using my emu"*
and then launches with `+connect_lobby <id>`; it does not dial a public IP.
Real splits: **(A)** keep Goldberg for both and fix discovery over WAN (Techniques 1/2 — one config line);
**(B)** Harmony: IP sockets for the transport **plus** carry a host IP instead of a SteamID in the lobby path;
**(C)** a native `steam_api64` shim doing SteamID→your-relay mapping itself. **No existing tool does (B) or (C).**

### 6.6 Technique 6 — real Steam client in the loop (**the only *true* internet route**)
Restore the **genuine Valve `steam_api64.dll`** (`steam_api64.dll.bak`, 262,944 B) and run the game as **AppID 480**
with the real Steam client running and logged in → **Valve's own lobby servers and Steam Datagram Relay** service
the traffic. No VPN, no port-forwarding, works behind CGNAT.

**Steps for this install**
1. Rename `steam_api64.dll.bak` → `steam_api64.dll` — **remove Goldberg** (they are mutually exclusive: the game's
   only `DllImport` library is `steam_api64`).
2. Remove/neutralise Goldberg's `steam_settings\` overrides. Note **OnlineFix specifically requires
   `steam_appid.txt` to be ABSENT**; the simpler `steam_appid.txt`=`480` form applies to the plain Spacewar spoof.
3. Start Steam and log in (a free account suffices).
4. Launch `Dimraeth.exe` **directly**, not through Steam, so Steam does not inject `SteamAppId=2402680`.
5. Verify Steam shows "Spacewar" as playing, then host/join in game.

**Maintained tools:** OpenSteamTool (`-onlinefix`; log line *"480 AppId spoofing"*; limitation: only one such game
at a time), SteaMidra/SFF + LumaCore (`-onlinefix` in `localconfig.vdf`), Unsteam
(`real_app_id=`/`fake_app_id=480`; Steam must be logged in). **OnlineFix teardown:** `OnlineFix64.dll` PE metadata
`CompanyName=Online-Fix.Me`, `FileDescription=Online-Fix Steamclient`; config keys **`RealAppId`+`FakeAppId`**;
payload = `OnlineFix64.dll` + `winmm.dll` (proxy) + `dlllist.txt` + `OnlineFix.ini`; ships its **own** signed
`steam_api64.dll` (not Goldberg). **Decisive proof it uses Valve's backend:** users switch `FakeAppId` between real
free Valve appids (`480`, `1836450`, `314970`) and observe **different player populations** → different backend
matchmaking pool → only Valve can produce that.

**Caveats:** requires the real Steam client (this is "no *Dimraeth* licence", not "no Steam"); the 480 pool is
shared with every 480-spoofer of every game (use private lobbies/invites); client-hook variants break on Steam
client updates; Steam ToS/ban risk is low but non-zero; **Dimraeth-specific confirmation is NOT FOUND**; and
**third-party OnlineFix binaries are flagged as untrusted** (24/71 VirusTotal detections, another aggregate 47/75,
packed `.of0/.of1/.of2` sections — the ecosystem itself advises throwaway accounts). Whether a legit Dimraeth
owner can share a lobby with a 480-spoofer is **contradictorily reported and UNRESOLVED** (irrelevant if all
players use the same method).

### 6.7 Ranking
Families are **mutually exclusive** (the real-Steam route requires removing Goldberg).

**Goal = genuine internet co-op, no VPN, works behind CGNAT →**
1. **Technique 6 (real Steam client + AppID 480)** — ~15 min; the only route that gives true internet play.
   Mechanism documented by Valve; Dimraeth-specific confirmation NOT FOUND; third-party fix binaries untrusted.
2. Technique 1 (Goldberg + VPN) — best-effort if staying Steam-free.
3. Technique 2 (Goldberg + port-forward) — author-tested but fails behind CGNAT.

**Goal = stay Steam-free with Goldberg →**
1. **Technique 1** + `force_listen_port.txt`=`47584` + `custom_broadcasts.txt` = peer's VPN IP. Prefer
   **Radmin or Hamachi** (documented broadcast domains, zero config) or a **non-ad-hoc ZeroTier**; on
   **Tailscale/NetBird you must** use `custom_broadcasts.txt`. Matches the one positive Dimraeth community report
   (§7) and the Lethal Company analogue (§7.3).
2. Technique 2 — documented/author-tested; needs a real public IP on the host.
3. Technique 3 (IL2CPP patch) — high effort, unverified. 4. Technique 4 — no implementation exists.

---

## 7. Q6 — Community reports

### 7.1 Dimraeth — reports EXIST
cs.rin.ru **"[Info] Dimraeth"**, `https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040` (f=10; created 5 Feb 2026,
active 16 Sep 2026, ~24 posts). Direct fetch returns HTTP 401 security check; readable via the text proxy
`https://r.jina.ai/https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040`.

| Report | Detail | Source |
|---|---|---|
| **Goldberg LAN works** | User **vperpl** (~16 Sep 2026, p=3589751), answering a Tailscale question: *"ye i tried both creamapi and goldberg lan - works fine"* | cs.rin.ru t=155040 |
| **Negative: hanging lobby** | User **megosa** (p=3589448): *"can't create lobby stuck in loading for me"* | cs.rin.ru t=155040 |
| **"Online Fix" needs REAL Steam** | DicDale/ZeiGames upload: *"Based on CSF & Goldberg. **Play Online:** Download the Online Fix … **Sign in to your Steam account.** … If the in-game invite button doesn't work, invite them to play **'Spacewar'** using the Steam interface."* → this is route **(a)**, not a Goldberg internet solution | cs.rin.ru t=155040 |
| **Tailscale unanswered** | User **thewaldro**: *"I prefer a tailscale setup over onlinefix tbh"* — **no Tailscale result was reported** | cs.rin.ru t=155040 |
| Loading-screen workaround | Two leading spaces on the StreamingAssets file (**verified already applied here**, §1.4) | cs.rin.ru t=155040 |
| Metadata-unreliable upload | A "Crack Only" upload lists *"App ID: 2940280, Engine: Unreal Engine"* — Dimraeth is 2402680/Unity, so that uploader is unreliable | cs.rin.ru t=155040 |

**online-fix.me has NO Dimraeth page.** Also flagged as a **red herring**: the 3DMGAME "Operation Dimera" TENOKE
thread is a *different* game (AppID 3883840). And `2upskill.com`'s "How to Fix Dimraeth Multiplayer Not Working"
was published **before** release, cites nothing, and contains no emulator content — **do not cite it**.

### 7.2 Interpretation
One user reports Goldberg **LAN** co-op working → consistent with §3.2 (Goldberg genuinely services
`CreateListenSocketP2P`/`ConnectP2P` and lobbies). One reports a hanging lobby → exactly the symptom of failed
**discovery** (different subnet/VPN, mismatched appid, or mismatched `listen_port`). The commercial "Online Fix" in
that thread is route **(a)**. **No confirmed report of Dimraeth working over the open internet with Goldberg + a
VPN was found** — the only relevant request (Tailscale) went unanswered. **Label: UNCONFIRMED for WAN.**

### 7.3 Comparable games — two premise corrections
**Correction 1: ROUNDS is NOT a Facepunch/SteamNetworkingSockets game.** I had listed it as a key comparison.
Decompiled `ROUNDS/Landfall.Network/ClientSteamLobby.cs` uses `Steamworks` (**Steamworks.NET**) *and*
`Photon.Pun`; gameplay goes to Photon (`PhotonNetwork.JoinRandomRoom()`), with Steam only for the lobby/invite
handshake (`http://git.warmcat.org/ROUNDS/diff/ROUNDS/Landfall.Network/ClientSteamLobby.cs`). **So ROUNDS is not
a valid analogue, and Goldberg cannot carry its gameplay traffic at all** — Goldberg emulates Steam services, not
Photon. Same for other Photon titles (Content Warning, R.E.P.O.). The gbe_fork maintainer is blunt: *"Photon has no
relation to steam… Hense the name STEAM EMULATOR not EVERY SERVICE EVER EXISTED EMULATOR."*
(`https://github.com/Detanup01/gbe_fork/issues/220`)

**Correction 2: the best real analogue is Lethal Company, and it confirms the recommended approach.** It uses
Steamworks.NET for lobbies **+ `Netcode.Transports.Facepunch.FacepunchTransport`** for transport — the same
transport family as Dimraeth — and is reported working under Goldberg over a VPN: *"I'm using Zerotier One with my
friends and custom broadcast IP. Everything works like a charm except voice chat."*
`https://github.com/Detanup01/gbe_fork/issues/86`

**Established from source** for any `com.community.netcode.transport.facepunch` game: the relay naming is
**nominal** under Goldberg, so success/failure tracks the *same* variables — peer discovery and AppID/port
agreement — which is exactly what the Lethal Company report demonstrates.

---

## 8. Source list

### Primary source code / binaries (read directly)
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.h`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/network.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking.h`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_sockets.h`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_networking_utils.h`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/steam_matchmaking.h`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/base.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/settings.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/local_storage.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/dll/dll.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/steamnetworkingsockets.cpp`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/build_win_release.bat`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/build_win_release_experimental.bat`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/build_win_release_experimental_steamclient.bat`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_release.txt` (mirror used for the `Notes:` structure check: `https://raw.githubusercontent.com/kameralarda/goldberg_emulator/master/Readme_release.txt`)
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/Readme_experimental_steamclient.txt`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/steamclient_loader/ColdClientLoader.ini`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/raw/master/files_example/steam_settings.EXAMPLE/custom_broadcasts.EXAMPLE.txt`
* `https://gitlab.com/api/v4/projects/Mr_Goldberg%2Fgoldberg_emulator/repository/tree?path=dll`
* `https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/merge_requests/41` (author-tested internet play)
* `https://raw.githubusercontent.com/Unity-Technologies/multiplayer-community-contributions/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs`
* `https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs`
* `https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamClient.cs`
* `https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/Networking/SocketManager.cs`
* `https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/Networking/ConnectionManager.cs`
* `https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/Generated/Interfaces/ISteamNetworkingSockets.cs`
* Local binaries: `GameAssembly.dll`, `global-metadata.dat`, `ScriptingAssemblies.json`, `steam_api64.dll`, `steam_api64.dll.bak`, `Player.log`

### Documentation / community
* Facepunch wiki — `https://wiki.facepunch.com/steamworks/SteamNetworkingSockets` and `…/SteamNetworkingSockets.CreateRelaySocket`
* Valve SDR (ownership quote) — `https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay`
* Valve Steamworks API overview (`steam_appid.txt` example `480`) — `https://partner.steamgames.com/doc/sdk/api`
* Valve example app (Spacewar/480) — `https://partner.steamgames.com/doc/sdk/api/example`
* Valve GameNetworkingSockets — `https://github.com/ValveSoftware/GameNetworkingSockets`
* cs.rin.ru "[Info] Dimraeth" — `https://cs.rin.ru/forum/viewtopic.php?f=10&t=155040`
* cs.rin.ru Goldberg main thread — `https://cs.rin.ru/forum/viewtopic.php?f=29&t=91627`
* cs.rin.ru steamworks-fix vs Goldberg taxonomy — `https://cs.rin.ru/forum/viewtopic.php?f=14&t=104597`
* OpenSteamTool — `https://raw.githubusercontent.com/OpenSteam001/OpenSteamTool/main/README.md`
* SteaMidra/SFF — `https://raw.githubusercontent.com/Midrags/SFF/main/README.md`
* gbe_fork #220 (Photon) — `https://github.com/Detanup01/gbe_fork/issues/220`; #86 (Lethal Company + ZeroTier) — `https://github.com/Detanup01/gbe_fork/issues/86`
* Facepunch #400 (ConnectP2P bound to Valve backend) — `https://github.com/Facepunch/Facepunch.Steamworks/issues/400`
* Tailscale broadcast unsupported — `https://forum.tailscale.com/t/broadcast-multicast-support/156`
* ZeroTier protocol — `https://docs.zerotier.com/protocol/`; issue #884 — `https://github.com/zerotier/ZeroTierOne/issues/884`
* Radmin VPN driver — `https://github.com/baptisterajaut/radmin-vpn-linux`
* Hamachi — `https://en.wikipedia.org/wiki/Hamachi_(software)`
* NetBird #1435 — `https://github.com/netbirdio/netbird/issues/1435`
* SoftEther L2 bridge — `https://www.softether.org/4-docs/1-manual/A/10.5`
* Tailscale CGNAT (`100.64.0.0/10`) — `https://tailscale.com/docs/reference/cgnat-interoperability`
* BepInEx 6 bleeding-edge — `https://builds.bepinex.dev/projects/bepinex_be`; MelonLoader Unity 6 issue — `https://github.com/LavaGang/MelonLoader/issues/1100`
* ROUNDS decompiled lobby — `http://git.warmcat.org/ROUNDS/diff/ROUNDS/Landfall.Network/ClientSteamLobby.cs`
* Dimraeth store data — `https://store.steampowered.com/api/appdetails?appids=2402680` (1–8 player player-hosted
  "seamless drop-in/drop-out" online co-op, no dedicated servers)

---

## 9. Caveats, corrections and adjudications

### 9.1 Corrections to earlier drafts of this report
1. **`steamnetworkingsockets64.dll`** — an earlier draft said "NOT FOUND in the Goldberg project". **Too strong.**
   The source and a CMake target exist, but the file is a **196-line unfinished stub** and is **not in the
   release**. Corrected in §4.2.
2. **The two `steamclient64.dll` files are different things** — one is a ~17-line shim, the other the full
   emulator. Corrected in §4.1.
3. **Per-VPN broadcast behaviour** — formerly flagged unverified; now sourced per product (§6.1).
4. **The AppID-480 route** — formerly framed as folklore-adjacent; it is a **documented, maintained technique**
   (Valve's own docs use 480 as the `steam_appid.txt` example; OpenSteamTool/SteamMidra/Unsteam/OnlineFix).
   Corrected in §5 and §6.6.
5. **The AppID file precedence** — I initially asserted the `480` file was simply inert. **Corrected:** Facepunch's
   `SteamClient.Init` sets the `SteamAppId`/`SteamGameId` env vars, which Goldberg honours, so the game's own
   serialized value may override `steam_appid.txt`. The effective appid is **UNDETERMINED** (§5.5).
6. **ROUNDS** — no longer used as an analogue; it is a Photon game (§7.3).

### 9.2 Two parallel agents' claims I adjudicated rather than averaged
* **"The game folder is CLEAN — no Goldberg files copied in"** (and a `backup/steam_api64.dll.original`
  referenced) — **REFUTED by direct byte-level verification.** `steam_api64.dll` is 1,958,912 bytes with
  Goldberg-only strings and **no** `Valve` string, and **no `backup` directory exists anywhere in the game tree**
  (checked recursively). That agent evidently inspected its own staging area under `%USERPROFILE%\DimraethOnlineFix\`.
* **"No `custom_broadcasts.txt` setting can ever give internet play"** — **REJECTED as over-broad.** There is
  correctly no relay/rendezvous, but `custom_broadcasts.txt` is exactly the mechanism that carries discovery
  across the internet, and **its own author reports having tested it successfully with friends** (MR !41), with
  multiple per-game cs.rin.ru guides corroborating. The accurate statement: *no **automatic** internet play;
  internet play via `custom_broadcasts.txt` + port-forwarding is documented and author-tested but fails behind
  CGNAT.* That agent's *other* conclusions (no relay exists; appid is a LAN peer-matching key; keep peers
  identical) are corroborated and adopted.

### 9.3 What I could NOT determine
1. **The game's effective AppID** (§5.5) — needs runtime determination.
2. **I did not run the game, load a mod, or test any two-machine scenario.** All runtime conclusions are inferred
   from source + on-disk artifacts + community claims. The one positive Dimraeth report is a **single user's
   claim**, not a reproduction.
3. **WAN over `custom_broadcasts.txt` + port-forwarding was not tested here** — it is author-tested upstream
   (MR !41) but not reproduced by me.
4. **No VPN is confirmed end-to-end with Goldberg + Dimraeth**; the closest analogue is the Lethal Company +
   ZeroTier report (§7.3). `NOT FOUND`: any Goldberg + Tailscale/NetBird report; any Dimraeth + Goldberg WAN
   report.
5. **No relay/SDR Goldberg fork exists** (§6.4) — a strong negative, though the ~342 GitLab forks were not
   exhaustively enumerated.
6. **Whether a legit Dimraeth owner can share a lobby with a 480-spoofer** — contradictory sources, UNRESOLVED.
7. **Anti-cheat / server-side validation is unassessed** — out of scope.
8. **`GameAssembly.dll` string caveat** (§2.3) — presence of a flat-API string proves a *binding* exists, not
   that the game calls it. And do **not** grep that DLL for managed transport names (false negatives — they live
   in `global-metadata.dat`).

### 9.4 Bottom line for this build
The transport path (`CreateListenSocketP2P` / `ConnectP2P` / `CreatePollGroup` / `SendMessageToConnection`) **is
emulated by Goldberg rather than stubbed**, which is why LAN co-op is genuinely viable — and why one cs.rin.ru
user reports it working. But Goldberg has **no relay**, so:
* For **internet co-op**, either restore the **genuine Valve DLL + real Steam client** (AppID-480 route → real
  Valve SDR; works behind CGNAT), or stay Steam-free and use a **VPN whose peers are added to
  `custom_broadcasts.txt`** (or port-forward 47584 UDP+TCP).
* Keep `force_listen_port.txt` = `47584` and keep every peer's `steam_appid.txt` / `steam_settings`
  **byte-identical** — a mismatch in either silently produces an **empty lobby list**.
* Expect "empty/hanging lobby" when discovery fails; that is the documented failure mode, not a transport bug.
