========================================================================
  DIMRAETH - ONLINE CO-OP FIX
  (6 files, no installer, no launcher)
========================================================================

Nothing to install and no script to run.
Just copy the files and press Play in Steam.

Full documentation and troubleshooting:
    https://github.com/<OWNER>/<REPO>


------------------------------------------------------------------------
STEP 1 - Copy
------------------------------------------------------------------------
1. Extract this zip anywhere.

2. Copy the "Dimraeth_Data" folder inside it into your Dimraeth folder,
   accepting the REPLACE prompt.

   Your game folder looks like:
       ...\steamapps\common\Dimraeth\

   It should end up like this:

       Dimraeth\
       |- Dimraeth.exe                        (already there)
       |- Dimraeth_Data\Plugins\x86_64\
          |- steam_api64.dll                  <- REPLACED
          |- steam_appid.txt                  <- NEW
          |- steam_settings\                  <- NEW
             |- steam_appid.txt
             |- force_listen_port.txt
             |- force_account_name.txt
             |- custom_broadcasts.txt

   That is 6 files: 1 replaced and 5 new. Nothing else is touched.

   Do NOT copy only steam_api64.dll. The four files in steam_settings\
   set the AppID, the network port and your display name. Without them
   the emulator uses defaults, and if your default port differs from your
   friend's you will never find each other.


------------------------------------------------------------------------
STEP 2 - Press Play in Steam
------------------------------------------------------------------------
Open Steam and press Play on Dimraeth. That is all.

This works because Dimraeth has no Steam DRM. Steam only starts the
game; it does not replace or check the steam_api64.dll in the game
folder. So the emulator you copied is the one that loads.


------------------------------------------------------------------------
STEP 3 - ZeroTier (so you can find each other online)
------------------------------------------------------------------------
The emulator only looks for players on the local network. ZeroTier makes
both PCs appear to be on the same one, which is what allows this to work
over the internet. Both players do this.

1. Install ZeroTier One:  https://www.zerotier.com/download/
   Leave the service running.

2. Join the network. Open PowerShell and run:

     & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" join <NETWORK_ID>

3. The network is private, so whoever created it must authorise you.
   Send them the output of these two commands:

     & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" info
     & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks

   Once authorised, the network gives you an address like 10.147.20.x

4. Confirm it worked:

     & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks

   It must show  OK  and a 10.x.x.x address.

5. Send your address to the other player. Each of you pings the other:

     ping <the other player's address>

   Four replies means you are ready.


------------------------------------------------------------------------
STEP 4 - Play
------------------------------------------------------------------------
1. Both players open the game THROUGH STEAM.

2. One player hosts the world.

3. The other opens the multiplayer menu and finds it in the lobby list.

   The host must be in the MULTIPLAYER menu, not the main menu. The
   emulator only starts announcing once you are in multiplayer, so an
   empty list while the host sits in the main menu is normal.

4. The first time, Windows asks whether Dimraeth may access the network.
   Click ALLOW and tick "Private networks". Without that, multiplayer
   cannot connect.

5. >>> HOW TO CONFIRM IT WORKED <<<
   Once you are in, look at the PARTY panel and check that both names are
   in the member list. Seeing the lobby in the list is not enough on its
   own - appearing in the party is the real confirmation.


------------------------------------------------------------------------
IF THE LOBBY LIST IS EMPTY
------------------------------------------------------------------------
FALLBACK - tell the emulator where the other player is.

Open this file:

    Dimraeth_Data\Plugins\x86_64\steam_settings\custom_broadcasts.txt

and put the OTHER player's ZeroTier address in it, one line, no "#":

    10.147.20.42

Save it, close and reopen the game.
The other player does the same with your address.

This file is sent as unicast, so it works even on networks that do not
carry broadcast traffic.


------------------------------------------------------------------------
OTHER ISSUES
------------------------------------------------------------------------
* Antivirus complaining about steam_api64.dll
  The emulator (Goldberg, open source) is unsigned, so some scanners
  object. Add the game folder to your exclusions.

* "Cannot create lobby" / stuck loading
  Close both games, wait about a minute and reopen. The discovery port
  stays busy for a while after the game exits.

* Lobby list still empty
  Check that force_listen_port.txt says 47584 on BOTH machines.

* I want the game back to normal
  Steam -> right-click Dimraeth -> Properties ->
  Installed Files -> Verify integrity of game files.
  Steam restores the original steam_api64.dll. No backup needed.


------------------------------------------------------------------------
DETAILS
------------------------------------------------------------------------
- Emulator: Goldberg Steam Emulator (open source, LGPLv3)
- AppID: 480 (Spacewar) - just a label the emulators match on
- Port: UDP + TCP 47584  (must be the same on both machines)
- Your SteamID is generated automatically and is unique. Nothing to set up.
  Never copy a SteamID from one machine to another: the emulator matches
  players by SteamID, so two machines sharing one identity cannot connect.
- Emulator saves: %APPDATA%\Goldberg SteamEmu Saves\
  Your normal game saves are not affected.

Steam will show "Dimraeth - Running" as usual. That is expected: the
Spacewar AppID only exists inside the emulator, the Steam client never
sees it.

In one sentence: the emulator plays the part of Steam, and ZeroTier makes
the two PCs see each other as if they were on the same network cable.

========================================================================
