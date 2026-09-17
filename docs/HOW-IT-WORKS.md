# Research findings

Why the fix is built the way it is. Everything below was established from the
game's own files, the emulator's source, and measurement — not assumption.

Full trail in `research/`.

---

## The game's networking stack

Recovered from `Dimraeth_Data\ScriptingAssemblies.json` and the IL2CPP metadata:

- `Facepunch.Steamworks.Win64.dll` — the Steamworks wrapper
- `Facepunch Transport for Netcode for GameObjects.dll` — the community package
  `com.community.netcode.transport.facepunch`
- Unity Netcode for GameObjects over `Unity.Networking.Transport`
- Unity Services Relay / QoS / Authentication are present as packages but are not
  the path co-op uses

Lobbies come from `ISteamMatchmaking`. The metadata contains the full lobby flow
including password-protected lobbies (`_passwordIncorrectPrompt`,
`_SetPasswordProtected`), invites (`_InviteUserToLobby`, `_ActivateGameOverlayInviteDialog`),
kick/ban handling (`BanListManager`) and leaderboards.

### The transport uses the modern Steam networking API

`FacepunchTransport` calls `CreateRelaySocket<T>()` / `ConnectRelay<T>(steamId)`,
which resolve to `ISteamNetworkingSockets::CreateListenSocketP2P` and
`ConnectP2P` — **not** the legacy `SendP2PPacket` / `ReadP2PPacket` API.

This matters: Goldberg implements the modern path rather than stubbing it, which
is the whole reason the fix works at all. The emulator's source shows
`CreateListenSocketP2P`, `ConnectP2P`, `AcceptConnection`,
`SendMessageToConnection`, `CreatePollGroup` and `ReceiveMessagesOn*` all routed
through its own LAN layer.

Interface negotiation also lines up: the game requests
`SteamAPI_SteamNetworkingSockets_v008` and the emulator exposes 001–004, 006, 008
and 009.

---

## Why AppID 480

Spacewar is Valve's free, permanently installed public test app with networking
fully enabled. Re-badging a game as 480 means the app exercises only features a
free account legitimately owns, so nothing is forged at authentication. Valve's
own documentation uses `480` as its literal `steam_appid.txt` example.

**Under this emulator the number is a namespace label, not a capability.** The
emulator never contacts Valve, so 480 buys nothing functionally. What matters is
that every player uses the same AppID and the same discovery port, because peer
and lobby filtering key on it.

This is also why Steam shows "Dimraeth — Running" and never Spacewar: the Steam
client and the emulator are two independent Steam implementations that never
exchange information. A side effect worth keeping — the store page, cover art and
overlay all behave normally.

---

## Why the emulator is LAN-only without a VPN

From `dll/network.cpp`:

- Peer discovery broadcasts on UDP port **47584** (`DEFAULT_PORT`) to
  `255.255.255.255` and to every interface's subnet broadcast address, every 5
  seconds. Reliable payload goes over TCP.
- `CreateListenSocketP2P` and friends register a listen socket with the local
  `Networking` object. Nothing listens unless the game asks for one — which is why
  the emulator is silent in the main menu.
- `InitRelayNetworkAccess()` and `GetRelayNetworkStatus()` are **faked**: they
  report success without ever contacting Valve. There is no rendezvous service, no
  NAT traversal and no relay.

Hence the README's design constraint: a virtual LAN (ZeroTier, Radmin, Hamachi,
SoftEther) or port forwarding with `custom_broadcasts.txt`. Tailscale documents no
broadcast or multicast support, so it needs the unicast fallback.

`custom_broadcasts.txt` works because announces are also sent directly to each
listed address (`load_custom_broadcasts` → `resolve_ip` → `send_packet_to`), and a
unicast packet survives networks that drop broadcast.

---

## Why the release build has no logging

The release `steam_api64.dll` contains no `PRINT_DEBUG`, `STEAM_LOG` or
`log.txt` strings. The `debug_experimental` folder in the release package contains
only a Readme — the debug binaries are not distributed.

Its Readme also states the debug build "creates a huge STEAM_LOG.txt file ... and
will probably make the game lag so only use this to debug issues". Building it
would require compiling the emulator with protobuf-lite.

So diagnostics observe from outside: process state, sockets, the game's own Unity
log, and a decoder for the announce protocol. In practice this covers more than an
internal log would, because it shows what actually leaves the machine.

---

## The announce protocol

From `dll/net.proto`:

```proto
message Announce {
    enum Types { PING = 0; PONG = 1; }
    Types type = 1;
    repeated uint64 ids = 2;
    message Other_Peers { uint64 id = 1; uint32 ip = 2; uint32 udp_port = 3; uint32 appid = 4; }
    uint32 tcp_port = 3;
    repeated Other_Peers peers = 4;
    uint32 appid = 5;
}

message Common_Message {
    uint64 source_id = 1;
    uint64 dest_id = 2;
    oneof messages { Announce announce = 3; /* ... */ }
    uint32 source_ip = 128;
    uint32 source_port = 129;
}
```

### The proto3 trap

`Types.PING = 0` is the proto3 default, so **a PING packet carries no type field
at all**. A decoder that initialises the type to a non-zero sentinel and accepts
only 0/1 will discard every PING. Symptom: packets received, zero decoded.

Found in all three decoding tools during development. See `TESTING.md`.

---

## The one-hub rule on a single machine

`dll/network.cpp` binds `port + i` for `i` in `0..999` and leaves
`socket_reuseaddr()` commented out for its UDP socket. So on one machine **only
one process can own UDP 47584**; the others land on 47585, 47586, … and rely on
the 47584 owner to relay discovery.

Consequences:

- A diagnostic that binds `0.0.0.0:47584` **becomes the hub** and pushes the game
  onto a fallback port that nobody broadcasts to. This caused a false "no
  announce" report.
- Binding a **specific** address on the same port is still allowed by Windows and
  receives broadcast copies — that is the technique the diagnostics uses.

---

## Other things established along the way

- **Dimraeth has no Steam DRM.** No `.bind`, no `CSteamDRM`, no Steam strings in
  `Dimraeth.exe`. Confirmed by byte scan. This is the foundation of the whole
  approach.
- **Facepunch's `SteamClient.Init` sets `SteamAppId`/`SteamGameId`** environment
  variables before `SteamAPI_Init`. The emulator honours those, but only after
  `steam_settings\steam_appid.txt`, so the AppID stays 480 even when launched by
  Steam (which injects `2402680`).
- **The emulator's SteamID is random per machine**, from `RtlGenRandom`. Verified
  across three clean instances. This is why the project ships no SteamID.
- **A file in `StreamingAssets` has two leading spaces in its name**
  (`'  Pool Of Remembrance Music.bank'`). This matches a community note about a
  loading-screen workaround already present in the shipped build.

---

## Where the research came from

- The game's files: `ScriptingAssemblies.json`, `global-metadata.dat`,
  `Dimraeth.exe`, `steam_api64.dll`
- The emulator's source: `dll/network.cpp`, `dll/base.cpp`,
  `dll/settings_parser.cpp`, `dll/local_storage.cpp`, `dll/net.proto` and the
  Steam interface headers (snapshots in `research/goldberg-upstream/`)
- The Facepunch transport and Steamworks sources, upstream on GitHub

`research/` holds the full reports, with sources listed, including the claims that
were later corrected.
