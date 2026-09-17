# Goldberg Steam Emulator — `steamclient64.dll`, `steamnetworkingsockets64.dll`, ColdClientLoader, and the AppID 480 technique

**Prepared for:** Dimraeth online-fix (Unity IL2CPP, Steam AppID 2402680)
**Method:** local binary reverse engineering (PE parsing, string extraction, IL2CPP metadata scanning) + upstream source reading + web sources.
**Convention:** every claim carries a source. Anything not sourceable is marked `NOT FOUND` or `SPECULATION`.

---

## 0. Artifacts examined locally

Goldberg release extracted at `%USERPROFILE%\DimraethOnlineFix\downloads\goldberg\`
CI job id `4247811310` (`downloads/goldberg/job_id`), matching the CI job that produced the zip
(`https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/jobs/4247811310/artifacts/download`, per the
CI `page_deploy` step: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/.gitlab-ci.yml>).

Sizes measured by me on disk:

| Path | Bytes |
|---|---|
| `steam_api64.dll` | 1 958 912 |
| `steam_api.dll` | 1 488 896 |
| `experimental/steam_api64.dll` | 3 207 680 |
| `experimental/steam_api.dll` | 2 531 328 |
| `experimental/steamclient64.dll` | **89 600** |
| `experimental/steamclient.dll` | 74 240 |
| `experimental_steamclient/steamclient64.dll` | **3 019 776** |
| `experimental_steamclient/steamclient.dll` | 2 395 648 |
| `experimental_steamclient/steamclient_loader.exe` | 100 864 |
| `lobby_connect/lobby_connect.exe` | 1 400 320 |
| `source_code/source_code.bundle` | 5 731 790 |

These match the user's reported sizes. **No `steamnetworkingsockets64.dll` is present anywhere in the release zip.**
I verified by enumerating the zip: `[System.IO.Compression.ZipFile]::OpenRead(...)` on
`downloads/goldberg_latest.zip` — the word `networkingsockets` does not occur in any entry name.

---

# QUESTION A

## A1. `steam_api64.dll` mode vs `steamclient64.dll` mode, and what ColdClientLoader does

### A1.1 The two modes are the SAME emulator code, loaded at a different point

The decisive evidence is the upstream source. `steamclient.cpp` in the Goldberg repo is **17 lines**:

```cpp
#include "Windows.h"
#ifdef _WIN64
#define DLL_NAME "steam_api64.dll"
#else
#define DLL_NAME "steam_api.dll"
#endif

extern "C" __declspec( dllexport )  void *CreateInterface( const char *pName, int *pReturnCode )
{
    HMODULE steam_api = LoadLibraryA(DLL_NAME);
    void *(__stdcall* create_interface)(const char*) = (void * (__stdcall *)(const char*))GetProcAddress(steam_api, "SteamInternal_CreateInterface");
    return create_interface(pName);
}
```
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamclient.cpp>

So Goldberg's **`steamclient(64).dll` is not a reimplementation of Valve's Steam client.** It is a thin
forwarder whose only export is `CreateInterface`, which `LoadLibraryA`s Goldberg's own `steam_api64.dll`
and delegates to its `SteamInternal_CreateInterface`.

I confirmed this on the actual binary `experimental/steamclient64.dll` (89 600 bytes):
* It imports exactly **one** DLL: `KERNEL32.dll`.
* Its only referenced DLL names are `KERNEL32.dll`, `steam_api64.dll`, `steamclient64.dll`.
* Its export directory is 84 bytes — i.e. essentially `CreateInterface`.
* Its only recovered API strings are `CreateInterface` and `SteamInternal_CreateInterface`.

Contrast with `experimental_steamclient/steamclient64.dll` (3 019 776 bytes): 9 sections including
`.detourc`/`.detourd` (Microsoft Detours), imports `WINMM.dll`, `XINPUT9_1_0.dll`, `USER32.dll`,
`GDI32.dll`, `dwmapi.dll`, `WS2_32.dll`, `IPHLPAPI.DLL`, and exports **38** named symbols:

```
Breakpad_SteamMiniDumpInit, Breakpad_SteamSetAppID, Breakpad_SteamSetSteamID,
Breakpad_SteamWriteMiniDumpSetComment, Breakpad_SteamWriteMiniDumpUsingExceptionInfoWithBuildId,
CreateInterface, Steam_BConnected, Steam_BGetCallback, Steam_BLoggedOn, Steam_BReleaseSteamPipe,
Steam_ConnectToGlobalUser, Steam_CreateGlobalUser, Steam_CreateLocalUser, Steam_CreateSteamPipe,
Steam_FreeLastCallback, Steam_GSBLoggedOn, Steam_GSBSecure,
Steam_GSGetSteam2GetEncryptionKeyToSendToNewClient, Steam_GSGetSteamID, Steam_GSLogOff, Steam_GSLogOn,
Steam_GSRemoveUserConnect, Steam_GSSendSteam2UserConnect, Steam_GSSendSteam3UserConnect,
Steam_GSSendUserDisconnect, Steam_GSSendUserStatusResponse, Steam_GSSetServerType,
Steam_GSSetSpawnCount, Steam_GSUpdateStatus, Steam_GetAPICallResult, Steam_GetGSHandle,
Steam_InitiateGameConnection, Steam_LogOff, Steam_LogOn, Steam_ReleaseThreadLocalMemory,
Steam_ReleaseUser, Steam_SetLocalIPBinding, Steam_TerminateGameConnection
```

Those `Steam_*` names are the **Steam2 "flat" C API** that Valve's real `steamclient.dll` exported.
That is why that build is 3 MB: it is the *full emulator* built directly as a `steamclient` shared library
(including ImGui/overlay + Detours), plus a `flat.cpp` compatibility layer for the legacy API.

This is confirmed by the upstream build system: `CMakeLists.txt` defines two independent targets,
`steam_api` (from `dll/*.cpp`, `${PROTO_SRCS}`, plus detours/overlay when experimental) and
`steamclient` (from `steamclient.cpp` alone).
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/CMakeLists.txt>

So there are actually **three** distinct things in the release, not two:

| Artifact | What it really is |
|---|---|
| `steam_api64.dll` | The emulator, drop-in replacement for Valve's `steam_api64.dll`. |
| `experimental/steamclient64.dll` (89 KB) | **A 3-line forwarder** that loads `steam_api64.dll` from beside it. Requires `experimental/steam_api64.dll` to also be present. Exists so CPY-style cracks, which expect to patch a `steamclient64.dll`, have something to patch while the real work happens in the api DLL. |
| `experimental_steamclient/steamclient64.dll` (3 MB) | The full emulator built as a standalone `steamclient` library, used with `steamclient_loader.exe`. Does not need `steam_api64.dll`. |

### A1.2 What the `experimental` folder is for

Goldberg's own README of that folder states its purpose verbatim:

> "This is a build of my emulator that blocks all outgoing connections from the game to non LAN ips and lets you use CPY cracks that use the steam_api dll to patch the exe in memory when the SteamAPI_Init() method is called."
> "To use a CPY style crack just rename the steam_api(64).dll crack to cracksteam_api.dll or cracksteam_api64.dll depending on the original name and replace the steamclient(64) dll with the one from this folder."

Sources: `downloads/goldberg/experimental/Readme.txt`;
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental.txt>

**Critically for your question 3:** the experimental build *hard-blocks all non-LAN traffic*. Its readme says:

> "Since this blocks all non LAN connections doing things like hosting a cracked server for people on the internet will not work or connecting to a cracked server that's hosted on an internet ip will not work."
> Allowed ranges only: `10/8`, `127/8`, `169.254/16`, `172.16–172.31`, `192.168/16`, `224–255` (multicast/broadcast).

So `experimental/steamclient64.dll` is by construction **strictly less capable** network-wise than the plain
`steam_api64.dll`. It is an anti-telemetry / LAN-purity build, not an online-enabling build.

This is corroborated by the binary: `experimental/steam_api64.dll` imports `WS2_32.dll` and `IPHLPAPI.DLL`
(same as release) *plus* `WINMM.dll`, `XINPUT9_1_0.dll`, `USER32.dll`, `GDI32.dll`, `dwmapi.dll` and has
`.detourc`/`.detourd` sections — that is the overlay + hooks. Its string table contains
`\steam_settings\disable_lan_only.txt`, the exact opt-out named in the readme.

### A1.3 What `ColdClientLoader.ini` / `steamclient_loader.exe` do

Header of the file itself: `#My own modified version of ColdClientLoader originally by Rat431`
(`downloads/goldberg/experimental_steamclient/ColdClientLoader.ini`), and the first line of the source is
`// My own modified version of ColdClientLoader originally written by Rat431`
(<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamclient_loader/ColdClientLoader.cpp>).

The ini is:

```ini
[SteamClient]
Exe=game.exe
ExeRunDir=.
ExeCommandLine=
#IMPORTANT:
AppId=

SteamClientDll=steamclient.dll
SteamClient64Dll=steamclient64.dll
```

Reading `ColdClientLoader.cpp`, the loader does exactly this, in order:

1. Reads `ColdClientLoader.ini` from its own directory.
2. Reads keys `SteamClient64Dll`, `SteamClientDll`, `Exe`, `ExeRunDir`, `ExeCommandLine`, `AppId`.
3. **If `AppId` is empty it aborts** with `"You forgot to set the AppId."`
4. Sets the environment variables **`SteamAppId`** and **`SteamGameId`** to `AppId`
   (this is the documented way real Steam tells a game its appid — also documented in Goldberg's readme).
5. `CreateProcessW(ExeFile, CommandLine, ..., CREATE_SUSPENDED, ..., ExeRunDir, ...)` — starts the game
   **suspended**.
6. Opens `HKEY_CURRENT_USER\Software\Valve\Steam\ActiveProcess` (creating it if absent) and writes:
   * `ActiveUser` (REG_DWORD) = `0x03100004771F810D & 0xffffffff` — a **hardcoded** public SteamID, not yours
   * `pid` (REG_DWORD) = the loader's own PID
   * `SteamClientDll` (REG_SZ) = full path to `steamclient.dll`
   * `SteamClientDll64` (REG_SZ) = full path to `steamclient64.dll`
   * `Universe` (REG_SZ) = `"Public"`
7. `ResumeThread`.
8. After the game exits, restores the original `SteamClientDll`/`SteamClientDll64` values if the key
   already existed.

**Interpretation (source-backed):** the loader's real job is to plant Valve's own registry contract —
`HKCU\Software\Valve\Steam\ActiveProcess\{SteamClientDll,SteamClientDll64,ActiveUser,pid,Universe}` — so
that a game whose Steam DRM/wrapper asks Windows "where is the steamclient DLL? who is the active user?"
gets pointed at the emulator instead of at a running Steam. This is the "ColdClient" technique. A
third-party report confirms the registry route is the operative mechanism for steamclient mode:

> "For Windows, I needed a registry entry for `SteamClientDll64` to point at the emu's:
> `REG ADD "HKEY_CURRENT_USER\SOFTWARE\Valve\Steam\ActiveProcess" /v "SteamClientDll64" /t "REG_SZ" /d "C:\Program Files (x86)\Steam\emu\steamclient64.dll" /f`"

Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/issues/262>

Goldenberg's own readme for this folder:
> "This is a build of the experimental version of my emu in steamclient mode with an included loader. See both the regular and experimental readmes for how to configure it. Note that all emu config files should be put beside the steamclient dll. You do not need to put a steam_interfaces.txt file for the steamclient version of the emu. To use the loader, put both steamclient dlls and the loader in a folder and edit the config file. Make sure you put the right appid in the ini file."

Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental_steamclient.txt>

### A1.4 Is `steamclient64.dll` "a full replacement for Valve's `steamclient64.dll` used to run the game as a cracked Steam client"?

**Answer: partially, and the framing is misleading.**

* It *is* loaded at the same place Valve's `steamclient64.dll` is loaded, and it *does* export
  `CreateInterface` (plus, in the 3 MB self-contained build, the legacy `Steam_*` Steam2 flat API and
  `Breakpad_*` stubs). Source: my export enumeration above + `steamclient.cpp`.
* It is **not** a Steam client. It does not log in anywhere, has no Steam account, no licence database,
  no Steam Guard, no store/CDN/download functionality, no friends network. It serves `CreateInterface`
  out of the local emulator.
* The emulator's own self-description is the opposite of "cracked Steam client":
  > "An emulator that supports LAN multiplayer without steam."
  > "You replace the steam api .dll or .so with mine ... and then you can put steam in the trash and play your games either in single player **on LAN without steam**."
  Sources: `downloads/goldberg/Readme.txt` line 3;
  <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/README.md>
  GitLab project description (fetched via API `projects/10993694`):
  *"Steam emulator that emulates steam online features. Lets you play games that use the steam multiplayer apis **on a LAN without steam or an internet connection**."*
  <https://gitlab.com/Mr_Goldberg/goldberg_emulator>

So: **it is `steam_api64.dll` mode wearing a `steamclient64.dll` filename, so that games/wrappers which
load the client DLL by name can still be emulated.** Nothing more.

---

## A2. Is `steamnetworkingsockets64.dll` a real Valve DLL? Does Goldberg ship one?

### A2.1 The implementation lives inside `steam_api64.dll` — verified two ways

**(a) Valve's own SDK redistributables.** The public Steamworks SDK mirror
`rlabrecque/SteamworksSDK` contains, for `redistributable_bin/win64`, exactly two files:

```
steam_api64.dll   319128
steam_api64.lib   369416
```
Query: `https://api.github.com/repos/rlabrecque/SteamworksSDK/contents/redistributable_bin/win64`
(a direct `HEAD` on `.../win64/steamnetworkingsockets.dll` returns **404**).

Note: `ValveSoftware/steamworks-sdk` returns 404 — that repo does not exist publicly under that name
(`NOT FOUND`).

**(b) The actual Valve DLL shipped with your game.** `backup/steam_api64.dll.original` is **262 944 bytes**
(Valve's redistributable is 319 128 bytes for a different SDK version; same family). I enumerated its
export table: **995 named exports**, including the entire modern networking surface:

```
SteamAPI_ISteamNetworkingSockets_ConnectP2P
SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P
SteamAPI_ISteamNetworkingSockets_SendMessageToConnection
SteamAPI_ISteamNetworkingSockets_ConnectByIPAddress
SteamAPI_ISteamNetworkingSockets_CreateListenSocketIP
SteamAPI_ISteamNetworkingSockets_GetAuthenticationStatus
SteamAPI_ISteamNetworkingSockets_InitAuthentication
SteamAPI_ISteamNetworkingSockets_ReceivedRelayAuthTicket
SteamAPI_ISteamNetworkingSockets_FindRelayAuthTicketForServer
SteamAPI_ISteamNetworkingSockets_ConnectToHostedDedicatedServer
SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess
SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus
SteamAPI_ISteamNetworkingUtils_GetPingToDataCenter
SteamAPI_ISteamNetworkingUtils_GetPOPList
SteamAPI_SteamDatagramHostedAddress_Clear
SteamAPI_SteamNetworkingSockets_v008
SteamAPI_SteamGameServerNetworkingSockets_v008
SteamAPI_SteamNetworkingUtils_v003
...
```

**Conclusion (confirmed): Valve ships the SteamNetworkingSockets implementation inside
`steam_api64.dll`. There is no separate Valve `steamnetworkingsockets64.dll` in the SDK's
Windows redistributables.** The user's premise is correct.

### A2.2 Where the name `steamnetworkingsockets` *does* legitimately come from

Valve's public SDK header `isteamnetworkingsockets.h` documents a **standalone library** build mode,
distinct from the Steamworks-API build mode:

```c
// Using standalone lib
#ifdef STEAMNETWORKINGSOCKETS_STANDALONELIB
    static_assert( STEAMNETWORKINGSOCKETS_INTERFACE_VERSION[24] == '3', "Version mismatch" );
    STEAMNETWORKINGSOCKETS_INTERFACE ISteamNetworkingSockets *SteamNetworkingSockets_LibV13();
    inline ISteamNetworkingSockets *SteamNetworkingSockets_Lib() { return SteamNetworkingSockets_LibV13(); }
    STEAMNETWORKINGSOCKETS_INTERFACE ISteamNetworkingSockets *SteamGameServerNetworkingSockets_LibV13();
    ...
#endif

// Using Steamworks SDK
#ifdef STEAMNETWORKINGSOCKETS_STEAMAPI
    STEAM_DEFINE_USER_INTERFACE_ACCESSOR( ISteamNetworkingSockets *, SteamNetworkingSockets_SteamAPI, STEAMNETWORKINGSOCKETS_INTERFACE_VERSION );
    ...
#endif
#define STEAMNETWORKINGSOCKETS_INTERFACE_VERSION "SteamNetworkingSockets013"
```
Source: <https://raw.githubusercontent.com/rlabrecque/SteamworksSDK/master/public/steam/isteamnetworkingsockets.h>

That standalone form is the open-source **GameNetworkingSockets** library
(`libGameNetworkingSockets.so` on Linux, and a Windows DLL), which is a *different product* from the
Steamworks SDK: it talks plain UDP / your own signaling, not Steam's backend.
See <https://github.com/ValveSoftware/GameNetworkingSockets>.

`NOT FOUND`: I could not find any Valve-published Windows binary literally named
`steamnetworkingsockets64.dll`. Some third-party sites use that filename; I found one such
"DLL download" page (<https://www.ijinshan.com/dll/repairdll20250815091715.html>) but it is an
untrustworthy aggregator, not evidence of a Valve artifact, so I do not treat it as a source.

### A2.3 Does Goldberg ship/provide one? — **The target exists, but the release does not ship it**

Goldberg's `CMakeLists.txt` **does** define a `steamnetworkingsockets` target:

```cmake
set(LIB_STEAMNETWORKINGSOCKETS steamnetworkingsockets64)   # x64 Windows
...
add_library(${LIB_STEAMNETWORKINGSOCKETS} SHARED steamnetworkingsockets.cpp)
...
install(TARGETS ${LIB_STEAMNETWORKINGSOCKETS} RUNTIME DESTINATION ./)
```
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/CMakeLists.txt>

The README's install-tree documentation lists it:
```
|- (lib)steam_api(64).[dll|so]
|- (lib)steamclient(64).[dll|so]
|- (lib)steamnetworkingsockets(64).[dll|so]
```
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/README.md>

**However:** the release zip is produced by `build_windows` → `wine cmd /c build_win_release_test.bat`,
packaged by the `deploy_all` job. I verified the shipped zip contains **no** `steamnetworkingsockets*` file.
So the CMake path (a separate, manual/experimental build route) can produce the DLL, but **the official
release you downloaded does not include it.** Also note the CMake target is only enabled on Windows
(`EXCLUDE_FROM_ALL` on non-Windows).

### A2.4 What Goldberg's `steamnetworkingsockets64.dll` actually would do — and why it would NOT help you

This matters, because it is the kind of thing that looks like an "internet enablement" loophole.
`steamnetworkingsockets.cpp` (196 lines total) is in the upstream repo. Its real content:

```cpp
#define NETWORKING_SOCKETS_DLL
#define STEAM_API_EXPORTS
#include "sdk_includes/steam_gameserver.h"
```
then defines **placeholder virtual classes**:
```cpp
class ISteamNetworkingUtilsDll {
    virtual SteamNetworkingMicroseconds GetLocalTimestamp() = 0;
    //not sure if these are the correct functions
    virtual bool CheckPingDataUpToDate( float flMaxAgeSeconds ) = 0;
    virtual void a() = 0; ... virtual void j() = 0;
};
class ISteamNetworkingP2P { virtual void a() = 0; ... virtual void j() = 0; };
```
and then, in `SteamDatagramClient_Init_InternalV6`:
```cpp
ISteamClient *client = (ISteamClient *)fnCreateInterface(STEAMCLIENT_INTERFACE_VERSION);
networking_sockets = client->GetISteamGenericInterface(hSteamUser, hSteamPipe, "SteamNetworkingSockets001");
networking_utils = new Networking_Utils_DLL<ISteamNetworkingUtilsDll>( (ISteamNetworkingUtils *)client->GetISteamGenericInterface(hSteamUser, hSteamPipe, "SteamNetworkingUtils001") );
networking_p2p   = new Networking_P2P_DLL<ISteamNetworkingP2P>();
return true;
```
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamnetworkingsockets.cpp>
(local copy: `research/steamnetworkingsockets.cpp`)

Analysis:
* It is a **shim**, not a relay implementation. It obtains `SteamNetworkingSockets001` from the emulator's
  own `CreateInterface` and hands it back out. The "Steam Datagram" functions are name stubs that log and
  return `true`/`NULL`.
* `SteamNetworkingSockets()` and `SteamNetworkingUtils()` are exported as name-only getters.
* It does **not** export the actual versioned standalone entry point Valve's header declares
  (`SteamNetworkingSockets_LibV13()`). I enumerated the exports of Goldberg's `steam_api64.dll`; it has
  **zero** exports matching `_LibV`. So a game built against `STEAMNETWORKINGSOCKETS_STANDALONELIB` could
  not link to Goldberg's shim anyway.
* The author left `//not sure if these are the correct functions` in the source. This target is unfinished.

**Answer to "would a Goldberg install ever need it?":** No, not for a game built against the Steamworks SDK —
those games load `steam_api64.dll` and reach SteamNetworkingSockets through
`SteamAPI_SteamNetworkingSockets_v008/v009/v011/v012`, all of which Goldberg's `steam_api64.dll` **does**
export (I enumerated them; Goldberg exports 1196 names vs Valve's 995, including
`SteamAPI_SteamNetworkingSockets_SteamAPI_v012` and `SteamAPI_ISteamNetworkingSockets_SendMessageToConnection`).
It would only be "needed" by a hypothetical game that dynamically loads a DLL literally named
`steamnetworkingsockets64.dll` — and even then Goldberg's build is a stub, not a working stack.

---

## A3. Does `steamclient64.dll` mode give ANY real internet/relay capability the `steam_api64.dll` mode does not?

**No. The LAN-only limitation is identical, and in the `experimental` case it is strictly worse.**

### A3.1 Proof from source: `ConnectP2P` resolves SteamIDs through the LAN discovery table

The emulator's `ConnectP2P` implementation (file `dll/steam_networking_sockets.h`):

```cpp
HSteamNetConnection ConnectP2P( const SteamNetworkingIdentity &identityRemote, int nVirtualPort )
{
    ...
    const SteamNetworkingIPAddr *ip = identityRemote.GetIPAddr();
    if (identityRemote.m_eType == k_ESteamNetworkingIdentityType_SteamID) {
        PRINT_DEBUG("Steam_Networking_Sockets::ConnectP2P %llu\n", identityRemote.GetSteamID64());
        //steam id identity
    } else if (ip) { ... } else { return k_HSteamNetConnection_Invalid; }

    HSteamNetConnection socket = new_connect_socket(identityRemote, nVirtualPort, SNS_DISABLED_PORT);
    send_packet_new_connection(socket);
    return socket;
}
```
and `send_packet_new_connection`:
```cpp
//TODO: right now this only supports connecting with steam id, might need to make ip/port connections work in the future when I find a game that uses them.
...
uint64_t steam_id = connect_socket->second.remote_identity.GetSteamID64();
if (steam_id) {
    msg.set_dest_id(steam_id);
    return network->sendTo(&msg, true);      // <-- the LAN layer
}
```
and `set_steamnetconnectioninfo` reveals the address mapping:
```cpp
if (connect_socket->second.real_port != SNS_DISABLED_PORT) {
    pInfo->m_addrRemote.SetIPv4(network->getIP(connect_socket->second.remote_identity.GetSteamID()), connect_socket->first);
}
```
Sources: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/dll/steam_networking_sockets.h>,
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/dll/network.cpp>
(local copies `research/dll_steam_networking_sockets.h`, `research/dll_network.cpp`)

`network->sendTo(...)` is Goldberg's `Networking` class, whose peer table is populated exclusively by
UDP announce/broadcast. In `dll/network.cpp`:
```cpp
static void get_broadcast_info(uint16 port) { ... uint32 broadcast_ip = iface_ip | ~subnet_mask; ... }
static bool send_broadcasts(...) { ... main_broadcast.ip = INADDR_BROADCAST; ... send_packet_to(...); ... custom broadcasts ... }
void Networking::send_announce_broadcasts() { send_broadcasts(udp_socket, htons(DEFAULT_PORT), ...); ... }
```
and `handle_announce` stores `conn->udp_ip_port = ip_port;` — i.e. a SteamID becomes dialable only because
the peer previously announced itself over LAN broadcast (or to a `custom_broadcasts` target). There is
**no rendezvous server, no SDR, no relay, no NAT traversal code path** anywhere in that file.

`force_listen_port.EXAMPLE.txt` contains `47584` (the documented default; the user's premise is correct),
and `custom_broadcasts.EXAMPLE.txt` is plain IPs/one domain:
```
192.168.3.255
127.8.9.10
192.168.66.99
192.168.7.99
removethis.test.domain.com
```
Note those are all RFC1918 / loopback / subnet-broadcast addresses. A "custom broadcast" is still a
broadcast — it cannot cross the public internet.

### A3.2 Proof from the project's own words

* Release readme, line 131: **"You must all be on the same LAN for it to work."**
  (`downloads/goldberg/Readme.txt`; <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_release.txt>)
* GitLab project description: *"...on a LAN without steam or an internet connection."*
  (<https://gitlab.com/Mr_Goldberg/goldberg_emulator>)
* Experimental readme: *"Since this blocks all non LAN connections doing things like hosting a cracked server for people on the internet will not work..."*
  (<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental.txt>)

### A3.3 The active fork confirms it, and explicitly refuses to add online play

`gbe_fork` (Detanup01; 2 641 stars, last pushed 2026-09-16 — the de-facto maintained lineage:
`Mr_Goldberg → nexgen999 → Detanup01`, per <https://github.com/sysfce2/Steam_goldberg_emulator>) keeps the
LAN-only scope. Two issues are decisive:

**Issue #94 — "Wrapper Mode?"** (the exact technique you are asking about):
> User: "Can you add Wrapper mode? e.g. using original steam_api functions with wrap to appid like 480, just like online fix?"
> **Detanup01 (maintainer): "Nope. Otherwise this wouldnt be an option for offline/lan play. There is CreamAPI and possible other for this. The code is public here. Feel free to make it a project of yours."**
Source: <https://github.com/Detanup01/gbe_fork/issues/94>

**Issue #127 — "Emulation of online functions (lobby search) via spacewar (480)"**:
> "The point of this project is to enable LAN-only play, such as in LAN parties or families playing together. **Leave the online stuff to online-fix and the likes.**"
Source: <https://github.com/Detanup01/gbe_fork/issues/127> (comment by TheBotlyNoob, 2024-12-25)

**PR #457 — "feat: add relay to have option to use goldberg over internet relay"** — opened and **closed
within 16 seconds, never merged** (created 2026-03-12 22:01:52, closed 22:02:08, `merged: false`, empty body).
Source: <https://github.com/Detanup01/gbe_fork/pull/457>

Additionally, gbe_fork's own docs admit its matchmaking is LAN-only and that the "non-LAN" knob is broken:
> "By default, match making servers (which handles browsing for matches) will always return LAN servers list whenever the game inquires about the available servers with a specific type (Internet, Friends, LAN, etc...). You can make the emu return the proper/actual servers list for the given type, by modifying `configs.main.ini` and setting `matchmaking_server_list_actual_type-1`. **This is currently broken**."
Source: <https://github.com/Detanup01/gbe_fork/blob/dev/post_build/README.release.md>

**→ CONCLUSION A3: Using Goldberg as `steamclient64.dll` grants ZERO additional internet/relay
capability. Both modes run the same emulator whose `ConnectP2P` is implemented over LAN UDP discovery.
Every Goldberg variant is LAN-only by design, by the author's explicit intent, and the maintainer of the
active fork has publicly refused to change this.**

### A3.4 The one genuine (but non-Steam) way to bridge Goldberg across the internet

Because Goldberg maps `SteamID → LAN IP` and tolerates "VPN LAN", the *only* legitimate way to make it work
over the internet is to make the peers share an L2/L3 broadcast domain — a virtual LAN. The experimental
readme even endorses this scoped to standard LAN ranges:

> "This means the game should work without any problems for LAN play (**even with VPN LAN** as long as you use standard LAN ips (10.x.x.x, 192.168.x.x, etc...)"
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental.txt>

`NOT FOUND`: I found no official Goldberg documentation recommending a specific VPN product. Community
practice (Hamachi/Radmin/ZeroTier/Tailscale) is widely repeated but I could not source an authoritative
statement, so I mark the specific product list `SPECULATION`/folklore. The *mechanism* (virtual LAN) is
sourced; the *product choice* is not.

---

## A4. What is `lobby_connect.exe`, and does it work over the internet or LAN only?

**LAN only.** And note it is a *launcher helper*, not a networking component — it does not make
Goldberg reach the internet.

Upstream `Readme_lobby_connect.txt` in full:
> "This is a small tool that discovers people playing on the network using my emu and lets you launch your game with parameters that will connect you to their games."
> "This is necessary for some games (like stonehearth). It will also let you join games with lobbies that are not public."
> "Steam has something called rich presence (the connect key) that lets games tell your friends what command line parameters to run your game with to join their game."
> "Most steam games also let you join lobbies in game without having started the game by starting the game with `+connect_lobby <lobby id>`."
> "Just run this tool and follow the instructions then pick the exe of the game. Make sure that you have installed my emu on the game first and that it works or it won't work."
Source: `downloads/goldberg/lobby_connect/Readme.txt`;
<https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_lobby_connect.txt>

"Discovers people **on the network**" = via the same UDP broadcast peer table. It then relaunches your
game with `+connect_lobby <id>` / rich-presence connect parameters. In `CMakeLists.txt` it is built with
the same `dll/*.cpp` + protobuf networking sources and `-DLOBBY_CONNECT -DNO_DISK_WRITES`, and links
`ws2_32` + `iphlpapi` + `comdlg32` — i.e. it embeds the emulator's LAN discovery, and `comdlg32` is for the
"pick your game's exe" file dialog.
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/CMakeLists.txt>

gbe_fork states its role plainly as an overlay alternative for joining lobbies:
> "Alternatively, you can use the dedicated tool `lobby_connect` to join a game lobby."
Source: <https://github.com/Detanup01/gbe_fork/blob/dev/post_build/README.release.md>

**Caveat (SPECULATION, flagged):** Goldberg's *emulated* lobbies are not Valve lobbies. `lobby_connect`
only enumerates emulator peers on the LAN, so it cannot discover or join a lobby hosted on Valve's backend.
Its value is limited to the same LAN/VPN-LAN scope as the rest of the emulator. I did not find a source
explicitly stating "lobby_connect internet does not work", so I infer this from the discovery mechanism
instead of quoting it — treat as high-confidence inference, not a quote.

---

# QUESTION B — the "Steam AppID 480 (Spacewar)" technique

## B0. Preliminary: your target game's actual networking path (important context I established)

I scanned `Dimraeth.exe`'s IL2CPP payload `GameAssembly.dll` (103 245 824 bytes) and the Unity assembly
manifest. This is not speculation — these are direct observations:

`Dimraeth_Data/ScriptingAssemblies.json` (204 assemblies) includes:
```
Facepunch.Steamworks.Win64.dll
Facepunch Transport for Netcode for GameObjects.dll
Unity.Netcode.Runtime.dll
Unity.Networking.Transport.dll
Unity.Services.Relay.dll
Unity.Services.Authentication.dll
...
```

`GameAssembly.dll` contains the strings `Facepunch.Steamworks.Win64.dll`,
`Facepunch Transport for Netcode for GameObjects.dll`, and the full Steamworks.NET flat API surface for
both networking stacks, e.g.:
```
SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P
SteamAPI_ISteamNetworkingSockets_ConnectP2P
SteamAPI_ISteamNetworkingSockets_SendMessageToConnection
SteamAPI_ISteamNetworkingSockets_ReceiveMessagesOnConnection
SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess
SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus
SteamAPI_ISteamMatchmaking_CreateLobby / JoinLobby / RequestLobbyList / SendLobbyChatMsg / SetLobbyData ...
SteamAPI_ISteamNetworking_SendP2PPacket / AcceptP2PSessionWithUser / AllowP2PPacketRelay (legacy)
SteamAPI_SteamNetworkingSockets_SteamAPI_v009 / v011 / v012
```

`globalgamemanagers.assets` contains a serialized MonoBehaviour type `FacepunchTransport` in namespace
`Netcode.Transports.Facepunch`, described as `Facepunch Transport for Netcode for GameObjects`.

And the transport in question (`FacepunchTransport.cs`, by Nico Thomas & Floris van Onna, using
Facepunch.Steamworks 2.3.2) is **relay-only** and **defaults to appid 480**:

```csharp
[Tooltip("The Steam App ID of your game. Technically you're not allowed to use 480, but Valve doesn't do anything about it so it's fine for testing purposes.")]
[SerializeField] private uint steamAppId = 480;

[Tooltip("The Steam ID of the user targeted when joining as a client.")]
[SerializeField] public ulong targetSteamId;

private void Awake() { SteamClient.Init(steamAppId, false); ... }

public override bool StartClient()
{
    connectionManager = SteamNetworkingSockets.ConnectRelay<ConnectionManager>(targetSteamId);
    ...
}
public override bool StartServer()
{
    socketManager = SteamNetworkingSockets.CreateRelaySocket<SocketManager>();
    ...
}
private IEnumerator InitSteamworks()
{
    yield return new WaitUntil(() => SteamClient.IsValid);
    SteamNetworkingUtils.InitRelayNetworkAccess();
    ...
    userSteamId = SteamClient.SteamId;
}
```
Source: <https://github.com/nicholas-maltbie/multiplayer-community-contributions/blob/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs>
README (authors, Facepunch.Steamworks 2.3.2): <https://github.com/nicholas-maltbie/multiplayer-community-contributions/blob/main/Transports/com.community.netcode.transport.facepunch/README.md>

And Facepunch's wrappers are thin aliases over the Steamworks API:
```
SteamNetworkingSockets.ConnectRelay<T>(SteamId serverId, int virtualport = 0)
    -> Internal.ConnectP2P( ref identity, virtualport, options.Length, options );
SteamNetworkingSockets.CreateRelaySocket<T>(int virtualport = 0)
    -> Internal.CreateListenSocketP2P( virtualport, options.Length, options );
```
Source: <https://github.com/Facepunch/Facepunch.Steamworks/blob/master/Facepunch.Steamworks/SteamNetworkingSockets.cs>

**Consequence:** Dimraeth's multiplayer is `NGO → FacepunchTransport → SteamNetworkingSockets.ConnectP2P(
SteamID ) / CreateListenSocketP2P`, plus Steam lobbies. It is the *exact* architecture you asked about in
question B. This means the AppID 480 question is not academic for this project — it is the crux.

---

## B1. What Spacewar (AppID 480) officially is, and why 480 specifically

**This is now CONFIRMED from Valve's own documentation** (a parallel research pass retrieved Valve's
partner docs via a text proxy because `partner.steamgames.com` renders bodies client-side):

* Valve's docs page is literally titled **"Steamworks API Example Application (SpaceWar)"**:
  > "In order to help developers understand the usage of the Steamworks API we have included source code for a fully functional version of the classic **Spacewar!** multi-player shooter game."
  > Demonstrated features include: "… **Matchmaking (Both lobbies and server browser)** · Multi-Player Authentication … · **Networking** …"
  Source: <https://partner.steamgames.com/doc/sdk/api/example>
* Valve's SDK index lists it as a first-class component: `steamworksexample - Steamworks API Example Application (SpaceWar)`.
  Source: <https://partner.steamgames.com/doc/sdk>
* Valve's Steam Networking feature page names Spacewar as the reference for the modern sockets API:
  > "See the Steamworks API Example Application (SpaceWar) for an example of using the ISteamNetworkingSockets for client-server communication."
  Source: <https://partner.steamgames.com/doc/features/multiplayer/networking>
* Same page confirms the AppID: "…must contain a single line with the game's AppID **(for your games, Valve will assign each an AppID, the example game's AppID is 480)**."
  Source: <https://partner.steamgames.com/doc/sdk/api/example>

### B1.1 The origin of the crack practice is Valve's own documentation

**This is the single most important finding for "why 480".** Valve's Steamworks API Overview documents
`steam_appid.txt` and uses `480` as the *literal example content*:

> "Create the a text file called `steam_appid.txt` next to your executable containing just the App ID and nothing else. **This overrides the value that Steam provides.** You should not ship this with your builds. Example:
>
> `480`"

Source: <https://partner.steamgames.com/doc/sdk/api>

So "set `steam_appid.txt` to 480" is not a crack invention at all — **it is copy-pasted from Valve's own
documentation and the SDK's bundled example file.** The crack community then combined this sanctioned
AppID-override mechanism with a free, universally-owned appid.

### B1.2 It is free and has no store page

* `https://store.steampowered.com/api/appdetails?appids=480` → `{"480":{"success":false}}`
* `https://store.steampowered.com/app/480/` and `https://steamcommunity.com/app/480` both redirect to the
  store home page — no store page, no community hub.
* Installable free via the Steam client URI `steam://install/480` (reported by third-party games
  journalism 游研社/yystv.cn: <https://www.yystv.cn/p/12722>).
* `NOT FOUND`: an explicit Valve sentence "Spacewar is free". Established by absence of a price page plus
  the third-party report.
* **`NOT FOUND`:** any Valve statement addressing, condoning, condemning, or detecting the 480-redirect
  practice.

### B1.3 Community/practice evidence for the 480 trick

* The Facepunch transport's own inline comment — first-hand evidence of *developer* practice and Valve's
  non-enforcement:
  > "The Steam App ID of your game. **Technically you're not allowed to use 480, but Valve doesn't do anything about it so it's fine for testing purposes.**"
  Source: <https://github.com/nicholas-maltbie/multiplayer-community-contributions/blob/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs>
* Concrete crack instructions:
  * Dark Souls: Prepare to Die Edition guide: *"Create a text file called 'steam_appid.txt'… write '480' in it… This will fool Steam into thinking that Dark Souls is a game called 'Spacewar'; this will enable online functionality for Dark Souls."* + *"Launch the game exe directly; do not launch through Steam."*
    <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/>
  * Schedule I (2025): *"Friend invite opens Spacewar instead of Schedule1"*; community: *"Spacewar is the 'game' many pirated cracks use to launch multiplayer in Steam."*
    <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693>
  * Stardew Valley showing as "spacewar": <https://steamcommunity.com/app/413150/discussions/0/3198115500348801920/>
* Side effect reported by journalism (citing SteamDB): Spacewar's concurrent-player count spikes coincide
  with major cracked multiplayer releases (78k Feb-2023 Sons of the Forest; >100k Jan-2024 Palworld;
  ~138k Mar-2025 Schedule I). **Treat the numbers as third-party reporting — not independently verified
  here** (`steamdb.info` returned HTTP 403 and I did not use it). Sources:
  <https://www.yystv.cn/p/12722>, <https://www.giga.de/entertainment/63-jahre-nach-release-steam-spiel-spacewar-stellt-neuen-rekord-auf-aus-kuriosem-grund--01JQTZVGF3Q5D274Y8Y2RF8TDG>

**Why 480 and not another appid:** (a) it is free and universally "owned", so Valve's ownership check
passes for every Steam user; (b) Valve itself points developers at 480 for `ISteamNetworkingSockets`;
(c) Valve documents no per-app SDR opt-in for Steam apps, so there is no documented reason 480 would lack
relay. `SPECULATION (strict)` on the last point — see §B2.4.

---

## B2. Does running as AppID 480 give access to Valve's real Steam Datagram Relay / lobbies / matchmaking?

### B2.1 What Valve's SDK says about the rendezvous requirement

**The decisive quote, from Valve's official Steam Datagram Relay page** (this is the exact answer to
"what are the prerequisites"):

> "Rendezvous messages are sent through Steam, so **if the player or server loses their connection to Steam, the connection cannot be made**. Also, **Steam does not restrict who can attempt to connect, aside from verifying that the player is signed into Steam and owns the game.**"

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

Also from the same page:

> "Steam Datagram Relay (SDR) is Valve's virtual private gaming network. … **Relaying the traffic protects your servers and players from DoS attack, because IP addresses are never revealed.** All traffic you receive is authenticated, encrypted, and rate-limited. … This relay network can be used for **both peer-to-peer traffic and dedicated servers**."
> "For peer-to-peer traffic on Steam, **all you need to do to take advantage of SDR is to use APIs such as CreateListenSocketP2P and ConnectP2P. Steam will take care of everything else.**"
> "We use a proprietary public key infrastructure (PKI) to authenticate clients and servers. **Players are issued individual, short-term certificates, tied to their specific player identity. Steam takes care of this.**"

Steam's `ISteamNetworkingSockets` reference page repeats the ownership condition and the partner gate:
> "**CreateListenSocketP2P** — Like CreateListenSocketIP, but clients will connect using ConnectP2P. **The connection will be relayed through the Valve network.** … **Any user that owns the app and is signed into Steam will be able to attempt to connect to your server.**"
> "An opensource version of this API is available on github. You can use it for whatever purpose you want. **To use the Valve network you need to be a Steam partner and use the version in the Steamworks SDK.**"

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

The certificates cannot be obtained offline — `steamnetworkingtypes.h` documents for
`ESteamNetworkingAvailability`:
> "`k_ESteamNetworkingAvailability_Waiting = 2, // We're waiting on a dependent resource to be acquired. (E.g. we cannot obtain a cert until we are logged into Steam. …)`"

Source: <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/include/steam/steamnetworkingtypes.h>

And the versioned header you quoted (from Valve's public GameNetworkingSockets repo, tag `1.0.0`,
`SteamNetworkingSockets002`) reads:
```cpp
/// Begin connecting to a server that is identified using a platform-specific identifier.
/// This requires some sort of third party rendezvous service, and will depend on the
/// platform and what other libraries and services you are integrating with.
///
/// At the time of this writing, there is only one supported rendezvous service: Steam.
/// Set the SteamID (whether "user" or "gameserver") and Steam will determine if the
/// client is online and facilitate a relay connection.  Note that all P2P connections on
/// Steam are currently relayed.
virtual HSteamNetConnection ConnectP2P( const SteamNetworkingIdentity &identityRemote, int nVirtualPort ) = 0;
```
Source: <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/1.0.0/include/steam/isteamnetworkingsockets.h>
**Caveat on your quote:** that wording is the `1.0.0`/`SteamNetworkingSockets002` era text. Current SDK
headers reworded it to: *"This uses the default rendezvous service, which depends on the platform and
library configuration. (E.g. on Steam, it goes through the steam backend.)"* — same substance. Cite the
version you rely on.
Source (current): <https://raw.githubusercontent.com/rlabrecque/SteamworksSDK/master/public/steam/isteamnetworkingsockets.h>

Goldberg's own source **quotes this same doctrine back** in its doc comments — because Goldberg copied
Valve's headers — which is a neat confirmation that the up-front rendezvous is the Steam backend:
```cpp
/// This requires some sort of third party rendezvous service, and will depend on the
/// platform and what other libraries and services you are integrating with.
/// At the time of this writing, there is only one supported rendezvous service: Steam.
/// Set the SteamID (whether "user" or "gameserver") and Steam will determine if the
/// client is online and facilitate a relay connection. Note that all P2P connections on
/// Steam are currently relayed.
```
Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/dll/steam_networking_sockets.h>

**So: `ConnectP2P(SteamID)` is not a peer-to-peer technique in the NAT-punching sense alone — it is a
request to Steam to find/relay to that SteamID. The Steam backend is the signalling channel, and all
P2P on Steam is relayed.**

### B2.2 Prerequisites for 480 to actually work

From Valve's documentation:

1. **A genuine, running Steam client.** *"The Steam client isn't running. A running Steam client is required to provide implementations of the various Steamworks interfaces."*
   Source: <https://partner.steamgames.com/doc/sdk/api>
2. **A logged-in Steam account that owns the AppID.** *"Ensure that you own a license for the App ID on the currently active Steam account. Your game must show up in your Steam library."* — plus the SDR wording *"verifying that the player is signed into Steam and owns the game."*
   Sources: <https://partner.steamgames.com/doc/sdk/api>, <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>
   **For 480 this condition is trivially satisfied because 480 is free and universally owned.**
3. **The genuine `steam_api64.dll` and the genuine Steam client process.** Valve describes the mechanism:
   *"When the Steamworks API initializes it finds the actively running steam client process and loads `steamclient.dll` from that path… all Steam API calls are transparently marshaled and sent via an RPC/IPC mechanism."*
   Source: <https://partner.steamgames.com/doc/sdk/api>
4. `InitRelayNetworkAccess()` must be called and reach `k_ESteamNetworkingAvailability_Current`
   (poll `GetRelayNetworkStatus`):
   > "void InitRelayNetworkAccess(); — If you know that you are going to be using the relay network (for example, because you anticipate making P2P connections), call this to initialize the relay network. If you do not call this, the initialization will be delayed until the first time you use a feature that requires access to the relay network… Typically initialization completes in a few seconds."
   Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils>

### B2.2b How Valve's validation actually works — the crux

Valve's backend validates **that the logged-in account owns the app whose AppID the client session
claims.** It does **not** (per any source found) validate that the running binary is that app's actual
binary. That is exactly why the 480 redirect works:

* `steam_appid.txt` is a documented, Valve-sanctioned AppID override: *"This **overrides the value that Steam provides**."* (<https://partner.steamgames.com/doc/sdk/api>)
* Valve documents no binary/hash attestation for the AppID claim; what Steam checks is *ownership*.
* `SteamEncryptedAppTicket` exists so a *server* can verify a *client account's* ownership of an app
  (`ISteamUser::RequestEncryptedAppTicket` + Web API `ISteamUserAuth/AuthenticateUserTicket`). It verifies
  **account ownership of an AppID**, not the client binary. (<https://partner.steamgames.com/doc/api/SteamEncryptedAppTicket>)

**Therefore the popular folklore — "cracked games use Spacewar because Valve's servers can't tell a
cracked DLL from a real one" — is imprecise in a way that matters.** The accurate statement is: *nothing
needs to be fooled at the authentication layer.* The account really owns AppID 480 and the Steam client
really is legitimate. What is spoofed is only **which app the local process claims to be**.

**Does Valve's backend "reject appid 480 clients that aren't genuine"?** `NOT FOUND` — no Valve statement,
policy, or credible analysis shows binary validation or enforcement for 480. Practice is pervasive and
visible in Spacewar's inflated player counts. Community-observed, not officially sanctioned.
`NOT FOUND`: any Valve statement addressing, condoning, condemning, or detecting the practice.

### B2.3 The two scenarios, contrasted precisely

**(a) Game running as AppID 480 through a REAL Steam client (with an emulator only patching ownership /
appid, not replacing the API): → YES, real SDR/relay/lobbies are usable.**
The process still calls into Valve's real `steamclient64.dll` (via official `steam_api64.dll`) with a valid
Steam session; the crack only (i) makes Steam treat the game as owned so it will launch, and (ii) makes the
*reported* appid 480 so the backend allocates Spacewar's networking. The SteamID you pass to `ConnectP2P`
is a real SteamID, and Steam relays it.
Independent corroboration that this is exactly how the modern tools do it — LumaCore, the DLL SteaMidra
injects into Steam, documents:
> "1. Copies `steamclient64.dll` to `bin\lcoverlay.dll` so it can be loaded and hooked independently of the live client."
> "4. Installs over 40 Detours hooks plus VEH captures into the loaded `lcoverlay.dll` copy, covering IPC dispatch, package ownership, license patching, Denuvo auth, manifest binding, **network packet rewriting**, and online-fix game language synchronization."
> "For online-fix games, LumaCore synchronizes the game's language setting to **Spacewar (480)** and `LumaCorePayload.dll` is injected into the game process via CreateProcess hooks to handle EOS bridge and lobby redirection."
> "`LumaCorePayload.dll` — injected into game processes for **online-fix multiplayer** (EOS bridge, lobby redirection)"
Sources: <https://github.com/Midrags/SFF/blob/main/LumaCore/README.md>,
<https://github.com/Midrags/SFF/blob/main/README.md> (which also says: *"**LC Online Fix** — toggle `-onlinefix` on a chosen App ID in `localconfig.vdf`. ... **LumaCore handles the appid-480 redirect at launch** so the overlay, Steam Input, and screenshots still tag the real game."* and that the "Fixes & Bypasses" feature is *"Achievement-safe — only adds bypass DLLs, **leaves the Steam API intact**"*).

**Concrete evidence that SDR P2P under 480 genuinely works:** a developer report of using
`CreateRelaySocket`/`ConnectRelay` under AppID 480 with Steamworks:
> "both initing steamworks under appid 480… CreateRelaySocket… ConnectRelay" and *"If I test the same project from different devices (or virtual machine) with different steam accounts connected, then everything works just fine."*
Source: <https://github.com/Facepunch/Facepunch.Steamworks/issues/686>
I independently verified `ConnectRelay`→`ConnectP2P` and `CreateRelaySocket`→`CreateListenSocketP2P` in
Facepunch's source (see B0), so this report is genuinely on the SDR path. The same report notes that
connecting to **your own** server from the same account/machine fails — that is normal SDR behaviour
(rendezvous is keyed to SteamID), not a 480 limitation.
An older (2017) developer report describes P2P with NAT punch-through under 480 using the legacy
`ISteamNetworking` API: <https://steamcommunity.com/discussions/forum/9/135510393195379614/>

So the "appid 480" trick is real, and its identifying signature is: **the real Steam client and a real
logged-in account stay in the loop; only ownership and the reported appid are manipulated inside the
running Steam client.** That is why these tools must hook/inject into `steam.exe` itself.

**(b) Standalone Goldberg `steam_api64.dll` drop-in: → NO. LAN-only, and appid 480 changes nothing.**
Goldberg replaces the API DLL wholesale, so `ConnectP2P` is answered by Goldberg and resolved through its
own UDP-broadcast peer table (demonstrated in A3.1). AppID 480 vs 2402680 is irrelevant: Goldberg never
contacts Valve, so there is no backend that could care which appid it is. The `steam_appid.txt` value in
Goldberg mode only affects local `Steam_Apps`/stats/cloud paths and the emulator's announce packet's
`appid` field, which is used to match peers (`if (!conn || conn->appid != msg->announce().appid())` in
`handle_announce`). Setting 480 in Goldberg mode is therefore at best neutral and at worst *harmful*:
it is a **peer-matching key**, so two people who set different appids will not see each other, and setting
480 for Dimraeth would make you collide with every other 480 game on the LAN
(also see the readme's warning: *"Do not run more than one steam game with the same appid at the same time
on the same computer"*, `downloads/goldberg/Readme.txt` line 134).

gbe_fork's own docs independently refute the emulator-to-Valve theory: matchmaking "will always return LAN
servers list" and the real-type option is "currently broken", and app tickets are self-generated
(`new_app_ticket=1`, `gc_token=1` in `configs.main.ini`) rather than obtained from Valve.
Source: <https://github.com/Detanup01/gbe_fork/blob/dev/post_build/README.release.md>

### B2.4 Does 480 specifically have SDR enabled?

**Findings in order of strength:**
1. Valve names Spacewar as the `ISteamNetworkingSockets` example — <https://partner.steamgames.com/doc/features/multiplayer/networking>
2. Valve's Spacewar page lists **Networking**, **Matchmaking (lobbies and server browser)** and
   **Multi-Player Authentication** as demonstrated features — <https://partner.steamgames.com/doc/sdk/api/example>
3. A developer successfully used `CreateListenSocketP2P`/`ConnectP2P` under AppID 480 across two machines
   with different accounts — <https://github.com/Facepunch/Facepunch.Steamworks/issues/686>
4. A 2017 developer report of P2P with NAT punch-through under 480 — <https://steamcommunity.com/discussions/forum/9/135510393195379614/>
5. Valve documents **no per-app SDR enablement step** for Steam apps.

**NOT FOUND:** any Valve statement that 480 specifically has SDR/relay enabled or disabled; any
Valve-documented restriction on using 480 for `ISteamNetworkingSockets` testing.
→ "SDR is enabled for 480" is the correct working assumption but rests on **inference** from Valve's
docs plus community reports. **Label: SPECULATION (strict)** for the explicit enablement claim.

**Bottom line for B:** the claim in scenario (a) is **TRUE but only under a real Steam client**; the
claim does **not** transfer to scenario (b). AppID 480 is not a capability that travels with the number —
it is a request routed to Valve's backend *by a genuine Steam client*. An emulator that answers Steam
calls locally cannot convert appid 480 into internet multiplayer.

### B2.5 Practical gotchas for testing under 480

* You must run the **real Steam client**, logged into a real account, with the real `steam_api64.dll`.
* `steam_appid.txt` containing `480` must sit next to the executable (or set `SteamAppId`/`SteamGameId`).
* **You cannot test P2P against yourself on one machine/account** — use two machines or two accounts.
  (<https://github.com/Facepunch/Facepunch.Steamworks/issues/686>, and by design: SDR rendezvous is keyed to SteamID)
* Remove `steam_appid.txt` before shipping: *"Make sure to remove the `steam_appid.txt` file when uploading the game to your Steam depot!"* (<https://partner.steamgames.com/doc/sdk/api>)
* **You share AppID 480's lobby/matchmaking namespace with everyone else using 480**, including pirates.
  Unreal developers have asked Valve for a dedicated test AppID precisely because of this:
  *"Any chance for an official UnrealEngine Steam Test AppId instead of the notorious Spacewar Id?"*
  <https://forums.unrealengine.com/t/any-chance-for-an-official-unrealengine-steam-test-appid-instead-of-the-notorious-spacewar-id/53881>

---

## B3. "Wrapper mode": the exact technical term for the AppID-480-through-real-Steam approach

This is worth naming explicitly because it is the pivot of your Question B.

gbe_fork issue #94 asks the maintainer for precisely the capability that would make scenario (a) work under
an emulator:

> User: "Can you add Wrapper mode? e.g. **using original steam_api functions with wrap to appid like 480, just like online fix?**"
> Detanup01: "Nope. Otherwise this wouldnt be an option for offline/lan play. There is CreamAPI and possible other for this."
Source: <https://github.com/Detanup01/gbe_fork/issues/94>

gbe_fork issue #526 asks again, and the *title itself* treats OnlineFix's method as distinct from Goldberg's:
> "[Feature] Using some features from Unsteam, implementation of online fix 4eighty"
> "would like a implementation of online fix and online fix ini like in unsteam, if needed be by using coldclient method"
Source: <https://github.com/Detanup01/gbe_fork/issues/526>

So "wrapper mode" = forward to the *original* Valve `steam_api` implementation while overriding the appid
(→ 480). That is a fundamentally different architecture from Goldberg's "replace and emulate". Goldberg
does the latter, deliberately, and its maintainer considers the former out of scope.
`NOT FOUND`: I could not retrieve the body/comments of #526 (the API returned the issue but no comments),
so I cannot report a maintainer response there.

---

## B4. What OnlineFix is, and how it differs from Goldberg — **CONFIRMED: it is the real-Steam-client + fake-AppID architecture, not Goldberg, not a private relay**

A dedicated research pass produced a full report at
`C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\OnlineFix_Technical_Report.md`. Headline findings:

### B4.1 Identity

`OnlineFix64.dll`'s own PE version resource says:

```
CompanyName     = Online-Fix.Me
FileDescription = Online-Fix Steamclient
LegalCopyright  = (C) 2021-2023, 0xdeadc0de
FileVersion     = 1.3.2.0
```
Source: <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>

The product string **"Online-Fix Steamclient"** is decisive: it targets the Steam *client* interface, not
merely a LAN API. It is simultaneously a Steam emulator, a multiplayer patch, and an
ownership/DRM workaround.

### B4.2 Shipped files — best concrete example (`SpeedyCoder1192/mcb-dlls`, exactly 4 files)

| File | Bytes | Role |
|---|---|---|
| `OnlineFix.ini` | 323 | config |
| `OnlineFix64.dll` | 10 817 536 | core |
| `dlllist.txt` | 15 (contents: `OnlineFix64.dll`) | load list |
| `winmm.dll` | 506 368 | proxy DLL |

Source (tree): <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>
`OnlineFix.ini` verbatim: `[Main]` / `#Language=en-US` / `ProductId=9NBLGGH2JHXJ` + `[Hashes]` with two
SHA-512 pins: <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini>

**Load chain: `winmm.dll` proxy → reads `dlllist.txt` → loads `OnlineFix64.dll`.** A matching error string
exists in the wild: *"failed to load onlinefix64.dll **from the list** error 126/225"*
(<https://mywebpc.ru/windows/onlinefix64-dll/>). Other examples (Dying Light 2, Dark Souls 3 / Seamless
Co-op) confirm `OnlineFix.ini` + `dlllist.txt` + an 11–12 MB `OnlineFix64.dll`
(<https://github.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/blob/main/docs/common_problem.md>).

**Does it ship `steam_api64.dll`? YES — and it is a CUSTOM OnlineFix build, not Goldberg:** a signed
`steam_api64.dll` with `ProductName = Steam Wrapper`, `CompanyName = Online-Fix`, ~6 MB, first seen
2020-12-27 (<https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066>).
`steamclient64.dll` as a **literal shipped filename**: **NOT FOUND** — "steamclient" appears only as the
product description and as a `WINEDLLOVERRIDES` key.

**`steam_appid.txt` must be ABSENT.** OnlineFix uses `OnlineFix.ini`'s `FakeAppId` instead; a Linux guide
instructs: *"VERIFY THAT A FILE CALLED `steam_api.txt` IS NOT IN THE GAME'S FOLDER, IF IT IS REMOVE IT"*
(<https://feddit.it/post/504803/4598192>).

### B4.3 Mechanism — **(a): real Valve backend via AppID spoofing.** (b), (c), (d) rejected

Confirmed config keys: **`RealAppId`** and **`FakeAppId`** (plus `Language`, `ExtraProtection`,
`OnlineFixLauncher.ini`'s `ExeName`).
Sources: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>,
<https://bbs.3dmgame.com/thread-6329126-1-1.html>

**The decisive proof that it is Valve's backend and not a private relay:** users switch `FakeAppId`
between *genuinely existing free Valve appids* and observe **different player populations**:
> "`FakeAppId=480` 是 spacewar 的 / `FakeAppId=1836450` 是 DEMO 的 / `FakeAppId=314970` 是 AGE 的"
> — <https://bbs.3dmgame.com/thread-6382542-1-1.html> (restated at <https://bbs.3dmgame.com/thread-6387209-1-15.html>)
> plus *"appid分散之后，更加少了"* ("after the appid split, there are even fewer players")

Those are real Valve apps: 480 = Spacewar; 1836450 = Monster Hunter Rise Sunbreak Demo; 314970 = Age of
Conquest IV. **Different AppID ⇒ different backend matchmaking pool ⇒ only Valve's backend can produce
that behaviour.** No OnlineFix relay endpoint exists in any source (**NOT FOUND**).

Corroboration from the sibling Unsteam fix design: it *"makes the game run disguised as Steam's free
placeholder title **Spacewar (AppID 480)**, borrowing Steam's official network… **requires a logged-in
Steam client**"*, with config `real_app_id=<game>` / `fake_app_id=480`, and the success indicator being
your Steam profile showing "playing Spacewar": <https://blog.syouiti.com/游戏破解指南/>

**Dual AppID use proven in code** (`onlinefix-linux`): it reads `RealAppId` + `FakeAppId`, rewrites them
into a `[OnlineFix Linux]` section, disables `ExtraProtection`, and launches with
`'SteamOverlayGameId' => ... ?? 480` while fetching cover art by the **real** AppID.
Sources: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>,
<https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>

**Caveat — OnlineFix is not one thing.** Non-Steam product lines exist: **EOS/Epic**
(`EOSAuthHooker64.dll`, `EOSSDK-Win64-Shipping.dll`, `Custom.dll`) and **Photon** (`PhotonBridge.dll`,
`launch_data.of*`). For those, the network path is the real **Epic/Photon** backend with the user's
account — not Steam, and still not an OnlineFix relay.
Sources: <https://threatinfo.net/companies/Online-Fix>,
<https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md>
This matches online-fix.me's own site taxonomy ("Play via: Steam / Epic Games Store / Microsoft Store /
GOG Galaxy / LAN / Steam Remote Play", plus an `/officialservers/` category): <https://online-fix.me/>

**SDR specifically:** strongly implied by the architecture, but **I found no packet capture confirming
SDR usage** — flag as inferred, not observed.

### B4.4 Steam client requirement — **CONFIRMED: installed + running + logged in, and `steam_appid.txt` absent**

* `FilesWorker.php` aborts if `which steam` fails, and if Steam is not running it **starts Steam itself**
  and then **waits up to 7 minutes for `~/.steam/steam/config/loginusers.vdf` to change** (= waits for
  login); otherwise it errors "Steam is not running".
  <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>
* The Dark Souls 3 docs' most common OnlineFix error is literally *"Steam is not launched"*.
  <https://github.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/blob/main/docs/common_problem.md>
* A launcher even ships a toggle literally labelled **"Bypass «Steam not running»"** (which monkey-patches
  `steamfix64.dll` with a stub) — the existence of that toggle is itself proof of the requirement.
  <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/forms/gameSettings.php>

### B4.5 OnlineFix vs Goldberg — **not a fork; no relationship found**

* Different authorship/branding: OnlineFix = `Online-Fix.Me` / `0xdeadc0de`, releases tagged
  `-0xdeadc0de` / `-OFME` (<https://threatinfo.net/files/OnlineFix64.dll-891d5812ed5120816ddc9b0f5ece5d1a>).
* No Goldberg code, no `steam_settings` model, no attribution in any OnlineFix file listing found.
* **Opposing network models:** Goldberg = LAN-only, no Steam. OnlineFix = internet, Steam required.
* Third parties treat them as **separate alternatives** — SteaMidra lists "Crack a game" → `gbe_fork` and
  "Multiplayer Fix" → online-fix.me as different pipelines
  (<https://github.com/Midrags/SFF/blob/main/README.md>), and `onlinefix-linux`'s README does likewise.
* They **converge on one architectural slot** — hijacking the client's `steamclient64.dll` via
  `HKCU\SOFTWARE\Valve\Steam\ActiveProcess\SteamClientDll64` (documented in Goldberg's own tracker:
  <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/work_items/262>) — convergence, not descent.
* **NOT FOUND:** any mutual statement by the OnlineFix and Goldberg authors about each other.

### B4.6 Security posture — heavily flagged, no clean bill of health

* **24/71** VirusTotal engines flag an `OnlineFix64.dll` (SHA-256 `27eb85e4…`); Microsoft's detection name
  is **`HackTool:Win32/GameHack!MSR`**: <https://mywebpc.ru/windows/onlinefix64-dll/>
* A separate aggregated scan reports **47/75** detections:
  <https://tools.malwaretips.com/file-scan/d687fcd5d3942793218036cde1b8c39d4ada63d2f4aa08778fc2722a4dc65f99>
* Family detections include serious classes: `Ransom.Wacapew` (on `ForzaHorizon5_loader.exe`),
  `Trojan.Downloader`, `Trojan.Packed`, `Hack.Patcher`:
  <https://threatinfo.net/companies/Online-Fix>
* Packed/obfuscated: custom `.of0`/`.of1`/`.of2` PE sections; one variant's 10.7 MB `.of2` at entropy
  **7.79** flagged packed/encrypted; one sample has **no signature at all**:
  <https://tria.ge/260614-cjlqsacv3j/static1>
* **NOT FOUND:** any vendor *analysis* proving a bundled miner/adware/stealer. The figures above are
  detection counts, not analyses. But there is equally **no clean bill of health** — OnlineFix is
  closed-source, obfuscated, inconsistently signed, unaudited, and sits between a **live logged-in
  Steam/Epic session** and the game. OnlineFix's own ecosystem advises throwaway accounts:
  *"if you're worried about your main account, use a fake account"* (<https://www.xmy7.com/sjyx/80210.html>)

### B4.7 Other projects in this space

* **`ZzEdovec/onlinefix-linux` (OFLL)** — the single most valuable public source. An open-source launcher
  whose PHP encodes the exact filename grammar, INI keys, AppID translation, `WINEDLLOVERRIDES`
  construction, the Steam-login wait, and the 480 overlay default.
  <https://github.com/ZzEdovec/onlinefix-linux> (AUR: <https://aur.archlinux.org/packages/onlinefix-linux-launcher-bin>)
* **`SpeedyCoder1192/mcb-dlls`** — archived verbatim 4-file OnlineFix payload. <https://github.com/SpeedyCoder1192/mcb-dlls>
* **`Midrags/SFF` (SteaMidra)** — independent client-level AppID-480 redirect. <https://github.com/Midrags/SFF>
* **`hydralauncher/hydra` #2379** — community-documented `WINEDLLOVERRIDES` strings. <https://github.com/hydralauncher/hydra/issues/2379>
* **`metrixmedia/SteamEmulator`** — has a `steamnetworkingsockets.cpp` (same stub concept as Goldberg's):
  <https://github.com/metrixmedia/SteamEmulator/commit/3f8ce69b6dc6819abd61c274c57184df9470cdb4>
* **"SpacewarWar" — NOT FOUND.** No such project exists; the real concept is Spacewar AppID 480.
* **"Goldberg internet multiplayer relay" — NOT FOUND and contrary to design** (see A3.3).
* **NOT FOUND:** any open-source reimplementation of OnlineFix's specific technique.

### B4.8 Explicit gaps (do not guess past these)

1. No authoritative OnlineFix-published file manifest for any game — all lists are third-party reconstructions.
2. No documented release shipping a literal `steamclient64.dll`.
3. `OnlineFix.ini` `[Hashes]` semantics and `.of0/.of1/.of2` section contents: undocumented.
4. No OnlineFix/Goldberg author statements about each other.
5. No vendor *analysis* (vs. signature counts) for/against miner/adware/stealer.
6. No packet capture confirming SDR usage.
7. API-level detail of how the `steamclient` interface is implemented: the export table is tiny
   (`OnlineFix`, `QueryApiImpl`), so the interface surface is likely resolved dynamically at runtime —
   **SPECULATION**.
8. `DL2_Offline.bat` vs `DL2_Online.bat` — whether it toggles AppID or the client hook is unproven.

---

# Consolidated answers

## Question A

1. **`steamclient64.dll` in the release is not a cracked Steam client.** Goldberg's `steamclient` target is
   a 17-line forwarder (`steamclient.cpp`) exporting only `CreateInterface`, which loads Goldberg's own
   `steam_api64.dll` and delegates to `SteamInternal_CreateInterface`. The 89 600-byte
   `experimental/steamclient64.dll` is exactly that (single import: `KERNEL32.dll`; only DLL name
   referenced besides itself: `steam_api64.dll`). The 3 019 776-byte
   `experimental_steamclient/steamclient64.dll` is the full emulator compiled in "steamclient" form —
   38 exports including `CreateInterface`, the legacy Steam2 `Steam_*` flat API, and `Breakpad_*`, with
   Detours sections and ImGui/overlay imports. `steamclient_loader.exe` + `ColdClientLoader.ini`
   (Goldberg's modified version of Rat431's loader) launch the game `CREATE_SUSPENDED`, set the
   `SteamAppId`/`SteamGameId` env vars from the ini's `AppId`, and plant
   `HKCU\Software\Valve\Steam\ActiveProcess\{SteamClientDll,SteamClientDll64,ActiveUser,pid,Universe}`
   so a DRM wrapper asking Windows where the Steam client is gets pointed at the emulator.
   **Purpose: compatibility with DRM/CPY-style wrappers that load `steamclient(64).dll` by name — not
   additional capability.**
2. **`steamnetworkingsockets64.dll` is not a Valve SDK redistributable.** Valve's Windows SDK
   redistributables contain only `steam_api64.dll` (+`.lib`), and the shipped Valve `steam_api64.dll` in
   this very game (262 944 bytes, 995 exports) contains the complete `SteamAPI_ISteamNetworkingSockets_*`
   and `SteamAPI_ISteamNetworkingUtils_*` surface. **Your premise is confirmed.** The name comes from
   Valve's `STEAMNETWORKINGSOCKETS_STANDALONELIB` mode (`SteamNetworkingSockets_LibV13()`), which is the
   open-source GameNetworkingSockets product, not Steamworks. Goldberg **does** have a CMake target named
   `steamnetworkingsockets`, and its README documents installing it — but **the official release zip does
   not contain it**, and the source `steamnetworkingsockets.cpp` is an unfinished forwarding stub that
   re-exports the emulator's own `SteamNetworkingSockets001` (with `//not sure if these are the correct
   functions` left in). Goldberg's `steam_api64.dll` exports no `_LibV*` symbols, so the shim is not even
   link-compatible with Valve's standalone API. **A normal Goldberg install never needs it.**
3. **No.** Both modes run the identical emulator; `ConnectP2P` with a SteamID is implemented by
   `send_packet_new_connection` → `network->sendTo(...)`, i.e. Goldberg's own UDP LAN discovery/announce
   table, with no rendezvous/relay code path. The `experimental` folder is explicitly *more* restrictive:
   it hooks socket functions to block every destination outside RFC1918/loopback/broadcast ranges.
   Author's words: "You must all be on the same LAN for it to work." The active fork's maintainer refused
   "wrapper mode" outright (issue #94: **"Nope. Otherwise this wouldnt be an option for offline/lan play"**),
   told a user asking for Spacewar-480 lobby emulation to **"Leave the online stuff to online-fix and the
   likes"** (issue #127), and an internet-relay PR (#457) was closed unmerged 16 seconds after opening.
4. **`lobby_connect.exe` is LAN-only.** It enumerates other players on the network via Goldberg's LAN
   discovery and relaunches your game with `+connect_lobby <id>` / rich-presence connect parameters. It is
   a join convenience for games that need a command-line connect argument — not a networking component and
   not an internet bridge.

## Question B

* **Scenario (a) — real Steam client + patched ownership/appid 480: the claim is TRUE, and the mechanism
  is Valve's backend.** Valve's official SDR page states: *"Rendezvous messages are sent through Steam, so
  if the player or server loses their connection to Steam, the connection cannot be made. Also, **Steam
  does not restrict who can attempt to connect, aside from verifying that the player is signed into Steam
  and owns the game.**"* (<https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>)
  Valve's header: `ConnectP2P` "uses the default rendezvous service … on Steam, it goes through the steam
  backend", and "all P2P connections on Steam are currently relayed". Prerequisites: a genuine running
  Steam client, a logged-in account, and `InitRelayNetworkAccess()` reaching `Current`. Corroborated by
  LumaCore/SteaMidra, which hooks Valve's real `steamclient64.dll` inside `steam.exe`, does "network
  packet rewriting", and "handles the appid-480 redirect at launch", and by a developer report of
  `CreateRelaySocket`/`ConnectRelay` working under 480 across two machines/accounts
  (<https://github.com/Facepunch/Facepunch.Steamworks/issues/686>).
* **Scenario (b) — standalone Goldberg `steam_api64.dll`: the claim is FALSE.** AppID 480 confers nothing,
  because Goldberg never contacts Valve. In Goldberg, the appid is a *local peer-matching key* in the LAN
  announce packet, so changing it to 480 can only break or pollute LAN discovery. There is no path from
  Goldberg to SDR, lobbies, or matchmaking. gbe_fork's own docs confirm: matchmaking "will always return
  LAN servers list" and the non-LAN option is "**currently broken**"; app tickets are self-generated.
* **Why 480:** **the practice is copied from Valve's own documentation** — Valve's Steamworks API Overview
  uses `480` as the literal example content of `steam_appid.txt` ("This overrides the value that Steam
  provides… Example: `480`", <https://partner.steamgames.com/doc/sdk/api>), and the SDK ships Spacewar
  with AppID 480 (<https://partner.steamgames.com/doc/sdk/api/example>). 480 is free, universally owned,
  and is the app Valve itself points at for `ISteamNetworkingSockets`. A Facepunch transport ships 480 as
  its default with the comment that it's "technically not allowed … but Valve doesn't do anything about it".
* **Does Valve reject non-genuine 480 clients?** `NOT FOUND`. Valve validates **account ownership of the
  claimed AppID**, not the running binary — and every Steam user genuinely owns 480. The popular folklore
  "cracked DLLs fool Valve's servers" is wrong: *nothing needs fooling at the auth layer*; only the
  process's claimed app identity is spoofed. `NOT FOUND`: any Valve statement addressing, condoning,
  condemning, or detecting the 480 practice; any Valve statement that SDR is enabled for 480 specifically
  (that is a strong inference — **SPECULATION (strict)**).
* **OnlineFix uses real Steam relay, not its own relay — CONFIRMED.** `OnlineFix64.dll` metadata says
  `FileDescription = Online-Fix Steamclient`; `OnlineFix.ini` exposes `RealAppId` + `FakeAppId`; and users
  switching `FakeAppId` between real free Valve appids (480 Spacewar / 1836450 / 314970) observe
  **different player populations** — only possible on Valve's backend. It requires a Steam client that is
  installed, running **and logged in** (launcher code waits up to 7 minutes for `loginusers.vdf` to
  change), and it requires **`steam_appid.txt` to be ABSENT**. It is **not** a Goldberg fork and has **no**
  private relay.
* **Do crack groups recommend 480 for SteamNetworkingSockets P2P/lobby games?** Yes — and in the strongest
  possible form for your case: the Facepunch NGO transport, which is what Dimraeth actually uses,
  **hard-codes 480 as its default** `steamAppId` and is **relay-only** (`ConnectRelay`→`ConnectP2P`,
  `CreateRelaySocket`→`CreateListenSocketP2P`). This is why "480 for SteamNetworkingSockets games" is
  standard advice.

---

## Actionable implication for the Dimraeth online-fix

Dimraeth = `NGO` + `FacepunchTransport` (relay-only: `ConnectP2P`/`CreateListenSocketP2P`) + Steam lobbies
(`CreateLobby`/`JoinLobby`/`RequestLobbyList`). Its multiplayer is structurally dependent on Valve's
rendezvous. Therefore:

* **A pure Goldberg fix can only ever be LAN / virtual-LAN play.** That is not a configuration problem you
  can solve with `steam_appid.txt`, `force_listen_port.txt`, or `custom_broadcasts.txt`; the relay call
  site has no non-LAN implementation in Goldberg.
* **To get real internet co-op you need the real Steam client in the loop** (wrapper-style: real Valve
  DLLs + owned/patched appid + a SteamID that Steam will relay), which is precisely the OnlineFix/LumaCore
  model and precisely what Goldberg's maintainer refuses to implement.
* **Do not set `steam_appid.txt` to 480 under Goldberg** — in Goldberg the appid is the LAN peer-matching
  key and must match the peers you intend to play with.

---

## Source index

Goldberg upstream
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator> (project + description)
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/README.md>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_release.txt>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental.txt>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_experimental_steamclient.txt>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_lobby_connect.txt>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/CMakeLists.txt>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/.gitlab-ci.yml>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamclient.cpp>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamnetworkingsockets.cpp>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/steamclient_loader/ColdClientLoader.cpp>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/dll/steam_networking_sockets.h>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/dll/network.cpp>
* <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/issues/262>

gbe_fork (active fork)
* <https://github.com/Detanup01/gbe_fork>
* <https://github.com/Detanup01/gbe_fork/issues/94> (maintainer refuses wrapper mode)
* <https://github.com/Detanup01/gbe_fork/issues/127> ("Leave the online stuff to online-fix")
* <https://github.com/Detanup01/gbe_fork/pull/457> (relay PR closed unmerged)
* <https://github.com/Detanup01/gbe_fork/issues/526> (asks for online-fix behaviour)
* <https://github.com/Detanup01/gbe_fork/blob/dev/post_build/README.release.md>
* <https://github.com/sysfce2/Steam_goldberg_emulator> (fork lineage)

Valve
* <https://raw.githubusercontent.com/rlabrecque/SteamworksSDK/master/public/steam/isteamnetworkingsockets.h>
* <https://api.github.com/repos/rlabrecque/SteamworksSDK/contents/redistributable_bin/win64>
* <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/1.0.0/include/steam/isteamnetworkingsockets.h> (the exact wording you quoted)
* <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/include/steam/steamnetworkingtypes.h>
* <https://partner.steamgames.com/doc/sdk/api/example> (Spacewar = AppID 480, the official SDK sample)
* <https://partner.steamgames.com/doc/sdk> (SDK index lists `steamworksexample`)
* <https://partner.steamgames.com/doc/sdk/api> (the `Example: 480` steam_appid.txt origin; Steam client + licence requirements)
* <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay> (the decisive SDR prerequisite quote)
* <https://partner.steamgames.com/doc/features/multiplayer/networking> (names Spacewar as the sockets example)
* <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>
* <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils>
* <https://partner.steamgames.com/doc/api/steamnetworkingtypes>
* <https://partner.steamgames.com/doc/api/SteamEncryptedAppTicket>
* <https://store.steampowered.com/api/appdetails?appids=480> (returns `success:false` — no store page)
* <https://github.com/ValveSoftware/GameNetworkingSockets>

Dimraeth's actual transport stack
* <https://github.com/nicholas-maltbie/multiplayer-community-contributions/blob/main/Transports/com.community.netcode.transport.facepunch/Runtime/FacepunchTransport.cs>
* <https://github.com/nicholas-maltbie/multiplayer-community-contributions/blob/main/Transports/com.community.netcode.transport.facepunch/README.md>
* <https://github.com/Facepunch/Facepunch.Steamworks/blob/master/Facepunch.Steamworks/SteamNetworkingSockets.cs>
* <https://github.com/Facepunch/Facepunch.Steamworks/issues/686> (SDR P2P under 480 works across two accounts)
* <https://wiki.facepunch.com/steamworks/SteamNetworkingSockets>
* <https://wiki.facepunch.com/steamworks/SteamNetworkingSockets.ConnectRelay>
* <https://wiki.facepunch.com/steamworks/SteamNetworking>

OnlineFix / appid-480 tooling and evidence
* <https://online-fix.me/>
* <https://github.com/Midrags/SFF/blob/main/README.md>
* <https://github.com/Midrags/SFF/blob/main/LumaCore/README.md>
* <https://github.com/Midrags/SFF/blob/main/CHANGELOG.md>
* <https://github.com/OpenSteam001/OpenSteamTool>
* <https://github.com/ZzEdovec/onlinefix-linux>
* <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php> (Steam-login wait; aborts without Steam)
* <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php> (RealAppId/FakeAppId)
* <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/forms/gameSettings.php> ("Bypass «Steam not running»")
* <https://github.com/SpeedyCoder1192/mcb-dlls> (verbatim 4-file OnlineFix payload)
* <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini>
* <https://github.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/blob/main/docs/common_problem.md>
* <https://github.com/hydralauncher/hydra/issues/2379>
* <https://bbs.3dmgame.com/thread-6382542-1-1.html> (FakeAppId channel switching ⇒ different player pools)
* <https://blog.syouiti.com/游戏破解指南/> (Unsteam: Spacewar 480, requires logged-in Steam)
* <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8> (OnlineFix64.dll metadata)
* <https://threatinfo.net/companies/Online-Fix>
* <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066> (OnlineFix custom "Steam Wrapper" api dll)
* <https://mywebpc.ru/windows/onlinefix64-dll/> (24/71 detections; `HackTool:Win32/GameHack!MSR`)
* <https://tria.ge/260614-cjlqsacv3j/static1> (packed PE, entropy 7.79)
* <https://www.yystv.cn/p/12722> (journalism: Spacewar as a pirate proxy appid; steam://install/480)
* <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/> (Dark Souls steam_appid.txt = 480 guide)
* <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693> (Schedule I / Spacewar)
* <https://steamcommunity.com/discussions/forum/9/135510393195379614/> (2017 dev report: P2P under 480)
* <https://forums.unrealengine.com/t/any-chance-for-an-official-unrealengine-steam-test-appid-instead-of-the-notorious-spacewar-id/53881> (shared 480 namespace problem)

Companion reports produced during this investigation
* `OnlineFix_Technical_Report.md` — full OnlineFix teardown
  (`C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\OnlineFix_Technical_Report.md`)
* `steam-appid-480-sdr-report.md` — full AppID 480 / SDR / Spacewar report with a confirmed-vs-folklore table
  (`C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\steam-appid-480-sdr-report.md`)

Local evidence
* `%USERPROFILE%\DimraethOnlineFix\downloads\goldberg\` (release + readmes)
* `%USERPROFILE%\DimraethOnlineFix\backup\steam_api64.dll.original` (Valve 262 944 B, 995 exports)
* `C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\GameAssembly.dll`
* `C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\Dimraeth_Data\ScriptingAssemblies.json`
* `C:\Program Files (x86)\Steam\steamapps\common\Dimraeth\Dimraeth_Data\globalgamemanagers.assets`
* `%USERPROFILE%\DimraethOnlineFix\research\` (downloaded upstream sources used for the code claims)

---

## Appendix: what I could NOT determine (explicit NOT FOUND list)

1. Any Valve statement that SDR/relay is enabled for AppID 480 specifically. (Inference only — flagged SPECULATION.)
2. Any Valve statement addressing, condoning, or detecting the 480-redirect practice.
3. Any Valve statement that Spacewar is "free" (established only by absence of a store page + third-party report).
4. Any Valve-published Windows binary literally named `steamnetworkingsockets64.dll`. The standalone
   `SteamNetworkingSockets_LibV13()` concept exists in headers, but I found no Valve release artifact with
   that filename, and no Valve SDK redistributable containing it.
5. Any Goldberg/GitLab issue, README, or commit stating that steamclient mode adds internet capability.
   (All evidence points the other way.)
6. Any release of gbe_fork shipping a working internet relay. PR #457 exists only as a closed, unmerged stub.
7. An authoritative OnlineFix-published file manifest; `OnlineFix64.dll` internal API details; whether
   OnlineFix uses SDR specifically (no packet capture).
8. A specific VPN product officially recommended by Goldberg for bridging LAN play over the internet.
   (The *mechanism* — virtual LAN with standard RFC1918 addresses — is sourced from Goldberg's readme;
   the *product list* is community folklore and is NOT sourced.)
