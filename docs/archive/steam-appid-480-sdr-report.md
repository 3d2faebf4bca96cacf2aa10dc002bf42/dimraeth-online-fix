# Technical Report — Steam AppID 480 ("Spacewar") and Valve's Networking Backends

**Scope:** What AppID 480 is, what Steam Datagram Relay (SDR) is and requires, whether a game running as AppID 480 can use Valve's real relay/lobby/matchmaking servers, why crack groups set `steam_appid.txt` = 480, and what backend `CreateListenSocketP2P`/`ConnectP2P` actually needs.

**Method:** Web research only (`web_search` / `web_fetch`). Primary sources are Valve's own Steamworks documentation (`partner.steamgames.com/doc/...`) and Valve's public `GameNetworkingSockets` repository. Secondary sources (community forums, third-party tools, games journalism) are labelled as such.

**Access limitations encountered (disclosed):**
- `partner.steamgames.com` serves main page content via JS; direct fetches returned only the navigation sidebar. The doc bodies below were retrieved through the `r.jina.ai` text-extraction proxy of the same official URLs. The rendered URLs are official Valve pages.
- `steamdb.info` returned HTTP 403 plus an automated notice instructing that SteamDB has no public API and that requests should stop. **No SteamDB data is used in this report.** Where SteamDB figures are cited, they are cited as *reported by a third party*, not as verified from SteamDB.
- `developer.valvesoftware.com/wiki/Steam_Datagram_Relay` is behind an "Anubis" anti-bot proof-of-work and could not be read. Consequently no claim here rests on the Valve Developer Community wiki.
- `gamedev.stackexchange.com/questions/208988` returned HTTP 403 and was not used.

Anything not sourced is marked **NOT FOUND** (could not be found) or **SPECULATION** (inference, clearly flagged).

---

## 1. What is Steam AppID 480 "Spacewar"?

### 1.1 Confirmed: it is Valve's official Steamworks sample/example application

Valve's own documentation page is titled **"Steamworks API Example Application (SpaceWar)"**:

> "In order to help developers understand the usage of the Steamworks API we have included source code for a fully functional version of the classic **Spacewar!** multi-player shooter game. It is a simple 2D game with support for up to 4 players and provides a perfect opportunity to showcase many of the APIs available in the Steamworks SDK."

The same page enumerates the Steamworks features the sample demonstrates:

> Cloud · Community Integration (avatars, friends names, etc) · Crash Reporting · Friends · HTML Surface · Inventory · Leaderboards · **Matchmaking (Both lobbies and server browser)** · Multi-Player Authentication (4 players supported in-game) · **Networking** · Stats & Achievements · Voice Chat

Source: <https://partner.steamgames.com/doc/sdk/api/example>

The Steamworks SDK landing page lists it as a first-class SDK component:

> "**steamworksexample** - [Steamworks API Example Application (SpaceWar)]"

Source: <https://partner.steamgames.com/doc/sdk>

And the Steam Networking feature page recommends it as the reference implementation for the modern sockets API:

> "See the [Steamworks API Example Application (SpaceWar)] for an example of using the [ISteamNetworkingSockets] for client-server communication."

Source: <https://partner.steamgames.com/doc/features/multiplayer/networking>

**Answer: Yes.** Spacewar (480) is Valve's official Steamworks sample/test application, shipped inside the Steamworks SDK, and it is the app Valve points to for `ISteamNetworkingSockets` usage.

### 1.2 Confirmed: the AppID is 480, and it is the canonical `steam_appid.txt` example

From the example page:

> "This file ships with the SDK example and should be present if you run from within Visual Studio or directly from the Debug or Release sub directories. When you are launching the game from the exe directly, outside of the Steam UI this file must be present and must contain a single line with the game's AppID **(for your games, Valve will assign each an AppID, the example game's AppID is 480)**."

Source: <https://partner.steamgames.com/doc/sdk/api/example>

And this is the single most important finding in this report — Valve's **"Steamworks API Overview"** page, in the section documenting `steam_appid.txt`, uses `480` as the literal example content:

> "Create the a text file called `steam_appid.txt` next to your executable containing just the App ID and nothing else. This overrides the value that Steam provides. You should not ship this with your builds. Example:
>
> `480`"

Source: <https://partner.steamgames.com/doc/sdk/api>

### 1.3 Confirmed: it is free, and it has no public store page

- The official store details endpoint returns a failure for 480: `https://store.steampowered.com/api/appdetails?appids=480` → `{"480":{"success":false}}`. Source: <https://store.steampowered.com/api/appdetails?appids=480>
- `https://store.steampowered.com/app/480/` redirects to the Steam store home page — there is no store page.
- `https://steamcommunity.com/app/480` likewise redirects to the store home page — there is no community hub.

**Free:** the app is installable at no cost via the Steam client URI `steam://install/480`. This is reported by third-party games journalism (Chinese games outlet 游研社 / yystv.cn), which states that although Spacewar cannot be found in Steam search, any Steam user on Windows can install and play it for free using `steam://install/480`:

> "虽然Steam商城根本搜不到它，但是任何使用Windows电脑的Steam用户，都能免费玩上《太空战争》，只需按下Windows徽标键+R键…输入下列链接：**steam://install/480**"

Source (secondary/third-party): <https://www.yystv.cn/p/12722>

**NOT FOUND:** a Valve-authored sentence explicitly stating "Spacewar is free." Valve's docs never mention price because 480 is not a commercial product. The "free" status is established by (a) the absence of any store/price page and (b) the third-party report above.

---

## 2. What is the Steam Datagram Relay (SDR)?

### 2.1 Purpose and general requirements — official

From Valve's official **Steam Datagram Relay** page:

> "Steam Datagram Relay (SDR) is Valve's virtual private gaming network. Using our APIs, you can not only carry your game traffic over the Valve backbone that is dedicated for game content, you also gain access to our network of relays. **Relaying the traffic protects your servers and players from DoS attack, because IP addresses are never revealed.** All traffic you receive is authenticated, encrypted, and rate-limited. Furthermore, for a surprisingly high number of players, we can also find a faster route through our network, which actually improves player ping times."
>
> "This relay network can be used for **both peer-to-peer traffic and dedicated servers**."

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

For **P2P on Steam specifically**, the page says there is essentially nothing to do:

> "**Peer-to-peer games** — For peer-to-peer traffic on Steam, all you need to do to take advantage of SDR is to use APIs such as [ISteamNetworkingSockets::CreateListenSocketP2P] and [ISteamNetworkingSockets::ConnectP2P]. **Steam will take care of everything else.**"

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

For **non-Steam platforms/stores**, the page lists explicit preconditions, including:

> "**Have a version of your game shipping on Steam.**"
> "Have some sort of matchmaking service (SDR refers to this as your 'game coordinator') that can issue some authentication credentials."

And it closes the door on the open-source route:

> "If you don't meet the criteria above, feel free to use the **opensource** version of the API for whatever you want. **Note that the opensource code does not support accessing the relay network.**"

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

### 2.2 Yes — the docs state that authentication with a Steam account and AppID ownership are required

This is stated most explicitly in the "Simple Connection Flow to Dedicated Server Without Game Coordinator" section (which is the `ConnectP2P`/`CreateListenSocketP2P` auto-ticket mode):

> "Rendezvous messages are sent through Steam, so **if the player or server loses their connection to Steam, the connection cannot be made**. Also, **Steam does not restrict who can attempt to connect, aside from verifying that the player is signed into Steam and owns the game.**"

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

The `ISteamNetworkingSockets` reference page repeats the ownership condition:

> "**CreateListenSocketP2P** — Like CreateListenSocketIP, but clients will connect using ConnectP2P. **The connection will be relayed through the Valve network.** … If you are listening on a dedicated servers in known data center, then you can listen using this function instead of CreateHostedDedicatedServerListenSocket, to allow clients to connect without a ticket. **Any user that owns the app and is signed into Steam will be able to attempt to connect to your server.**"

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

And the same page states the developer-side requirement:

> "An opensource version of this API is available on github. You can use it for whatever purpose you want. **To use the Valve network you need to be a Steam partner and use the version in the Steamworks SDK.**"

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

**App ticket / auth session:**

- For the **ticket-based hosted-dedicated-server** flow, tickets are mandatory: "Client call to connect to a server hosted in a Valve data center, on the specified virtual port. **You must have placed a ticket for this server into the cache, or else this connect attempt will fail!**" (<https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>)
- For the **P2P / auto-ticket** flow (`ConnectP2P`), no explicit ticket is required by the caller: "If you are not issuing your own tickets, then to connect to a dedicated server via SDR in **auto-ticket mode**, use ConnectP2P."
- Either way, **Steam-issued certificates** are required for authenticated connections. SDR page: "We use a proprietary public key infrastructure (PKI) to authenticate clients and servers. **Players are issued individual, short-term certificates, tied to their specific player identity. Steam takes care of this.**" (<https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>)
- The SDK header confirms certificates cannot be obtained without being logged into Steam. In `steamnetworkingtypes.h`, the enum documentation for `ESteamNetworkingAvailability` reads: "`k_ESteamNetworkingAvailability_Waiting = 2, // We're waiting on a dependent resource to be acquired.  (E.g. we cannot obtain a cert until we are logged into Steam. …)`" (<https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/include/steam/steamnetworkingtypes.h>)

**Does the game need to own/have the AppID on the Steam backend?** Yes, per the two doc statements above ("verifying that the player is signed into Steam and owns the game"; "Any user that owns the app and is signed into Steam"). Additionally, SDR's PKI is scoped per-app: "we will publish a certificate signed by our master CA key that **marks your key as trusted for your app(s)**" (<https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>).

### 2.3 Official doc pages for the requested APIs

| API | Official page |
|---|---|
| `ISteamNetworkingSockets` (incl. `ConnectP2P`, `CreateListenSocketP2P`) | <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets> |
| `ISteamNetworkingUtils` (incl. `InitRelayNetworkAccess`, `SetGlobalConfigValueInt32`) | <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils> |
| `steamnetworkingtypes.h` (incl. `ESteamNetworkingConfigValue`) | <https://partner.steamgames.com/doc/api/steamnetworkingtypes> |
| Steam Networking (feature overview) | <https://partner.steamgames.com/doc/features/multiplayer/networking> |
| Steam Datagram Relay (feature page) | <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay> |

`InitRelayNetworkAccess` is documented as:

> "void InitRelayNetworkAccess(); — If you know that you are going to be using the relay network (for example, because you anticipate making P2P connections), call this to initialize the relay network. If you do not call this, the initialization will be delayed until the first time you use a feature that requires access to the relay network… Use GetRelayNetworkStatus or listen for SteamRelayNetworkStatus_t callbacks to know when initialization has completed. Typically initialization completes in a few seconds."

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils>

`SetGlobalConfigValueInt32` appears under "Shortcuts for common cases":

> `bool SetGlobalConfigValueInt32( ESteamNetworkingConfigValue eValue, int32 val );`

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils>

---

## 3. Can a game running as AppID 480 use Valve's real SDR relay / lobbies / matchmaking servers?

### 3.1 Prerequisites — confirmed

1. **A genuine, running Steam client.** Valve: "**The Steam client isn't running.** A running Steam client is required to provide implementations of the various Steamworks interfaces." (<https://partner.steamgames.com/doc/sdk/api>)
2. **A logged-in Steam account that owns the AppID.** Valve: "Ensure that you **own a license for the App ID** on the currently active Steam account. Your game must show up in your Steam library." (<https://partner.steamgames.com/doc/sdk/api>) — and for SDR/`CreateListenSocketP2P`: "verifying that the player is signed into Steam and owns the game" (<https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>). For AppID 480 this condition is trivially satisfied, because 480 is free and universally "owned".
3. **The genuine `steam_api64.dll` + the genuine Steam client process.** Valve's API overview describes the mechanism: "When the Steamworks API initializes it finds the actively running steam client process and loads `steamclient.dll` from that path… all Steam API calls are transparently marshaled and sent via an RPC/IPC mechanism." (<https://partner.steamgames.com/doc/sdk/api>)

### 3.2 Does Valve's backend validate the appid? Yes — but note *how*, because this is the crux

Valve's backend validates **that the logged-in account owns the app whose AppID the client session claims**. It does **not** (per any source found) validate that the running binary is actually that app's binary. That is precisely why the "480 redirect" technique works: the process claims to be Spacewar, the account genuinely owns Spacewar, so validation passes.

- `steam_appid.txt` is a documented, Valve-sanctioned mechanism for overriding the AppID: "This **overrides the value that Steam provides**." (<https://partner.steamgames.com/doc/sdk/api>)
- Valve documents no binary/hash attestation for AppID claim. What Steam does check is ownership: "Ensure that you own a license for the App ID on the currently active Steam account." (<https://partner.steamgames.com/doc/sdk/api>)
- The `SteamEncryptedAppTicket` mechanism exists for a *server* to verify a *client account's* ownership of an app (`ISteamUser::RequestEncryptedAppTicket` / `GetEncryptedAppTicket`), but that requires the server to call the Web API `ISteamUserAuth/AuthenticateUserTicket`. It verifies **account ownership of an AppID**, not the client's binary. (<https://partner.steamgames.com/doc/api/SteamEncryptedAppTicket>)

### 3.3 Can a cracked/emulated `steam_api64.dll` pass that validation?

**Two fundamentally different piracy techniques must be separated. Conflating them is the main source of folklore.**

**(a) Emulator substitution — does NOT reach Valve's backend.**
Tools such as Goldberg / `gbe_fork` replace `steam_api64.dll` with an emulator. Their own release README is explicit about what they are:

> "**An emulator that supports LAN multiplayer without steam.**"

Source: <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>

Details from the same README that confirm it is a local emulation, not a Valve backend client:

- Matchmaking is faked: "**By default, match making servers (which handles browsing for matches) will always return LAN servers list** whenever the game inquires about the available servers with a specific type (Internet, Friends, LAN, etc…)" — and the option to return "actual" types is marked "**This is currently broken**".
- App tickets are self-generated: "**Auth token (app ticket):** By default the emu will send the old token format for various APIs, like: `Steam_GameServer::GetAuthSessionTicket()`, `Steam_User::GetAuthSessionTicket()`, `Steam_User::GetAuthTicketForWebApi()`. You can make the emu **generate new ticket data**…"
- Scope is local/offline: "**Do not run more than one steam game with the same appid at the same time on the same computer with this emu** or there might be network issues."
- Local avatars: "Players avatars are shared **over the local network**."

Source: <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>

**Conclusion:** an emulated `steam_api64.dll` of this class **cannot** use Valve's SDR relay, Valve lobbies, or Valve matchmaking, because it never talks to Valve at all — it substitutes itself for the Valve client library and emulates the backend locally. Any claim that a Goldberg-class emulator DLL "passes Valve's ticket validation" is **REFUTED** by the emulator's own documentation. No source found claims otherwise (**NOT FOUND**).

**(b) AppID-480 redirect with the *genuine* Steam client and *genuine* `steam_api64.dll` — DOES reach Valve's backend.**
Here nothing is emulated. The real Steam client is running, the real Valve-issued account session is used, and the process merely claims to be AppID 480 via `steam_appid.txt` (or, in modern tools, via a client-side config/VDF hook). Because the account genuinely owns 480, Valve's ownership validation succeeds.

A current, actively maintained crack toolchain documents this mechanism explicitly. The SteaMidra / SFF README describes its "LC Online Fix":

> "**LC Online Fix** — toggle `-onlinefix` on a chosen App ID in `localconfig.vdf`. Closes Steam first, picks the active SteamID3 from `loginusers.vdf`, navigates the VDF tree case-insensitively. **LumaCore handles the appid-480 redirect at launch so the overlay, Steam Input, and screenshots still tag the real game.**"

and distinguishes it from emulation:

> "**Fixes & Bypasses** — … Achievement-safe — **only adds bypass DLLs, leaves the Steam API intact.**"

Source: <https://github.com/Midrags/SFF> (README.md, `main` branch)

Note the phrase "leaves the Steam API intact" — i.e. the genuine Valve API and genuine Steam client are deliberately preserved, precisely because that is what makes real Steam online features work. The `gbe_fork` emulator is listed in the same tool as a *separate* offline feature ("a Steam emulator for running games offline").

### 3.4 Evidence that these features actually work under AppID 480

**Developer report (2017) — old `ISteamNetworking` P2P with NAT punch-through under 480:**

> "I've been doing some testing with Steamworks.NET, using the AppID that it provides (480 - Spacewar), and **everything seems to work - I can access friends list, use p2p with NAT punch-through, etc, Steam just shows me and my friend playing spacewar**, when we are actually playing my basic unity project."

Source (community): <https://steamcommunity.com/discussions/forum/9/135510393195379614/>

The same thread includes a community answer that correctly summarises the mechanism:

> "A normal gamer can only 'play' Spacewar by using cracked and pirated games to hook into steams authentication system by tricking steam into believing it's a legitimate copy."

Source (community, from a different thread on the same topic): <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693>

**Developer report (2022) — `SteamNetworkingSockets` SDR P2P under 480:**

A Facepunch.Steamworks issue titled "SteamNetworkingSockets.ConnectRelay ArgumentException: Invalid Connection" reports:

> "I have 2 projects with server and client, **both initing steamworks under appid 480**. Server creates socket `SteamNetworkingSockets.CreateRelaySocket<SteamSocketManager>(0);` … But for some reason I cannot get client to connect to server with `steamConnectionManager = SteamNetworkingSockets.ConnectRelay<SteamConnectionManager>(SteamClient.SteamId);`"

Reply:

> "Not sure if that is the same case, but I have this: 'System.ArgumentException: Invalid Connection'. But this is happening **only if you are trying to connect to localhost**. **If I test the same project from different devices (or virtual machine) with different steam accounts connected, then everything works just fine.**"

Source: <https://github.com/Facepunch/Facepunch.Steamworks/issues/686>

**This is the single strongest piece of evidence that SDR-relayed P2P works under AppID 480.** It is important to establish that `ConnectRelay`/`CreateRelaySocket` really are `ConnectP2P`/`CreateListenSocketP2P` and not plain UDP. From Facepunch's own source (`SteamNetworkingSockets.cs`):

```csharp
public static T CreateRelaySocket<T>( int virtualport = 0 ) where T : SocketManager, new()
{
    ...
    /// <summary>
    /// Creates a server that will be relayed via Valve's network (hiding the IP and improving ping).
    t.Socket = Internal.CreateListenSocketP2P( virtualport, options.Length, options );
    ...
}

/// <summary>
/// Connect to a relay server.
/// </summary>
public static T ConnectRelay<T>( SteamId serverId, int virtualport = 0 ) where T : ConnectionManager, new()
{
    ...
    t.Connection = Internal.ConnectP2P( ref identity, virtualport, options.Length, options );
    ...
}
```

Source: <https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs>

The Facepunch wiki also describes them as: "Connect to a socket created via CreateListenSocketIP" vs. "**Creates a 'server' socket that listens for clients to connect to by calling Connect, over SDR (Steam Datagram Relay)**." Source: <https://wiki.facepunch.com/steamworks/SteamNetworkingSockets>

So: `CreateRelaySocket` → `CreateListenSocketP2P`, `ConnectRelay` → `ConnectP2P`. The report is on point.

**Behavioural evidence — Spacewar's concurrent-player count tracks major cracked multiplayer releases.** Third-party games journalism (游研社) reports, citing SteamDB data, that Spacewar's "concurrent players" spiked to 78k in Feb 2023 (coinciding with *Sons of the Forest* early access), passed 100k in Jan 2024 (coinciding with *Palworld*), and hit ~138k in late Mar 2025 (coinciding with *Schedule I*), while the actual Spacewar game was not being played by those accounts.

Source (secondary/third-party): <https://www.yystv.cn/p/12722> — SteamDB figures as reported by that outlet; **not independently verified** (SteamDB access blocked, see Method note).

A parallel community report from the *Schedule I* Steam hub:

> "When I invite a friend to my lobby in Schedule1 via Steam, it opens **Spacewar (App ID 480)** for them instead of Schedule1."
> Reply: "**Spacewar is the 'game' many pirated cracks use to launch multiplayer in Steam.** He's playing a pirated copy."

Source: <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693>

### 3.5 Does 480 specifically have relay/matchmaking enabled?

**NOT FOUND:** an explicit Valve statement to the effect of "SDR/relay/matchmaking are enabled for AppID 480."

**Strong indirect evidence that they are:**
1. Valve's official Spacewar page lists **Matchmaking (Both lobbies and server browser)** and **Multi-Player Authentication** among the features the sample demonstrates — a sample that demonstrates a backend feature must have that feature enabled for its AppID. (<https://partner.steamgames.com/doc/sdk/api/example>)
2. Valve's Steam Networking page names Spacewar as *the* example for `ISteamNetworkingSockets` — the API whose P2P path is "relayed through the Valve network" by default. (<https://partner.steamgames.com/doc/features/multiplayer/networking>)
3. Valve's SDR page says P2P on Steam needs nothing beyond `CreateListenSocketP2P`/`ConnectP2P`: "Steam will take care of everything else." No per-app SDR opt-in is documented anywhere I found. (<https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>)
4. The working `ConnectP2P`-under-480 developer report in §3.4.

**SPECULATION (clearly flagged):** Given (1)–(3), it is reasonable to infer that SDR is enabled for AppID 480 in the same way it is for any other Steam app. But no Valve document states this for 480 specifically, and I found no Valve document describing a per-app SDR enablement step for Steam apps (as opposed to non-Steam platforms, which are explicitly gated).

---

## 4. Why do crack groups set `steam_appid.txt` to 480?

### 4.1 Origin of the practice — Valve's own documentation

The origin is not obscure: **Valve's own docs tell developers to put 480 in `steam_appid.txt`.**

1. The Steamworks API Overview's `steam_appid.txt` example content is literally `480` (<https://partner.steamgames.com/doc/sdk/api>).
2. Valve's Spacewar sample ships with a `steam_appid.txt` containing 480, and the docs say the sample "ships with the SDK example" (<https://partner.steamgames.com/doc/sdk/api/example>).
3. Valve's docs also warn the file "overrides the value that Steam provides" and "You should not ship this with your builds" — i.e. Valve documents it as a developer-only override, which is exactly what makes it abusable.

**Why 480 specifically, and not another free app?** Combining the sources:

- 480 is the value printed in Valve's docs, so it is the default copy-paste value.
- 480 is free and owned by essentially every Steam account, so the ownership check ("owns the game") passes without the pirate owning the actual game.
- 480 has the Steam backend features a multiplayer crack needs enabled (lobbies, matchmaking, `ISteamNetworking`/`ISteamNetworkingSockets`), because Valve uses it to demonstrate exactly those features.
- Valve's Spacewar is a 2D game with essentially no DRM wrapper and no file-integrity attestation relevant to the AppID claim.

Third-party journalism states the mechanism and the reason directly:

> "Steam版本的《太空战争》，主要是为了方便游戏开发者将Steam内置功能移植到自己的游戏里。它不仅去掉了标题的感叹号，还内置了Steam API的完整功能，包括头像、好友列表、匹配和社区功能等。V社在Steam文献库展示了《太空战争》的全部源代码… V社还允许游戏开发者使用《太空战争》对应的识别编号，即AppID（480），免费测试游戏的网络联机功能。**正是这一点，给了盗版游戏，特别是盗版多人游戏以可乘之机。**盗版游戏当然是无法通过Steam联机的，然而当它们通过技术手段骗过Steam，将自己伪装成《太空战争》的AppID时，就能像正版游戏一样用Steam联机了。"

Translation of the operative sentences: the Steam build of Spacewar exists to let developers port Steam features into their own games; it has the full Steam API built in, including avatars, friends list, **matchmaking** and community; Valve publishes its full source in the Steamworks docs; **Valve also lets developers use Spacewar's AppID (480) to test a game's networking features for free** — and *that* is what gives pirated games, especially pirated multiplayer games, their opening: when they trick Steam into believing they are the Spacewar AppID, they can use Steam online play just like a legitimate game.

Source (secondary/third-party): <https://www.yystv.cn/p/12722>

The same article reports the loophole is not new: "这个利于盗版联机的漏洞，**至少在2017年就有报告**，V社想管的话也早就管了。" ("This loophole … was reported at least as early as 2017; if Valve wanted to do something about it, they would have long ago.")

Source: <https://www.yystv.cn/p/12722>

### 4.2 Concrete crack instructions that say "set `steam_appid.txt` to 480"

**Example A — Dark Souls: Prepare to Die Edition, "Play Dark Souls PTDE Online 2024" (Steam Community guide, Nov 2023):**

> "3. Create a text file called **"steam_appid.txt"** in the DATA folder found within the game's main directory. Open the text file you created and **write "480" in it** (without the " marks). **This will fool Steam into thinking that Dark Souls is a game called "Spacewar"; this will enable online functionality for Dark Souls.**
> 4. **Launch the game exe directly; do not launch through Steam.**"

Source: <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/>

Note step 4: the genuine Steam client must still be running in the background — the instruction is to launch the *game* outside Steam so it picks up the overridden AppID while the real Steam client's session provides the backend connection. This is category (b) from §3.3, not emulation.

**Example B — SteaMidra / SFF (contemporary tool, actively maintained):**

> "**LC Online Fix** — toggle `-onlinefix` on a chosen App ID in `localconfig.vdf`… **LumaCore handles the appid-480 redirect at launch** so the overlay, Steam Input, and screenshots still tag the real game."
> "**Multiplayer Fix** — searches **online-fix.me** for the selected game and opens the result in your browser."

Source: <https://github.com/Midrags/SFF>

**Example C — Schedule I (2025), user-visible symptom:** players receive Steam lobby invites that open **Spacewar (App ID 480)** instead of the real game, and the community identifies this as the crack signature. Source: <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693>

### 4.3 Is the claimed benefit real?

**Claimed benefit:** "Setting `steam_appid.txt` to 480 enables internet multiplayer through Valve's servers."

**Assessment:**

- **Yes, for the genuine-Steam-client variant.** The mechanism is exactly as claimed in §3: the process claims AppID 480, the account legitimately owns 480, Valve brokers lobbies/P2P/relay for 480. Confirmed by Valve's docs on `steam_appid.txt` and SDR rendezvous (§2.2, §3.1), and by the developer reports in §3.4.
- **No, for the emulator variant.** Goldberg-class emulators provide LAN-only multiplayer and never touch Valve. §3.3(a).
- **Caveat that the folklore usually omits:** this is an AppID/ownership spoof, not a `steam_api64.dll` crack. It relies on Valve continuing to permit AppID overrides and on Valve not enforcing binary identity. It provides no anonymity — the sessions are brokered by the player's own real, logged-in Steam account, which is why the "Spacewar" activity appears on their public profile (see the *Schedule I* thread, where a poster identified the pirate by the Spacewar entry on their recently-played list).

---

## 5. Authoritative confirmation vs. community folklore

| Claim | Status | Basis |
|---|---|---|
| Spacewar (480) is Valve's official Steamworks sample/test app | **CONFIRMED** | Valve: <https://partner.steamgames.com/doc/sdk/api/example>, <https://partner.steamgames.com/doc/sdk> |
| 480 is the value in Valve's own `steam_appid.txt` example | **CONFIRMED** | Valve: <https://partner.steamgames.com/doc/sdk/api> |
| `steam_appid.txt` overrides the AppID Steam would otherwise use | **CONFIRMED** | Valve: <https://partner.steamgames.com/doc/sdk/api> |
| SDR P2P rendezvous goes through Steam and requires being signed into Steam and owning the app | **CONFIRMED** | Valve: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay> |
| The open-source API cannot access the relay network | **CONFIRMED** | Valve: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>; <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets> |
| `ConnectP2P` requires a third-party rendezvous service, of which Steam is the only supported one, and all P2P on Steam is relayed | **CONFIRMED (historical SDK header)** | Valve: <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/1.0.0/include/steam/isteamnetworkingsockets.h> (see §6) |
| Pirated copies run under AppID 480 to obtain Steam online functionality | **CONFIRMED (multiple independent community/journalistic sources)**; **no Valve acknowledgement found** | <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/>, <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693>, <https://www.yystv.cn/p/12722> |
| Spacewar's concurrent-player count spikes coincide with major cracked multiplayer releases | **REPORTED by third-party journalism citing SteamDB; not independently verified here** | <https://www.yystv.cn/p/12722> |
| A game running as 480 that keeps the real Steam client can use Valve-brokered lobbies/P2P | **CONFIRMED by mechanism (Valve docs) + two independent developer reports** | §3.4 |
| `ConnectP2P` (SDR relay) under AppID 480 works between two machines with different accounts | **COMMUNITY REPORT, not Valve-confirmed** | <https://github.com/Facepunch/Facepunch.Steamworks/issues/686> |
| A cracked/emulated `steam_api64.dll` (Goldberg class) can connect to Valve's real relay/lobby/matchmaking servers | **REFUTED** by the emulator's own docs (LAN-only, local ticket generation) | <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> |
| A cracked/emulated `steam_api64.dll` can pass Valve's app-ticket validation for a *different* app | **NOT FOUND** — no source supports this; the emulator explicitly fabricates tickets locally | — |
| An explicit Valve statement that SDR/relay/matchmaking are enabled for AppID 480 | **NOT FOUND** | — |
| A Valve statement addressing, condoning, or condemning the 480-redirect practice | **NOT FOUND** | — |
| Valve has taken action to block the 480 practice | **NOT FOUND** (third-party journalism asserts Valve has not acted, but that is not a Valve statement) | <https://www.yystv.cn/p/12722> |

**Folklore to discard:** the common shortcut "cracked games use Spacewar because Valve's servers can't tell a cracked dll from a real one" is imprecise in a way that matters. The accurate statement is: **nothing needs to be fooled at the authentication layer.** The account really does own AppID 480, and the Steam client really is a legitimate Steam client. What is spoofed is only *which app the local process claims to be*. Conversely, the claim that a Steam *emulator* DLL gets you onto Valve's servers is contradicted by the emulators' own documentation.

---

## 6. `ConnectP2P` / `CreateListenSocketP2P` — what backend infrastructure is required

### 6.1 The exact text you quoted — found and cited

The text is authentic. It appears in Valve's public **GameNetworkingSockets** repository at the `1.0.0` tag, in `include/steam/isteamnetworkingsockets.h`, interface version `SteamNetworkingSockets002`:

```cpp
#ifdef STEAMNETWORKINGSOCKETS_ENABLE_SDR
	/// Like CreateListenSocketIP, but clients will connect using ConnectP2P
	///
	/// nVirtualPort specifies how clients can connect to this socket using
	/// ConnectP2P.  It's very common for applications to only have one listening socket;
	/// in that case, use zero.  …
	///
	/// If you use this, you probably want to call ISteamNetworkingUtils::InitializeRelayNetworkAccess()
	/// when your app initializes
	virtual HSteamListenSocket CreateListenSocketP2P( int nVirtualPort ) = 0;

	/// Begin connecting to a server that is identified using a platform-specific identifier.
	/// This requires some sort of third party rendezvous service, and will depend on the
	/// platform and what other libraries and services you are integrating with.
	///
	/// At the time of this writing, there is only one supported rendezvous service: Steam.
	/// Set the SteamID (whether "user" or "gameserver") and Steam will determine if the
	/// client is online and facilitate a relay connection.  Note that all P2P connections on
	/// Steam are currently relayed.
	///
	/// If you use this, you probably want to call ISteamNetworkingUtils::InitializeRelayNetworkAccess()
	/// when your app initializes
	virtual HSteamNetConnection ConnectP2P( const SteamNetworkingIdentity &identityRemote, int nVirtualPort ) = 0;
#endif
```

Verbatim raw source: <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/1.0.0/include/steam/isteamnetworkingsockets.h>
Rendered source: <https://github.com/ValveSoftware/GameNetworkingSockets/blob/1.0.0/include/steam/isteamnetworkingsockets.h>

**Important caveat on version:** this wording is from the `1.0.0` tag (interface `SteamNetworkingSockets002`), not from the current SDK. The wording was later reworked. Do not cite it as "the current SDK header."

### 6.2 The same requirement in other SDK versions — all say the same thing in substance

**Steamworks SDK 1.50 mirror** (`SteamNetworkingSockets009`, `isteamnetworkingsockets.h`):

> "/// Begin connecting to a peer that is identified using a platform-specific identifier.
> /// This uses the default rendezvous service, which depends on the platform and library
> /// configuration.  (E.g. **on Steam, it goes through the steam backend**.)"

Source: <https://raw.giteeusercontent.com/chenyanwjf/proton-ge-custom/raw/master/lsteamclient/steamworks_sdk_150/isteamnetworkingsockets.h>

**Current `GameNetworkingSockets` master** (`isteamnetworkingsockets.h`): same wording as 1.50.

Source: <https://raw.githubusercontent.com/studentutu/GameNetworkingSockets/master/include/steam/isteamnetworkingsockets.h>

**Current Steamworks API reference (partner.steamgames.com)** — `ConnectP2P`:

> "Begin connecting to a peer that is identified using a platform-specific identifier. **This uses the default rendezvous service, which depends on the platform and library configuration. (E.g. on Steam, it goes through the steam backend.) The traffic is relayed over the Steam Datagram Relay network.**"

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

**Current Steamworks API reference** — `CreateListenSocketP2P`:

> "Like CreateListenSocketIP, but clients will connect using ConnectP2P. **The connection will be relayed through the Valve network.**"

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

**Current Steam Networking feature page:**

> "Our newest APIs relay packets through the Valve network by default… **All P2P connections are automatically relayed over the Valve backbone when appropriate.**"

Source: <https://partner.steamgames.com/doc/features/multiplayer/networking>

**Answer to your question:** **Yes.** `ConnectP2P` with a `SteamID` requires Valve's Steam backend to perform the rendezvous. The SDK header (1.0.0 era) says the rendezvous service is required and Steam is the only supported one; current partner docs say Steam/Steam-backend is the default rendezvous service and that the traffic is relayed over SDR. NAT punch/relay is decided by the library and Steam's relay network, not by the application.

### 6.3 What a non-Valve deployment would have to supply

For completeness — if you are *not* on Steam, every piece of the backend must be replaced. Valve's own docs and Valve's open-source `README_P2P.md` enumerate them:

> "**Signaling service** — A side channel, capable of relaying small rendezvous messages from one host to another. This means hosts must have a constant connection to your service, one that enables you to *push* messages to them."
> "**STUN server(s)** — A STUN server is used to help peers discover their own public IP address and open up firewalls."
> "**Relay fallback** — Unfortunately, for some pairs of hosts, NAT piercing is not successful. In this situation, the traffic must be relayed… **On Steam we use a custom relay service known as Steam Datagram Relay (SDR)**… (You may see this mentioned in the opensource code here, but **the SDR support code is not opensource**.)"
> "**Naming hosts and matchmaking** — … Those services are also included with Steam, but outside the scope of a transport library like this."

Source: <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README_P2P.md>

And the partner docs, for non-Steam platforms:

> "**P2P connections require a 'signaling' service.** This is a low-bandwidth, non-latency-sensitive, best-effort-delivery channel capable of forwarding occasional rendezvous messages used to negotiate routing. **This requires clients to have a persistent connection to your matchmaking service**, such that you can push messages to them, such as a websocket or TCP connection. If clients only talk to your game coordinator using a request/response pattern, for example through http, that won't work."

Source: <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>

And from the API reference, on the custom-signaling escape hatch:

> "**Custom P2P signaling** — *Signaling* refers to rendezvous messages sent through a trusted channel… **Steam provides a signaling service for you.** However, in some situations you may wish to do your own signaling. (For example, if one or both of your peers are not on Steam.) You can use SteamNetworkingSockets to make P2P connections, with your own signaling. You can use ICE to pierce NAT and use standard STUN/TURN servers, or depending on your situation, **SDR relay network and Valve backbone may not be available**."

Source: <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets>

---

## 7. Does Spacewar (480) specifically have Steam networking / SDR enabled, and does it work for P2P relay testing?

**Findings, in order of strength:**

1. **Valve names Spacewar as the `ISteamNetworkingSockets` example.** "See the Steamworks API Example Application (SpaceWar) for an example of using the ISteamNetworkingSockets for client-server communication." — <https://partner.steamgames.com/doc/features/multiplayer/networking>
2. **Valve's Spacewar page lists Networking, Matchmaking (lobbies *and* server browser), and Multi-Player Authentication as demonstrated features.** — <https://partner.steamgames.com/doc/sdk/api/example>
3. **A developer successfully used `CreateListenSocketP2P`/`ConnectP2P` (via Facepunch's `CreateRelaySocket`/`ConnectRelay`) under AppID 480 across two machines with different Steam accounts.** — <https://github.com/Facepunch/Facepunch.Steamworks/issues/686> (community report). The same report notes that connecting **to your own server from the same account/machine** fails — which is normal behaviour, not a 480 restriction; the reporter's own follow-up says "it seems like you cannot connect normally from the same Steam account client to your own server socket through Steam."
4. **A 2017 developer report of P2P with NAT punch-through under 480** — <https://steamcommunity.com/discussions/forum/9/135510393195379614/> (community report; older `ISteamNetworking`, not SDR).
5. **Valve does not document any per-app SDR enablement step for Steam apps**, and 480 is what Valve itself points at for sockets examples, so there is no documented reason 480 would lack it.

**NOT FOUND:**
- Any Valve statement that AppID 480 specifically has SDR/relay enabled (or disabled).
- Any Valve-documented restriction on using 480 for `ISteamNetworkingSockets` P2P testing.
- Any Valve statement that the 480 redirect for pirated games is detected or blocked.

**Answer:** Spacewar (480) works for `SteamNetworkingSockets` P2P/SDR testing — with a genuine Steam client, a logged-in account, and the genuine Steamworks API. This is established by Valve pointing at 480 for exactly this API, plus two independent developer reports spanning 2017–2022 (old `ISteamNetworking` P2P, and modern `CreateListenSocketP2P`/`ConnectP2P`). "SDR is enabled for 480" is the correct working assumption but rests on inference from Valve's docs rather than an explicit Valve statement, and is labelled **SPECULATION** in the strict sense of §3.5.

### 7.1 Practical implications if you are building/testing against 480

- You must run the **real Steam client**, logged into a real account, with the real `steam_api64.dll` shipped next to your binary. Valve: "A running Steam client is required." (<https://partner.steamgames.com/doc/sdk/api>)
- You must have a `steam_appid.txt` containing `480` next to the executable (or use `SteamAppId`/`SteamGameId` env vars). (<https://partner.steamgames.com/doc/sdk/api>, and the Goldberg README for the env-var detail)
- Call `ISteamNetworkingUtils::InitRelayNetworkAccess()` at startup; poll `GetRelayNetworkStatus` / `SteamRelayNetworkStatus_t`. (<https://partner.steamgames.com/doc/api/ISteamNetworkingUtils>)
- **You cannot test P2P against yourself on one machine/account.** Use two machines or two accounts. (<https://github.com/Facepunch/Facepunch.Steamworks/issues/686>, and by design — SDR rendezvous is keyed to SteamID)
- Remove `steam_appid.txt` before shipping: "Make sure to remove the `steam_appid.txt` file when uploading the game to your Steam depot!" (<https://partner.steamgames.com/doc/sdk/api>)
- Be aware you are sharing AppID 480's lobbies/matchmaking namespace with everyone else using 480 for the same purpose (including pirates). This is the "conflicts in session lookups" problem raised on the Unreal Engine forums: "would be nice to have an UE4 steam id for all instead of 'SpaceWar'", in a thread titled *"Any chance for an official UnrealEngine Steam Test AppId instead of the notorious Spacewar Id?"*. (<https://forums.unrealengine.com/t/any-chance-for-an-official-unrealengine-steam-test-appid-instead-of-the-notorious-spacewar-id/53881>)

---

## 8. Consolidated source list

**Valve / official:**
- <https://partner.steamgames.com/doc/sdk/api/example> — Steamworks API Example Application (SpaceWar)
- <https://partner.steamgames.com/doc/sdk/api> — Steamworks API Overview (`steam_appid.txt` = 480; Steam client + license requirements)
- <https://partner.steamgames.com/doc/sdk> — Steamworks SDK index (lists `steamworksexample`)
- <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay> — Steam Datagram Relay
- <https://partner.steamgames.com/doc/features/multiplayer/networking> — Steam Networking
- <https://partner.steamgames.com/doc/api/ISteamNetworkingSockets> — `ConnectP2P`, `CreateListenSocketP2P`, signaling, "need to be a Steam partner"
- <https://partner.steamgames.com/doc/api/ISteamNetworkingUtils> — `InitRelayNetworkAccess`, `SetGlobalConfigValueInt32`
- <https://partner.steamgames.com/doc/api/steamnetworkingtypes> — config values / types
- <https://partner.steamgames.com/doc/api/SteamEncryptedAppTicket> — app ticket semantics
- <https://partner.steamgames.com/doc/store/testing> — testing on Steam (no mention of 480 as a test AppID for this purpose)
- <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/1.0.0/include/steam/isteamnetworkingsockets.h> — **the exact quoted `ConnectP2P` text**
- <https://github.com/ValveSoftware/GameNetworkingSockets/blob/1.0.0/include/steam/isteamnetworkingsockets.h> — rendered
- <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/include/steam/isteamnetworkingsockets.h> — current header
- <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/include/steam/steamnetworkingtypes.h> — `ESteamNetworkingAvailability` ("cannot obtain a cert until we are logged into Steam")
- <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README.md> — "some features are only available on Steam, such as Steam's authentication service, signaling service, and the SDR relay service"
- <https://raw.githubusercontent.com/ValveSoftware/GameNetworkingSockets/master/README_P2P.md> — signaling / STUN / relay fallback requirements
- <https://store.steampowered.com/api/appdetails?appids=480> — returns `{"480":{"success":false}}`

**SDK-mirror header (third-party mirror of Valve's SDK):**
- <https://raw.giteeusercontent.com/chenyanwjf/proton-ge-custom/raw/master/lsteamclient/steamworks_sdk_150/isteamnetworkingsockets.h> — Steamworks SDK 1.50 / `SteamNetworkingSockets009`

**Community / third-party:**
- <https://steamcommunity.com/discussions/forum/9/135510393195379614/> — 2017 developer report, P2P + NAT punch-through under 480
- <https://github.com/Facepunch/Facepunch.Steamworks/issues/686> — 2022 report, SDR `ConnectP2P` under 480 works across machines/accounts
- <https://raw.githubusercontent.com/Facepunch/Facepunch.Steamworks/master/Facepunch.Steamworks/SteamNetworkingSockets.cs> — proof that `ConnectRelay` → `ConnectP2P`, `CreateRelaySocket` → `CreateListenSocketP2P`
- <https://wiki.facepunch.com/steamworks/SteamNetworkingSockets> — same, in prose
- <https://steamcommunity.com/app/211420/discussions/0/6027566653452564957/> — Dark Souls PTDE: explicit "write 480 in steam_appid.txt" crack instruction
- <https://steamcommunity.com/app/3164500/discussions/1/830459135855238693> — Schedule I: "Spacewar is the 'game' many pirated cracks use to launch multiplayer in Steam"
- <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md> — Goldberg/gbe_fork: "LAN multiplayer without steam", faked matchmaking, local ticket generation
- <https://github.com/Midrags/SFF> — SteaMidra: "LumaCore handles the appid-480 redirect at launch"; "leaves the Steam API intact"
- <https://www.yystv.cn/p/12722> — 游研社 journalism: reasons for the 480 practice, `steam://install/480`, SteamDB concurrent-player correlation with cracked releases, "reported since 2017"
- <https://forums.unrealengine.com/t/any-chance-for-an-official-unrealengine-steam-test-appid-instead-of-the-notorious-spacewar-id/53881> — Unreal developers on 480 as the de-facto test AppID
- <https://gamedev.stackexchange.com/questions/212913/how-can-i-test-my-game-using-steamapi-without-steam> — developer using test AppID 480
- <https://github.com/rlabrecque/Steamworks.NET/issues/311> — "The API will fail to init if the user does not own the app ID in question. They may use app ID 480"

**Explicitly not used / inaccessible:**
- `steamdb.info` — HTTP 403; site requested no further automated access. Not used.
- `developer.valvesoftware.com/wiki/Steam_Datagram_Relay` — blocked by Anubis proof-of-work. Not used.
- `gamedev.stackexchange.com/questions/208988` — HTTP 403. Not used.
