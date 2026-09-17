# OnlineFix / OnlineFix64.dll — Technical Reverse-Engineering Report

**Scope:** online-fix.me and the "OnlineFix" Steam emulator family (`OnlineFix64.dll`, `OnlineFix.dll`, `steam_api64.dll` wrapper, `winmm.dll`, `OnlineFix.ini`).
**Method:** web research only (no local binary disassembly). Every claim carries a source URL. Unconfirmed items are labelled **NOT FOUND** or **SPECULATION**.

---

## 0. Executive summary

OnlineFix is **not** a Goldberg-style LAN emulator and **not** a VPN technique. It is a hybrid:

* a **DRM/ownership bypass** — it makes a cracked, not-owned game believe it is a legitimately-owned, logged-in Steam user; and
* a **multiplayer patch** that achieves real internet play by **re-targeting the game's Steamworks traffic onto a real, free/always-available Valve AppID** (canonically **Spacewar, AppID 480**), so the game rides Valve's own Steam networking/relay/matchmaking/lobby backend.

Confirmed: it **requires the genuine Steam client installed and logged in**, and it **does** ship its own `steam_api64.dll` wrapper plus a custom `steamclient` implementation. It is **not** a fork of Goldberg and is architecturally near-opposite to it.

---

## 1. What online-fix.me and "OnlineFix" are

### 1.1 The site

* online-fix.me is a third-party site distributing "online fixes" (multiplayer patches) for cracked/repacked games. A Chinese games site describes it in plain terms as a third-party multiplayer-fix resource from a **Russian team**: "Online-Fix 是由俄罗斯团队制作的第三方联机修复资源，主要用于部分游戏的多人联机功能" ("Online-Fix is a third-party multiplayer-fix resource made by a Russian team, mainly used for the multiplayer functionality of some games") — <https://www.xmy7.com/sjyx/107808.html>
* An automated reputation checker scores the domain 35/100 ("Suspicious Website" / blacklist warning) — <https://gridinsoft.com/online-virus-scanner/url/online_fix-me> (also surfaced as <https://pt.gridinsoft.com/online-virus-scanner/id/155954174a6fa52ec64ca44e4d77f387e7c9f363541c81a4a7812d9c783af3ca>)
* Trustpilot user rating is 3/5 ("Average") — <https://ca.trustpilot.com/review/online-fix.me>
* Third-party tooling treats it purely as a fix *distribution* site: a Steam-modding tool states it "searches **online-fix.me** for the selected game and opens the result in your browser. SteaMidra is not affiliated with online-fix.me" — <https://github.com/Midrags/SFF/blob/main/README.md>
* Independent news coverage of the group: a hardware/games news site headlines "Online-Fix group released an online hack for **Microsoft Flight Simulator 2024**", noting the group ships online hacks bypassing mandatory online checks — <https://ko.gamegpu.com/news/igry/gruppa-online-fix-vypustila-onlajn-vzlom-dlya-microsoft-flight-simulator-2024>

### 1.2 The tool: what OnlineFix64.dll actually is

Authoritative metadata comes from PE version-info extraction of real samples:

* `OnlineFix64.dll` version resource: **CompanyName = `Online-Fix.Me`**, **FileDescription = `Online-Fix Steamclient`**, FileVersion/ProductVersion `1.3.2.0`, **LegalCopyright `Copyright (C) 2021-2023, 0xdeadc0de`** — <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>
* GridinSoft ThreatInfo classifies OnlineFix64.dll under publisher/company **`Online-Fix`** (30 files indexed) — <https://threatinfo.net/companies/Online-Fix>
* The `steam_api64.dll` shipped by OnlineFix carries **ProductName `Steam Wrapper`**, **CompanyName `Online-Fix`** — <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066>

The literal string "**Online-Fix Steamclient**" is the strongest single piece of evidence that this is a **replacement Steam client / Steam-client-interface implementation**, not merely a LAN emulator. This is corroborated by the fact that the emulator is loaded as `steamclient` (see §2.4).

A Russian Windows-help article summarises the function bluntly: "**Onlinefix64.dll** – this dynamic API library, developed by … Onlinefix, which is needed to crack paid games that are uploaded to torrents or to their site online-fix.me" — <https://mywebpc.ru/windows/onlinefix64-dll/>

### 1.3 Verdict on "emulator / patch / DRM workaround"

**All three, in one bundle.** It is a Steam emulator (replaces Steam API + client interfaces), a multiplayer patch (rewrites games to a shared free AppID for online play), and a DRM/ownership workaround (spoofs ownership and a logged-in user).

---

## 2. Files shipped by an OnlineFix release

### 2.1 The authoritative file-name pattern

The most precise public description of the OnlineFix payload is the regex used by the **OnlineFix Linux Launcher** to discover and override the fix's DLLs/INI files. Files that match are the fix; matching `.dll` files are added to `WINEDLLOVERRIDES` with `=n` (`win*.dll` gets `=n,b`):

```
(?i)^(emp|custom)\.dll$|^win.*\.dll$|^(online|steam).*\.(dll|ini|json)$|^eos.*\.dll$|^epicfix.*\.dll$|^(winmm|dlllist)\.txt$|^launch_data\.of.*$
```
Source: `FixParser::parseDlls` in <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>

That expands to these families:

| Pattern | Meaning |
|---|---|
| `win*.dll` | `winmm.dll`, `winhttp.dll`, `wininet.dll` … → **proxy/loader DLLs** (override `=n,b`) |
| `online*.dll` / `online*.ini` / `online*.json` | `OnlineFix64.dll`, `OnlineFix.dll`, `OnlineFix.ini`, `onlinefix.json` |
| `steam*.dll` / `steam*.ini` / `steam*.json` | `steam_api64.dll`, `steam_api64.ini`, `steamfix64.dll`, `SteamOverlay64.dll`, `steamclient64.dll` |
| `eos*.dll` | `EOSAuthHooker64.dll`, `EOSSDK-Win64-Shipping.dll` (Epic Online Services layer) |
| `epicfix*.dll` | Epic-side fix |
| `winmm.txt` / `dlllist.txt` | **text list of DLLs to inject** |
| `launch_data.of*` | Photon-launcher data |

Additional confirmed real file names from GridinSoft's `Online-Fix` company index: `OnlineFix64.dll`, `OnlineFix.dll`, `Custom.dll`, `EOSAuthHooker64.dll`, `PhotonBridge.dll`, `EOSSDK-Win64-Shipping.dll`, `steam_api.dll`, `steam_api64.dll`, `Launcher.exe`, `ForzaHorizon5_loader.exe` — <https://threatinfo.net/companies/Online-Fix>

### 2.2 CONCRETE EXAMPLE 1 — `mcb-dlls` (complete 4-file payload, verbatim hashes)

A public GitHub repo mirroring an OnlineFix payload contains **exactly four files** (GitHub API tree, sizes in bytes):

| File | Size (bytes) |
|---|---|
| `OnlineFix.ini` | 323 |
| `OnlineFix64.dll` | 10,817,536 |
| `dlllist.txt` | 15 |
| `winmm.dll` | 506,368 |

Source: <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1> (repo: <https://github.com/SpeedyCoder1192/mcb-dlls>)

`dlllist.txt` content (verbatim, 15 bytes):
```
OnlineFix64.dll
```
Source: <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/dlllist.txt>

`OnlineFix.ini` content (verbatim):
```ini
[Main]
#Language=en-US
ProductId=9NBLGGH2JHXJ

[Hashes]
0=7f0745a64e08d858b9adb6545f114afd3e405bf1f1d10fe1d18507b9f63cfa97e0d5eca8b4a9c01245fc774587636dbcdc7ea9a75d9b8184dc8a2b939bc4928e
1=859336ac0aa358ba35f99fde4fcea8bf4dd60667ae39d2858bc996e73145169418b701f2816dbf3f568095232d6fdc8039ea58bccf0561dc768b21962938df2f
```
Source: <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini>

Notes: `ProductId=9NBLGGH2JHXJ` is a Microsoft Store product ID format; `[Hashes]` holds two SHA-512 digests (integrity/anti-tamper or per-file pins). Repo name "mcb" suggests a Minecraft-Bedrock-family title. **SPECULATION:** the `Hashes` values are a file-integrity check of the host game; I could not source a specification of this section.

This example shows the minimal loading chain: **`winmm.dll` (proxy) → reads `dlllist.txt` → loads `OnlineFix64.dll`**, with `OnlineFix.ini` as configuration. Machine-code confirmation of a load-from-list design: the emulator's own error string is "**failed to load onlinefix64.dll from the list error 126/225**" / "from the list" — <https://mywebpc.ru/windows/onlinefix64-dll/> and the Chinese DS3 guide documents a `dlllist.txt` whose entries must all exist, warning "**不要有空行**" (no blank lines — a blank line is treated as a DLL name, causing `Failed to load dll from the list`) — <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md>

### 2.3 CONCRETE EXAMPLE 2 — Dying Light 2 (OnlineFix + Epic/EOS variant)

Documented game-directory layout `\ph\work\bin\x64` contains:

* `steam_api64.ini` (an INI belonging to the emulator's `steam_api64.dll`)
* `OnlineFix.ini`
* `DL2_Offline.bat` and `DL2_Online.bat` (two launch modes)
* Fix source credited as online-fix.me, with Epic Online Services login flow

Verbatim: "安装完后打开目录`\ph\work\bin\x64`用记事本打开`steam_api64.ini`和`OnlineFix.ini`在Language=那栏都改为schinese即是中文" — after install, open directory `\ph\work\bin\x64`, open `steam_api64.ini` **and** `OnlineFix.ini` in Notepad and change `Language=` to `schinese` for Chinese.
Source: <https://www.xmy7.com/sjyx/80210.html>

This confirms the presence of **both** `steam_api64.ini` (so a `steam_api64.dll` wrapper in the same folder) and `OnlineFix.ini`. It also confirms "*离线**和**在线修复包括*" (both offline and online fixes included) and that it supports online play with legitimate owners.

### 2.4 CONCRETE EXAMPLE 3 — Dark Souls 3 / Seamless Co-op (Chinese mod docs)

Documents: `OnlineFix64.dll` in the game directory, `OnlineFix.ini` with a `Language=` key, and `dlllist.txt` enumerating DLLs to inject.

Verbatim: "找到游戏目录中的`dlllist.txt`文件，并打开… 确保文件中涉及到的dll文件都存在，最常见的就是`OnlineFix64.dll`文件被杀毒软件删了" ("Find `dlllist.txt` in the game directory and open it… make sure all DLLs it references exist; most commonly `OnlineFix64.dll` has been deleted by antivirus").
Source: <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md>

It also specifies an expected `OnlineFix64.dll` size: "正确的联机补丁这个文件的大小应该是`11,582 KB`" ("the correct multiplayer patch's file should be `11,582 KB`"). Cross-check: the Triage sandbox sample of `OnlineFix64.dll` is reported as **11.8 MB** = 12,378,521 bytes = 12,088 KiB — <https://tria.ge/260614-q2aywsdt6s>. **SPECULATION:** the values are consistent to within rounding/version drift across OnlineFix releases, indicating OnlineFix64.dll is genuinely ~11–12 MB.

It also confirms `dlllist.txt` is parsed by the loader and that `OnlineFix.ini` carries `Language`.

### 2.5 Other confirmed files and settings

* **`OnlineFixLauncher.ini`** with an `ExeName` key, plus a bundled `Launcher.exe` — from the Saints Row (online-fix.me) patch FAQ: "打开 `OnlineFixLauncher.ini` 文件并将 `ExeName` 设置更改为…**然后再运行一次 `Launcher.exe`**" ("open `OnlineFixLauncher.ini` and change `ExeName`… then run `Launcher.exe` again") — <https://bbs.3dmgame.com/thread-6329126-1-1.html>
* **`OnlineFix.ini`** keys actually documented: `Language`, `RealAppId`, `FakeAppId`, `ExtraProtection` (sections `[Main]`, `[Misc]`, `[OnlineFix Linux]`) — keys extracted from the onlinefix-linux `IniStorage` reads in <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>
* **Saves location:** `C:\Users\Public\Documents\OnlineFix\<AppID>\Saves\...` — e.g. `C:\Users\Public\Documents\OnlineFix\742420\Saves\saves\SR` for Saints Row — <https://bbs.3dmgame.com/thread-6329126-1-1.html>. This confirms the emulator keys its state by **real AppID** (742420 = Saints Row).
* **`winmm.dll` / `winmm64.dll`:** **CONFIRMED PRESENT** in at least some releases (§2.2). It is a proxy DLL (`=n,b` override) and is explicitly named as one of the watched files causing firewall interference — "Windows 防火墙是否拦截游戏 EXE 启动程序、**OnlineFix64.dll**、**winmm.dll** 等相关补丁文件" — <https://www.xmy7.com/sjyx/107808.html>
* **Companion modules:** `PhotonBridge.dll` (Photon networking), `EOSAuthHooker64.dll` / `Custom.dll` (Epic Online Services auth), from <https://threatinfo.net/companies/Online-Fix>, and `EOSAuthHooker` is named as an EOSFix component in <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md>

### 2.6 Point-by-point answers on requested files

| Requested file | Verdict | Evidence |
|---|---|---|
| `steam_api64.dll` | **YES — shipped, and it is a custom OnlineFix build, NOT Goldberg.** ProductName `Steam Wrapper`, CompanyName `Online-Fix`, digitally signed by `OnlineFix`, ~6 MB, first seen 2020-12-27 | <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066> |
| `steamclient64.dll` | **YES in behaviour, NOT as a file named `steamclient64.dll`.** The emulator *implements the Steam client* — its own FileDescription is "Online-Fix Steamclient" — and is loaded via `WINEDLLOVERRIDES` keys `steamclient`/`steam_api64`/`OnlineFix64` plus the `SteamClientDll64` registry mechanism. I found **no** documented OnlineFix release shipping a file literally named `steamclient64.dll` — see **NOT FOUND** note below | <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>; <https://feddit.it/post/504803/4598192>; <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/work_items/262> |
| `OnlineFix64.dll` | **YES — the core file**, ~10.5–12 MB, signed, ProductName/FileDescription "Online-Fix Steamclient" | <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>; <https://tria.ge/260614-q2aywsdt6s>; <https://tria.ge/260614-cjlqsacv3j/static1> |
| `winmm.dll` / `winmm64.dll` | **YES — present in at least some releases** (proxy/loader), override `winmm=n,b` | <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>; <https://feddit.it/post/504803/4598192>; <https://www.xmy7.com/sjyx/107808.html> |
| `steam_appid.txt` | **NOT FOUND in OnlineFix releases; and it must be ABSENT.** OnlineFix sets the AppID through `OnlineFix.ini` (`FakeAppId`) and via the Steam client, not a text file. A Linux guide explicitly says: if the game keeps opening the store, "**VERIFY THAT A FILE CALLED `steam_api.txt` IS NOT IN THE GAME'S FOLDER, IF IT IS REMOVE IT**" | <https://feddit.it/post/504803/4598192> |
| `OnlineFix.ini` / config | **YES — confirmed**, with keys `RealAppId`, `FakeAppId`, `Language`, `ExtraProtection` | <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>; <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini>; <https://bbs.3dmgame.com/thread-6382542-1-1.html> |

> **NOT FOUND:** a documented OnlineFix release whose file list literally includes `steamclient64.dll`. The word "steamclient" appears as (a) the emulator's own product description ("Online-Fix Steamclient") and (b) a `WINEDLLOVERRIDES` key name users must set. Whether some OnlineFix builds *do* drop a literal `steamclient64.dll` is **unresolved from public sources**.

> **Contradiction to flag:** one repack FAQ claims the fix deliberately omits `steam_api64.dll` — "只是愚蠢地替换了游戏根目录下的`steam_api64.dll`文件，这是无法做到的，因为**我们的修复不包含这个文件**" ("[the repacker] stupidly replaced `steam_api64.dll` in the game root — that cannot be done, because **our fix does not include this file** (and shouldn't)") — <https://bbs.3dmgame.com/thread-6329126-1-1.html>. This is contradicted by hard file-reputation evidence that `steam_api64.dll` is signed by `OnlineFix` with CompanyName `Online-Fix` / Product `Steam Wrapper` (source above). Most likely explanation (**SPECULATION**): the statement referred to a specific *Steam-Fix* variant or an older release, or the author meant the *pristine Valve* file must be kept in some configurations. Treat the "no `steam_api64.dll`" claim as unreliable.

---

## 3. How OnlineFix achieves multiplayer

### 3.1 The mechanism — **(b) is FALSE, (c) is FALSE, (d) is FALSE; the answer is (a), with the specific twist of AppID spoofing**

Confirmed answer: **OnlineFix runs the game under the genuine, logged-in Steam client and makes the game believe it owns a real free/placeholder Valve AppID — canonically Spacewar (480) — so that the game's Steamworks multiplayer APIs (lobbies, matchmaking, P2P/SteamNetworkingSockets, Steam Datagram Relay) are served by Valve's real backend.**

This is independently and near-identically stated by a third-party technical guide describing the same class of fix ("Unsteam", which is the same "pretend to be Spacewar" family):

> "Unsteam 让游戏伪装成 Steam 的免费占位标题 **Spacewar（AppID 480）** 运行，借 Steam 的官方网络联机。**需要 Steam 客户端登录**；联机对象不限破解玩家。"
> ("Unsteam makes the game run disguised as Steam's free placeholder title **Spacewar (AppID 480)**, borrowing Steam's official network for multiplayer. **Requires a logged-in Steam client.**")
> Success indicator: "Steam 个人状态栏显示正在玩 **Spacewar**" ("your Steam profile status shows you are playing **Spacewar**")
> Config keys: `real_app_id=<the game's real Steam AppID>` and `fake_app_id=480  ; Spacewar, 不用改` ("Spacewar, don't change")
> Source: <https://blog.syouiti.com/游戏破解指南/>

And directly for OnlineFix, via the `OnlineFix.ini` `FakeAppId` key:

> "文件夹里面有个叫 `OnlineFix.ini` 的档案，点开可以修改 `FakeAppId` 去你想使用的平台连线… 已知有3个平台供你连线
> `FakeAppId=480` 是 spacewar 的
> `FakeAppId=1836450` 是 DEMO 的
> `FakeAppId=314970` 是 AGE 的"
> ("There is a file called `OnlineFix.ini`; open it to change `FakeAppId` to the platform you want to connect through… There are 3 known platforms:
> `FakeAppId=480` — Spacewar's
> `FakeAppId=1836450` — the DEMO's
> `FakeAppId=314970` — AGE's")
> Source: <https://bbs.3dmgame.com/thread-6382542-1-1.html> (restated at <https://bbs.3dmgame.com/thread-6387209-1-15.html>)

Crucially, the community notes that these are **separate populations / separate "channels"**, and that switching AppID changes who you can meet:

* "本来人就少，appid分散之后，更加少了" ("there were few people to begin with; once the appids are split up there are even fewer") — <https://bbs.3dmgame.com/thread-6382542-1-1.html>
* "age版联机去人还是不少的，你看看换个联机补丁试试" ("the AGE version still has a fair number of players online; try switching to a different multiplayer patch") — <https://bbs.3dmgame.com/thread-6387209-1-15.html>

This "different AppID = different matchmaking/matchmaking pool" behaviour is only possible if the fix is rewriting the AppID used for **real Steam backend calls** — i.e. the game is talking to Valve.

Independent corroboration that this is Valve's infrastructure: the appids named are real, free/zero-cost Valve apps, which is exactly what makes them usable as "ownership-free" placeholders:
* AppID **480 = Spacewar**, Valve's long-standing free Steamworks test title.
* AppID **1836450 = Monster Hunter Rise: Sunbreak Demo** — <https://steamdb.info/app/1836450/>
* AppID **314970 = Age of Conquest IV** — <https://steamdb.info/app/314970/>

Mechanically, the fix performs an AppID **translation**: `OnlineFix.ini` exposes `RealAppId` (the true game) and `FakeAppId` (Spacewar or similar). The onlinefix-linux launcher reads both and, for a Steam-Fix variant, even rewrites them into a `[OnlineFix Linux]` INI section:

```php
$realAppID = $ini->get('RealAppId','OnlineFix Linux') ?? $ini->get('RealAppId','Main');
$fakeAppID = $ini->get('FakeAppId','Main');
…
$ini->set('RealAppId',$fakeAppID,'Main');
$ini->set('RealAppId',$realAppID,'OnlineFix Linux');
…
if ($ini->get('ExtraProtection', 'Misc') != null)
    $ini->set('ExtraProtection', 'false', 'Misc');  // disables an anti-tamper check
```
Source: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>

And critically, **`RealAppId` is used for the game's real identity** — the launcher fetches the game's cover art from Steam's CDN keyed on it (`https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg`), while `FakeAppId` is pushed to the Steam overlay as `SteamOverlayGameId` **defaulting to 480**. Both in the same file — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php> and <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>:

```php
'SteamOverlayGameId' => app()->appModule()->games->get('fakeSteamID',$name) ?? 480
```

So: **real game identity ↔ real AppID for content/cover, spoofed free AppID (480) for the Steam session and networking.** That is exactly option **(a)**.

### 3.2 Why (b), (c) and (d) are rejected

**(b) Own relay/master server by the OnlineFix authors — REJECTED as the primary mechanism.**
The observable behaviour is that users are pooled per *Steam AppID* (480 / 1836450 / 314970) and see *Steam* game/overlay identity, which is impossible for a private relay to produce. Also, a fix that used its own master server would not need `FakeAppId` at all.
**NOT FOUND:** any evidence of an OnlineFix-operated relay/master endpoint (domain, IP range, or protocol). I explicitly searched for OnlineFix relay infrastructure and found none. If such a thing exists, it is undocumented publicly. **SPECULATION:** OnlineFix does operate *some* ancillary servers (the site, login, fix downloads, and possibly a Photon-based layer — see `PhotonBridge.dll`), but not the game-session relay.

**(c) Goldberg-style LAN emulation + VPN — REJECTED.** Goldberg's own documentation is explicit and decisive:
> "An emulator that supports **LAN** multiplayer **without steam**." … "**You must all be on the same LAN for it to work.**"
> <https://raw.githubusercontent.com/GeospatialDaryl/Goldberemu/master/Readme_release.txt> and <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>

Goldberg is LAN-only and Steam-client-free; OnlineFix is internet-capable and Steam-client-*requiring*. These are mutually exclusive designs. A Chinese guide draws the same line, presenting them as the two distinct alternatives: "**在线联机需求**：使用 Unsteam（伪装免费占位游戏借助 Steam 联机）。**单机/局域网需求**：使用 GBE Fork（完全离线独立运行模拟器）" — "for **online** you use Unsteam (disguise as a free placeholder game and use Steam for multiplayer); for **offline/LAN** you use GBE Fork (fully offline standalone emulator)" — <https://blog.syouiti.com/游戏破解指南/>. It also notes GBE Fork "不依赖 Steam 客户端，但**无法在线公网匹配**" ("does not depend on the Steam client, but **cannot matchmake over the public internet**").

**(d) Custom SteamNetworkingSockets-compatible relay — REJECTED.** No evidence of an OnlineFix-authored `ISteamNetworkingSockets`/`ISteamNetworkingMessages` relay service exists. What *does* exist are open-source projects that *emulate* those interfaces locally (see §7), but those are independent of OnlineFix and are LAN/P2P-oriented.

**Nuance to note:** OnlineFix is not purely one thing. There are two distinct OnlineFix product lines visible in the evidence:
1. **Steam-Fix** (the main one, described above) — Spacewar-style AppID spoofing over the real Steam client. `steamfix64.dll` / `steamfix.ini` variants exist (onlinefix-linux handles `steamfix*.dll` and a "FreeTP patch" for `steamfix.ini`; <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>).
2. **EOS/Epic-side fixes** — `EOSAuthHooker64.dll`, `EOSSDK-Win64-Shipping.dll`, `Custom.dll`, and a "Photon Launcher" (`launch_data.of*`, `onlinefix.json`, `Launcher.exe`, `Newtonsoft.Json.dll`) for EOS and Photon-backed games. The Dying Light 2 example requires an **Epic Games account login** and connects to **Epic's** servers, not Steam's — <https://www.xmy7.com/sjyx/80210.html>. The onlinefix-linux README lists compatibility classes "SteamFix", "SteamFix + EOSFix (combined)", "EOSFix", and "Custom OnlineFix servers (Photon Launcher)" — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md>
So for EOS/Photon titles the network path is the *real* Epic/Photon backend with the *real* user's (possibly throwaway) account — again real infrastructure, not an OnlineFix relay.

### 3.3 Gaming the Steam Datagram Relay

Valve's Steam Datagram Relay (SDR) is Valve's own relay network used by SteamNetworkingSockets, and Steamworks documentation confirms it exists as first-party infrastructure — <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>. Because Spacewar (480) is a real Steam AppID and the session is a real (if unowned) Steam session, `ISteamNetworkingSockets` calls using SDR will be brokered by Valve. **CONFIRMED at the level of "the design must route through Valve"; I did not find a packet capture explicitly showing an SDR connection established by an OnlineFix session — treat the SDR-specific detail as strongly implied rather than directly observed.**

### 3.4 How the emulator evades detection ("why it's not just Goldberg")

Two load mechanisms, both pointing at Steam-client-level hooking rather than a drop-in `steam_api` replacement:

1. **`WINEDLLOVERRIDES` (Linux/Proton)** — the fix is installed by forcing the game to load *its* DLLs under the names of several Steam/system libraries at once:   ```
   WINEDLLOVERRIDES="OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n" %command%
   ```
   and a second, user-confirmed working variant:
   ```
   WINEDLLOVERRIDES="custom=n;onlinefix64=n;steam_api64=n;steamoverlay64=n;winmm=n,b" %command%
   ```
   Sources: <https://feddit.it/post/504803/4598192> and <https://github.com/hydralauncher/hydra/issues/2379>
   The `steam_api64=n` override means the game's `steam_api64.dll` import is redirected to the OnlineFix module — i.e. OnlineFix substitutes itself *as* the Steam API **and** as `winmm`, `SteamOverlay64`, `dnet`, `custom`.
   OnlineFix-linux generalises this: it scans the fix folder and emits `name=n;` for every matching DLL, or `name=n,b;` for `win*.dll` proxies — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>

2. **`steamclient` hijack (Windows)** — Goldberg's issue tracker documents the registry mechanism this class of fix uses: `HKCU\SOFTWARE\Valve\Steam\ActiveProcess\SteamClientDll64` pointing at the emulator's `steamclient64.dll`. That issue is about Goldberg's experimental `steamclient` build, which is the *same* architectural slot OnlineFix occupies — <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/work_items/262>

The `OnlineFix64.dll` binary's PE structure is consistent with a client-level hook rather than a data-only emulator: Triage's static analysis of one sample shows an unusual `.of0` / `.of1` / `.of2` section naming (the "of" marker matching "OnlineFix" and the `launch_data.of*` file family) and, in one variant, a **10.7 MB `.of2` section with entropy 7.79 reported as packed/encrypted** — <https://tria.ge/260614-cjlqsacv3j/static1>. GridinSoft reports the same `.of0`/`.of1`/`.of2` layout with `.of1` holding ~100% of section data — <https://threatinfo.net/files/OnlineFix64.dll-891d5812ed5120816ddc9b0f5ece5d1a>. Exports are minimal; Triage lists an export named `OnlineFix` and `QueryApiImpl`, and a `rundll32 … OnlineFix64.dll,#1` invocation succeeds — <https://tria.ge/260614-qjlqsacv3j/static1> (see also <https://tria.ge/260614-q2aywsdt6s/behavioral1>).

---

## 4. Steam client requirement and AppID handling

### 4.1 Does it require the real Steam client installed AND logged in? — **YES, both.**

**Installed (hard requirement):** The onlinefix-linux launcher aborts if Steam is missing:
```php
if (execute("which steam")->getExitValue() != 0) {
    … UXDialog::showAndWait(…'FILESWORKER.NOSTEAM'…'ERROR');   // "Steam is not installed or installed via Flatpak/Snap"
    return;
}
```
Source: `FilesWorker::generateProcess` — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>

**Running (hard requirement):** if `pidof steam` returns 1, the launcher **starts Steam itself** (`steam -silent`) and then **waits for `~/.steam/steam/config/loginusers.vdf` to change** before proceeding — up to 420 attempts (7 minutes) — clearly meaning *waiting for the user to be logged in*:
```php
elseif (execute('pidof steam',true)->getExitValue() == 1) {
    $steam = self::runSteam();
    if ($steam == false) { … 'FILESWORKER.STEAMNOTSTARTED' … return; }   // "Steam is not running"
}
…
$logUsers = File::of($home.'/.steam/steam/config/loginusers.vdf');
$lastMod = $logUsers->lastModified();
while ($attempts <= 420 and ($logUsers->exists() == false or $logUsers->lastModified() == $lastMod)) { … }
```
Source: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>

**Logged in (semantics):** the login-state wait above is the direct evidence. Corroborating community/technical statements:
* The Chinese guide's prerequisite for the equivalent fix: "`Unsteam` —— 联机补丁（**需 Steam 客户端运行**）" ("Unsteam — multiplayer patch (**requires the Steam client to be running**)"); and "确保 Steam 客户端**已登录**" ("make sure the Steam client is **logged in**") — <https://blog.syouiti.com/游戏破解指南/>
* The DS3 mod docs' most common OnlineFix error is literally "**Steam is not launched**" (`steam未启动`), with the prescribed fix being "如果steam没有启动，那就启动steam，再启动游戏" ("if Steam is not running, start Steam, then start the game") — <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md>
* Hydra users report the fix only works when the game is launched **from the Steam library**, not from a third-party launcher: "For it to work I need to launch the game from the Steam library with those same arguments" — <https://github.com/hydralauncher/hydra/issues/2379>

**There is an optional bypass of the "Steam must be running" check**, and its existence is itself evidence of the requirement. onlinefix-linux ships a setting labelled in its UI as "**Bypass «Steam not running»**" (`GAMESETTINGS.ADDITIONALS.USEFAKESTEAM`, i.e. `noSteamRequest`), which monkey-patches `steamfix32.dll`/`steamfix64.dll` to a stub `ftpPath*.dll` and renames the original to `*.noofllpath`:
```php
$dlls = File::of($fixPath)->findFiles(… '^steamfix(32|64)\.dll$' …);
fs::rename($dll, fs::name($dll).'.noofllpath');
fs::copy(ResourceStream::of(…'ftpPath64.dll'), $dll);
```
Sources: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/forms/gameSettings.php> and localization key `"GAMESETTINGS.ADDITIONALS.USEFAKESTEAM": "Bypass «Steam not running»"` in <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/locale/en.json>. **SPECULATION:** this bypass is for FreeTP-style fixes and/or offline play; it is not the normal online path.

### 4.2 Does it use the game's real AppID or a changed one? — **BOTH. This is the core trick.**

* The **real AppID** is preserved for game identity/entitlement lookups, save paths (`…\OnlineFix\<realAppID>\…`), Steam cover art, and user-facing metadata. Evidence: `RealAppId` INI key + the cover-art fetch by `$appId` and `games->set('steamID',$parsed['realAppId'])` — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>, <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/forms/newGameConfigurator.php>; save path `OnlineFix\742420\` for Saints Row (742420) — <https://bbs.3dmgame.com/thread-6329126-1-1.html>
* The **AppID presented for the Steam session / matchmaking / overlay is changed** to a free placeholder — `FakeAppId`, canonically **480 (Spacewar)**, with 1836450 and 314970 as alternates — <https://bbs.3dmgame.com/thread-6382542-1-1.html>, <https://bbs.3dmgame.com/thread-6387209-1-15.html>, <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/modules/FilesWorker.php>
* A **third-party tool implements the identical pattern at the Steam-client level** and describes it explicitly: "**LC Online Fix** — toggle `-onlinefix` on a chosen App ID in `localconfig.vdf` … **LumaCore handles the appid-480 redirect at launch** so the overlay, Steam Input, and screenshots still tag the real game." — <https://github.com/Midrags/SFF/blob/main/README.md>
* "Spacewar auto-check: reads all Steam library ACF files to detect if **Spacewar (AppID 480)** is already installed" — a tool literally verifies you have AppID 480 available, because the fix depends on it — <https://github.com/Midrags/SFF/blob/main/CHANGELOG.md>

### 4.3 Direct answers to the searched-for phrases

| Phrase | Finding |
|---|---|
| "Steam must be running" | **CONFIRMED.** Error string/message "Steam is not running" (`FILESWORKER.STEAMNOTSTARTED`) and doc error "**Steam is not launched**". Sources: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/locale/en.json>, <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md> |
| "log in to Steam" | **CONFIRMED.** Logged-in state is required; the launcher waits for `loginusers.vdf` to change. Sources: <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/modules/FilesWorker.php>, <https://blog.syouiti.com/游戏破解指南/> |
| "`steam_appid.txt`" | **CONFIRMED IT MUST NOT BE PRESENT.** Linux guide: "VERIFY THAT A FILE CALLED `steam_api.txt` IS NOT IN THE GAME'S FOLDER, IF IT IS REMOVE IT" — because it would override the spoofed AppID and send the game to the store page. Source: <https://feddit.it/post/504803/4598192> |
| "AppID 480" | **CONFIRMED.** 480 is the default `FakeAppId`; also the launcher's default `SteamOverlayGameId`. Sources: <https://bbs.3dmgame.com/thread-6382542-1-1.html>, <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/modules/FilesWorker.php> |

---

## 5. Relationship to Goldberg Steam Emulator

**CONFIRMED: OnlineFix is NOT a fork of Goldberg. There is no evidence of any code relationship, and the two projects' own documentation describes mutually incompatible architectures. I found NO statement by either author about the other.**

Evidence for non-relationship:

1. **Different authors and different ProductName/CompanyName.** Goldberg/gbe_fork binaries are identified as Goldberg; OnlineFix files carry `CompanyName = Online-Fix` / `Online-Fix.Me` and `ProductName = Steam Wrapper` or `Steamclient`, plus `LegalCopyright … 0xdeadc0de` — <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>, <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066>. OnlineFix releases/repacks are tagged `-0xdeadc0de` / `-OFME` (e.g. `beamng.drive.v0.24.1.1-0xdeadc0de`, `plague.inc.evolved.v1.18.3.2-ofme`) — <https://threatinfo.net/files/OnlineFix64.dll-891d5812ed5120816ddc9b0f5ece5d1a>
2. **No Goldberg code/attribution anywhere in OnlineFix artefacts.** Goldberg's licence/credits and its `steam_settings` config model do not appear in any OnlineFix file listing I found. OnlineFix uses its own `OnlineFix.ini` / `OnlineFixLauncher.ini` / `dlllist.txt` / `steam_api64.ini` scheme.
3. **Opposite network models.** Goldberg: LAN-only, "**without steam**", "**You must all be on the same LAN**" — <https://raw.githubusercontent.com/GeospatialDaryl/Goldberemu/master/Readme_release.txt>, <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>. OnlineFix: internet-capable, Steam-client-required, AppID-spoofing.
4. **Third-party tooling treats them as separate, alternatives.** SteaMidra lists `gbe_fork` as an **offline** "Crack a game" component while listing online-fix.me as a separate **Multiplayer Fix** — <https://github.com/Midrags/SFF/blob/main/README.md>. onlinefix-linux lists them as distinct categories and even lists "SteamFix", "EOSFix", "FreeTP", "Photon Launcher" as *different* fix families — <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md>
5. **`gbe_fork` README files** contain no mention of OnlineFix, Spacewar or AppID 480 spoofing — <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>

**NOT FOUND:** any statement by Mr_Goldberg, Detanup01 (gbe_fork), or the OnlineFix authors/0xdeadc0de about each other. I searched for this specifically and found nothing. Do not assert a relationship.

**One shared technique, however:** both use the *same architectural slot* on Windows — hijacking/replacing the `steamclient64.dll` used by the Steam client (Goldberg experimentally; OnlineFix as its core product), as documented in Goldberg's own issue tracker via the `SteamClientDll64` registry value — <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/work_items/262>. That is convergence, not descent.

---

## 6. Security, trust and antivirus concerns

### 6.1 AV detection — **CONFIRMED heavily flagged**

* **24 of 71 VirusTotal engines** flag a specific `OnlineFix64.dll` (SHA-256 `27eb85e42e1c67706133f8fb3d12f9d782fff25d49ce3738de1b13fc25bdae3a`) as malicious; Microsoft's signature is named as **`HackTool:Win32/GameHack!MSR`** — <https://mywebpc.ru/windows/onlinefix64-dll/> (VirusTotal permalink given there: <https://www.virustotal.com/gui/file/27eb85e42e1c67706133f8fb3d12f9d782fff25d49ce3738de1b13fc25bdae3a>)
* A separate aggregated scan reports **47/75 detections** for an `OnlineFix64.dll` sample — <https://tools.malwaretips.com/file-scan/d687fcd5d3942793218036cde1b8c39d4ada63d2f4aa08778fc2722a4dc65f99>
* GridinSoft classifies samples as **`Trojan.Win64.Packed.ns`** (family: Packed), **`Hack.Patcher`**, **`Trojan.Heur!`**, **`Trojan.Packed`**, **`Trojan.Downloader`**, **`Trojan.ExtHeur!`** — <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>, <https://threatinfo.net/companies/Online-Fix>
* Triage sandbox: static score 3/10, with the packer signal "**1 section with high entropy (≥7.5) detected**"; one behavioral run scored 1/10 with **0 network requests** (consistent with a DLL that does nothing without a host game) — <https://tria.ge/260614-cjlqsacv3j/static1>, <https://tria.ge/260614-q2aywsdt6s/behavioral1>
* Aggregated `OnlineFix64.dll` detection names across samples: `Hack.Patcher`, `Trojan.Heur!`, `Trojan.Packed`, `Trojan.Downloader` — <https://threatinfo.net/companies/Online-Fix>

### 6.2 The alarming data point that must be reported honestly

The GridinSoft `Online-Fix` company index lists these detections (among 30 files) — <https://threatinfo.net/companies/Online-Fix>:

| File | Detection | Last seen |
|---|---|---|
| `ForzaHorizon5_loader.exe` | **`Ransom.Wacapew`** | 2024-08-11 |
| `ConanSandbox.exe` | **`Trojan.Downloader`** | (per certificate page) |
| `Launcher.exe` (2 hashes) | `Trojan.Agent`, `Trojan.Occamy` | — |
| `Launcher.exe` | `Trojan.Downloader` | 2024-05-11 |
| multiple `OnlineFix64.dll` | `Trojan.Downloader`, `Hack.Patcher`, `Trojan.Heur!`, `Trojan.Packed` | through 2026-09 |
| multiple `Custom.dll` | `Trojan.Heur!`, `Hack.Patcher` | through 2026-05 |
| multiple `PhotonBridge.dll` | `Trojan.Heur!`, `Trojan.Packed`, `Trojan.Downloader` | through 2026-09 |
| `EOSAuthHooker64.dll`, `EOSSDK-Win64-Shipping.dll` | `Trojan.Heur!` | through 2026-07 |
| `steam_api.dll` / `steam_api64.dll` | `Trojan.Heur!`, `Trojan.Gen` | 2020–2026 |

Sources: <https://threatinfo.net/companies/Online-Fix>, <https://threatinfo.net/certificates/OnlineFix>

**Interpretation — what is confirmed vs. speculation:**

* **CONFIRMED:** these files are *routinely and heavily* flagged, including by name-brand engines, including categories far more serious than "game hack" (`Ransom`, `Trojan.Downloader`). A ransomware label on `ForzaHorizon5_loader.exe` in particular is not explainable as a generic game-hack false positive.
* **CONFIRMED:** GridinSoft/ThreatInfo's own meta-warning explicitly says the publisher signature name should not be trusted on its own: "ThreatInfo found detected files associated with OnlineFix. A matching signature name should be checked together with the file hash, detection verdict, and source path." — <https://threatinfo.net/certificates/OnlineFix>
* **CONFIRMED (adverse):** the site is also a reputation risk — 35/100 "Suspicious" — <https://gridinsoft.com/online-virus-scanner/url/online_fix-me>
* **CONFIRMED (distinct mechanism):** `OnlineFix.ini` carries an `[Hashes]` block with SHA-512 pins — <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini> — i.e. the emulator verifies file integrity of something it loads. This is anti-tamper, and it is also what a loader that fetches/validates external content looks like. The section is undocumented publicly.
* **NOT FOUND:** any vendor *writeup* (as opposed to a signature) proving OnlineFix64.dll bundles a **miner** or **adware**. I searched specifically for miner/adware analyses and found none. The widely-cited "24/71" figure is a detection *count*, not an analysis.
* **NOT FOUND:** any proof that OnlineFix64.dll itself steals credentials or exfiltrates data. But note that the *architecture itself* is the risk: the fix requires a **genuine logged-in Steam account**, sits between the game and the Steam client, and (for EOS variants) requires an **Epic account login** — so it is positioned to observe session material. The Dying Light 2 instructions even advise using a throwaway: "登录 Epic Store 将游戏链接到您的帐户（**如果您担心主帐户，请使用假帐户**）" ("log in to Epic Store to link the game to your account — **if you're worried about your main account, use a fake account**") — <https://www.xmy7.com/sjyx/80210.html>. That advice appears in OnlineFix-derived instructions, i.e. the ecosystem does not vouch for its own safety.
* **CONFIRMED innocent factor:** the emulator uses a **packer/obfuscator** and is **unsigned** in some samples. Triage's static report for one sample lists "**Unsigned PE**" as the *only* signature finding — <https://tria.ge/260614-cjlqsacv3j/static1> — while GridinSoft's metadata for other samples claims a **valid signature by `OnlineFix`** — <https://threatinfo.net/files/OnlineFix64.dll-891d5812ed5120816ddc9b0f5ece5d1a>. Both facts raise the false-positive rate: packing + unsigned/self-signed + a tiny import table (`kernel32`, `user32`, `shell32` — plus `ws2_32`, `wldap32`, `advapi32` in another sample) is a textbook heuristic trigger.
* **CONFIRMED for the Goldberg comparison point:** a parallel project openly acknowledges the same false-positive pattern — "The Windows build is signed with a fake self-signed certificate… but it also triggers some antivirus software… the project is not a malware, if your antivirus software complains, be sure it's a false-positive." — <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>. OnlineFix makes no such public statement that I could find (**NOT FOUND**).

**Bottom line for §6:** OnlineFix64.dll is **confirmed** to be near-universally flagged by AV (including serious detection classes), **confirmed** to be packed/obfuscated and inconsistently signed, and **NOT confirmed** to contain a miner/adware/stealer by any published analysis. The publicly verifiable risk is *unverifiable binaries handling a live Steam/Epic session*, plus at least one sample-class flagged as ransomware. There is no independent audit of the OnlineFix binaries; nothing here should be treated as a clean bill of health.

---

## 7. GitHub / open-source projects that document or reimplement this approach

### 7.1 Direct OnlineFix-related repositories

| Project | URL | What it is |
|---|---|---|
| **ZzEdovec/onlinefix-linux** (OFLL) | <https://github.com/ZzEdovec/onlinefix-linux> | **The single most valuable public source.** An open-source launcher (PHP/DevelNext) that discovers, patches and launches OnlineFix games on Linux. Its `FixParser.php` documents the exact file-name grammar, the INI keys (`RealAppId`, `FakeAppId`, `ExtraProtection`, `Language`), and the AppID-translation logic; `FilesWorker.php` documents the Steam-running/logged-in requirement, the `WINEDLLOVERRIDES` construction, the `SteamOverlayGameId` default of 480, and the Proton launch environment; `gameSettings.php` documents the "Bypass Steam not running" monkey-patch of `steamfix64.dll` and the Photon-launcher patch. AUR package: <https://aur.archlinux.org/packages/onlinefix-linux-launcher-bin> |
| **SpeedyCoder1192/mcb-dlls** | <https://github.com/SpeedyCoder1192/mcb-dlls> | A verbatim archived OnlineFix payload (4 files: `OnlineFix.ini`, `OnlineFix64.dll`, `dlllist.txt`, `winmm.dll`) — the cleanest concrete file-list example available |
| **Midrags/SFF (SteaMidra)** | <https://github.com/Midrags/SFF> | Documents the AppID-480 redirect pattern independently (`LC Online Fix`, `localconfig.vdf`, Spacewar ACF detection). Not an OnlineFix reimplementation; a different (client-side) approach to the same problem. Multiplayer-fix doc: <https://github.com/Midrags/SFF/blob/main/docs/MULTIPLAYER_FIX.md> |
| **hydralauncher/hydra** issue #2379 | <https://github.com/hydralauncher/hydra/issues/2379> | Community documentation of the exact `WINEDLLOVERRIDES` strings needed for OnlineFix, and the fact that the game must be launched from the Steam library |
| **darksouls3-mod-docs** | <https://github.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/blob/main/docs/common_problem.md> | Documents `dlllist.txt`, the expected `OnlineFix64.dll` size, `OnlineFix.ini`'s `Language`, the "Steam is not launched" error, and AV deleting `OnlineFix64.dll` |

### 7.2 SteamNetworkingSockets / relay-emulation projects (requested search terms)

I searched the specific terms requested ("steam emulator relay server internet multiplayer", "Goldberg internet multiplayer relay", "steam P2P emulator relay", "gbe_fork relay", "SpacewarWar", "SteamNetworkingSockets emulator relay"). Findings:

* **"SpacewarWar" — NOT FOUND.** No project or document by this name. The related real concept is simply **Spacewar (Steam AppID 480)**, Valve's free test app, used as the spoofing target (see §4.2).
* **Goldberg / gbe_fork relay server — NOT FOUND, and contrary to Goldberg's design.** `gbe_fork` and Goldberg are explicitly LAN-only ("**You must all be on the same LAN for it to work.**") and offer only *broken* non-LAN stubs: `matchmaking_server_list_actual_type` and `matchmaking_server_details_via_source_query` are documented as "**This is currently broken**" — <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>. Custom broadcast targets (`custom_broadcasts.txt`) extend LAN discovery across IPs/domains but are still broadcast-based, not a relay service.
* **SteamNetworkingSockets emulation exists in these projects:**
  * `Detanup01/gbe_fork` — <https://github.com/Detanup01/gbe_fork> (implements `ISteamNetworkingSockets`/`ISteamNetworkingMessages` locally; LAN transports)
  * `metrixmedia/SteamEmulator` — contains `steamnetworkingsockets.cpp` with `SteamNetworkingMessages_LibV2()` etc. — <https://github.com/metrixmedia/SteamEmulator/commit/3f8ce69b6dc6819abd61c274c57184df9470cdb4> and <https://gitcode.com/gh_mirrors/st/SteamEmulator/blob/main/steamnetworkingsockets.cpp>
  * `sysfce2/Steam_goldberg_emulator` — a re-fork of the Goldberg lineage — <https://github.com/sysfce2/Steam_goldberg_emulator>
* **A project that provides a *real* internet relay for emulated LAN play** (a genuinely different technique, and possibly why the search terms surface): `BentLent/comstar` — "a simple, peer-to-peer UDP relay server designed to connect instances of xemu … across the internet by utilizing the Hyperswarm DHT network" — <https://github.com/BentLent/comstar>. This is the "(b) own relay" model, but for **xemu**, and it is **not** related to OnlineFix.
* **NOT FOUND:** any open-source reimplementation of OnlineFix's specific technique (i.e. an emulator that spoofs the Steam AppID to 480 *and* drives Valve's real backend). OnlineFix itself is **closed-source and obfuscated**; no public source exists for `OnlineFix64.dll`.

### 7.3 Related tooling that names both ecosystems

* `SteamAutoCrack` / SteamAutoCracks — wraps Steamless + Goldberg for offline patching — <https://github.com/SteamAutoCracks/Steam-auto-crack>
* `Steamless` (Atom0s) — SteamStub DRM removal, frequently a prerequisite — <https://github.com/atom0s/Steamless>
* A comprehensive Chinese guide contrasting **Unsteam** (online, Steam-client-based, Spacewar spoof) vs **GBE Fork** (offline/LAN) vs **Nemirtingas Epic Emulator** (EOS) — <https://blog.syouiti.com/游戏破解指南/> (original author credited to Nite07: <https://www.nite07.com/zh-cn/posts/game-crack-tutorial/>)
* `Launcher.exe` + `unsteam_loader64.exe` and `unsteam.ini` with `real_app_id` / `fake_app_id=480` — the same functional design as OnlineFix, documented step by step; a cs.rin.ru thread is cited as its source — <https://blog.syouiti.com/游戏破解指南/>

---

## 8. Confirmed fact vs. community folklore — summary table

| Claim | Status | Source |
|---|---|---|
| OnlineFix = third-party multiplayer fix for cracked games, Russian origin | **CONFIRMED (folklore-sourced but consistent)** | <https://www.xmy7.com/sjyx/107808.html> |
| `OnlineFix64.dll` = "Online-Fix Steamclient", (C) 0xdeadc0de, CompanyName Online-Fix.Me | **CONFIRMED (PE metadata)** | <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8> |
| Ships `OnlineFix64.dll` (~11–12 MB) | **CONFIRMED** | <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>, <https://tria.ge/260614-q2aywsdt6s>, <https://darksouls3-mod-docs.github.io/docs/common_problem/> |
| Ships `winmm.dll` proxy + `dlllist.txt` | **CONFIRMED** | <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>, <https://feddit.it/post/504803/4598192> |
| Ships `OnlineFix.ini` with `RealAppId`/`FakeAppId`/`Language` | **CONFIRMED** | <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>, <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini> |
| Ships a custom `steam_api64.dll` ("Steam Wrapper", signed OnlineFix) | **CONFIRMED** (contradicts one repack FAQ) | <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066> |
| Ships a file literally named `steamclient64.dll` | **NOT FOUND** | — |
| Ships `steam_appid.txt` | **CONFIRMED ABSENT / must be removed** | <https://feddit.it/post/504803/4598192> |
| Is a Steam emulator | **CONFIRMED** | PE FileDescription "Online-Fix Steamclient" |
| Achieves multiplayer via Valve's real Steam servers, using a free placeholder AppID (Spacewar/480) | **CONFIRMED** (strong, multi-source) | <https://bbs.3dmgame.com/thread-6382542-1-1.html>, <https://blog.syouiti.com/游戏破解指南/>, <https://github.com/Midrags/SFF/blob/main/README.md> |
| Uses Valve's Steam Datagram Relay specifically | **STRONGLY IMPLIED, not directly observed** | <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay> |
| Uses an OnlineFix-operated own relay/master server | **NOT FOUND / REJECTED as primary mechanism** | — |
| Uses Goldberg LAN emulation + VPN | **REJECTED** | <https://raw.githubusercontent.com/GeospatialDaryl/Goldberemu/master/Readme_release.txt> |
| Requires real Steam client installed and logged in | **CONFIRMED** | <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/modules/FilesWorker.php>, <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md> |
| Requires real AppID *and* changes the AppID | **CONFIRMED — both, via RealAppId/FakeAppId** | <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/src/app/modules/FixParser.php>, <https://bbs.3dmgame.com/thread-6387209-1-15.html> |
| Is a fork of Goldberg Steam Emulator | **REJECTED** | Opposite network models; no shared code/credits |
| Goldberg/OnlineFix authors commented on each other | **NOT FOUND** | — |
| Commonly flagged by AV (incl. 24/71 and 47/75) | **CONFIRMED** | <https://mywebpc.ru/windows/onlinefix64-dll/>, <https://tools.malwaretips.com/file-scan/d687fcd5d3942793218036cde1b8c39d4ada63d2f4aa08778fc2722a4dc65f99> |
| Bundles miner/adware | **NOT FOUND** (no vendor writeup); `Ransom.Wacapew` detection on `ForzaHorizon5_loader.exe` is CONFIRMED on record | <https://threatinfo.net/companies/Online-Fix> |
| Open-source reimplementation of OnlineFix's technique | **NOT FOUND**; OnlineFix is closed-source/obfuscated | — |
| "SpacewarWar" project | **NOT FOUND** | — |

---

## 9. Explicit gaps (do not guess past these)

1. **NOT FOUND:** a public, authoritative file manifest published *by OnlineFix itself* for any specific game. All file lists above are reconstructed from third-party observations, a mirrored repo, and a launcher's parser.
2. **NOT FOUND:** a documented OnlineFix release shipping a file literally named `steamclient64.dll`.
3. **NOT FOUND:** any analysis of the `[Hashes]` section of `OnlineFix.ini` or of the `.of0`/`.of1`/`.of2` PE section contents.
4. **NOT FOUND:** any statement by OnlineFix or Goldberg authors regarding one another.
5. **NOT FOUND:** any vendor technical writeup (as opposed to AV signature counts) proving or disproving miner/adware/stealer behaviour in OnlineFix64.dll.
6. **NOT OBSERVED DIRECTLY:** a packet capture confirming Steam Datagram Relay usage by an OnlineFix session.
7. **NOT FOUND:** details of how OnlineFix implements the `steamclient` interface at API level (which `ISteam*` interfaces it re-exports and how it forwards to the real client). `OnlineFix64.dll`'s export table is extremely small (`OnlineFix`, `QueryApiImpl` per Triage), so the actual interface surface is **SPECULATION** — likely resolved dynamically at runtime rather than via exported symbols.
8. **NOT FOUND:** confirmation of whether the `Offline` vs `Online` split (`DL2_Offline.bat` / `DL2_Online.bat`) corresponds to switching `FakeAppId`/`RealAppId` or to enabling/disabling the client hook. **SPECULATION:** most likely the latter, but unproven.

---

## 10. Appendix — primary source URLs

**OnlineFix binary metadata / AV**
- <https://zh.gridinsoft.com/online-virus-scanner/id/a188ff24aec863479408cee54b337a2fce25b9372ba5573595f7a54b784c65f8>
- <https://pt.gridinsoft.com/online-virus-scanner/id/155954174a6fa52ec64ca44e4d77f387e7c9f363541c81a4a7812d9c783af3ca>
- <https://threatinfo.net/companies/Online-Fix>
- <https://threatinfo.net/certificates/OnlineFix>
- <https://threatinfo.net/files/OnlineFix64.dll-891d5812ed5120816ddc9b0f5ece5d1a>
- <https://threatinfo.net/files/steam_api64.dll-c6d74dafc1f5cded74ef2dc08062a066>
- <https://threatinfo.net/files/OnlineFix.dll-93fd833da3eed801e0f5d4766741aa27>
- <https://threatinfo.net/files/Launcher.exe-4763bacc1bff9c278e5ca1f44354c183>
- <https://tria.ge/260614-cjlqsacv3j/static1>
- <https://tria.ge/260614-q2aywsdt6s>
- <https://tria.ge/260614-q2aywsdt6s/behavioral1>
- <https://mywebpc.ru/windows/onlinefix64-dll/>
- <https://tools.malwaretips.com/file-scan/d687fcd5d3942793218036cde1b8c39d4ada63d2f4aa08778fc2722a4dc65f99>
- <https://gridinsoft.com/online-virus-scanner/url/online_fix-me>
- <https://ca.trustpilot.com/review/online-fix.me>

**OnlineFix file layout / config / behaviour**
- <https://api.github.com/repos/SpeedyCoder1192/mcb-dlls/git/trees/main?recursive=1>
- <https://github.com/SpeedyCoder1192/mcb-dlls>
- <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/OnlineFix.ini>
- <https://raw.githubusercontent.com/SpeedyCoder1192/mcb-dlls/main/dlllist.txt>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FixParser.php>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/modules/FilesWorker.php>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/forms/newGameConfigurator.php>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/app/forms/gameSettings.php>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/src/locale/en.json>
- <https://raw.githubusercontent.com/ZzEdovec/onlinefix-linux/main/README.md>
- <https://github.com/ZzEdovec/onlinefix-linux>
- <https://aur.archlinux.org/packages/onlinefix-linux-launcher-bin>
- <https://feddit.it/post/504803/4598192>
- <https://github.com/hydralauncher/hydra/issues/2379>
- <https://raw.githubusercontent.com/darksouls3-mod-docs/darksouls3-mod-docs.github.io/main/docs/common_problem.md>
- <https://www.xmy7.com/sjyx/80210.html>
- <https://www.xmy7.com/sjyx/107808.html>
- <https://bbs.3dmgame.com/thread-6329126-1-1.html>
- <https://bbs.3dmgame.com/thread-6382542-1-1.html>
- <https://bbs.3dmgame.com/thread-6387209-1-15.html>
- <https://www.playground.ru/phasmophobia/cheat/phasmophobia_onlajn_fiks_dlya_igry_po_seti-1797471>
- <https://wikidll.com/onlinefix/photonbridge-dll>
- <https://ko.gamegpu.com/news/igry/gruppa-online-fix-vypustila-onlajn-vzlom-dlya-microsoft-flight-simulator-2024>

**AppID / Spacewar / Steam backend**
- <https://blog.syouiti.com/游戏破解指南/> (also <https://www.nite07.com/zh-cn/posts/game-crack-tutorial/>)
- <https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay>
- <https://steamdb.info/app/1836450/>
- <https://steamdb.info/app/314970/>
- <https://github.com/Midrags/SFF/blob/main/README.md>
- <https://github.com/Midrags/SFF/blob/main/CHANGELOG.md>
- <https://github.com/Midrags/SFF/blob/main/docs/MULTIPLAYER_FIX.md>

**Goldberg / gbe_fork**
- <https://raw.githubusercontent.com/GeospatialDaryl/Goldberemu/master/Readme_release.txt>
- <https://raw.githubusercontent.com/Detanup01/gbe_fork/dev/post_build/README.release.md>
- <https://github.com/Detanup01/gbe_fork>
- <https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/work_items/262>
- <https://github.com/sysfce2/Steam_goldberg_emulator>

**Other emulator / relay projects**
- <https://github.com/metrixmedia/SteamEmulator/commit/3f8ce69b6dc6819abd61c274c57184df9470cdb4>
- <https://gitcode.com/gh_mirrors/st/SteamEmulator/blob/main/steamnetworkingsockets.cpp>
- <https://github.com/BentLent/comstar>
- <https://github.com/SteamAutoCracks/Steam-auto-crack>
- <https://github.com/atom0s/Steamless>

**Community/AV discussion**
- <https://steamcommunity.com/app/1623730/discussions/0/4414172285529172295>
