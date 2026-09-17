using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Lobby discovery / join test for the Goldberg Steam emulator.
//
// Loads the same steam_api64.dll the game uses, with its own SteamID, and runs
// the real client flow:
//
//     RequestLobbyList() -> GetLobbyByIndex() -> JoinLobby() -> GetNumLobbyMembers()
//
// SCOPE - WHAT THIS PROVES AND WHAT IT DOES NOT
//
//   Proves: the lobby is discoverable on the network and accepts a join request.
//   Does NOT prove: that a player appears in the in-game party list. That needs
//   the P2P data channel (ConnectP2P) plus Unity Netcode approval, which this
//   tool does not exercise. Confirming party membership requires a real second
//   player.
//
// Compiled with the classic .NET Framework csc.exe, so this file deliberately
// avoids local functions, tuples and other newer C# syntax.
public static class JoinTest
{
    static StringBuilder log = new StringBuilder();
    static string logFile = null;
    static void L(string s) { Console.WriteLine(s); log.AppendLine(s); }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern IntPtr LoadLibraryA(string path);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr h, string n);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte f_Init();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void f_Void();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr f_GetIface();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint f_U32(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_U64(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_LI(IntPtr self, int i);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_LL(IntPtr self, ulong lobby);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte f_Data(IntPtr self, ulong lobby, int i, byte[] key, int klen, byte[] val, int vlen);

    static IntPtr Lib;
    static T Get<T>(string name) where T : class
    {
        IntPtr p = GetProcAddress(Lib, name);
        if (p == IntPtr.Zero) throw new Exception("missing export: " + name);
        return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
    }

    public static int Main(string[] argv)
    {
        string dir = null;
        int seconds = 60, pollMs = 3000;

        for (int i = 0; i < argv.Length; i++)
        {
            if (argv[i] == "--dir" && i + 1 < argv.Length) dir = argv[++i];
            else if (argv[i] == "--seconds" && i + 1 < argv.Length) seconds = int.Parse(argv[++i]);
            else if (argv[i] == "--poll" && i + 1 < argv.Length) pollMs = int.Parse(argv[++i]);
            else if (argv[i] == "--log" && i + 1 < argv.Length) logFile = argv[++i];
        }
        if (dir == null) dir = Directory.GetCurrentDirectory();
        Directory.SetCurrentDirectory(dir);

        L("=========== LOBBY DISCOVERY TEST ===========");
        L("NOTE: matchmaking layer only - does NOT prove party membership.");
        L("dir  = " + dir);
        L("time = " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));

        string dll = Path.Combine(dir, "steam_api64.dll");
        L("dll  = " + dll + "  exists=" + File.Exists(dll));
        string[] cfgs = new string[] { "steam_appid.txt", Path.Combine("steam_settings", "steam_appid.txt") };
        for (int i = 0; i < cfgs.Length; i++)
        {
            string f = cfgs[i];
            string v = File.Exists(f) ? "'" + File.ReadAllText(f).Trim() + "'" : "(absent)";
            L("  cfg " + f.PadRight(30) + " = " + v);
        }
        L("  env SteamAppId=" + (Environment.GetEnvironmentVariable("SteamAppId") == null
            ? "<null>" : Environment.GetEnvironmentVariable("SteamAppId")));

        Lib = LoadLibraryA(dll);
        if (Lib == IntPtr.Zero) { L("failed to load the DLL"); Save(); return 2; }

        f_Init init = Get<f_Init>("SteamAPI_Init");
        byte ok = 0;
        try { ok = init(); } catch (Exception e) { L("SteamAPI_Init threw: " + e.Message); Save(); return 3; }
        if (ok == 0)
        {
            L("SteamAPI_Init returned FALSE; retrying with SteamAppId=480 env vars...");
            Environment.SetEnvironmentVariable("SteamAppId", "480");
            Environment.SetEnvironmentVariable("SteamGameId", "480");
            try { ok = init(); } catch (Exception e) { L("retry threw: " + e.Message); Save(); return 3; }
        }
        L("SteamAPI_Init() -> " + ok);
        if (ok == 0) { L("INIT FAILED"); Save(); return 3; }

        f_Void    runCb    = Get<f_Void>("SteamAPI_RunCallbacks");
        f_GetIface mmGet   = Get<f_GetIface>("SteamAPI_SteamMatchmaking_v009");
        f_GetIface userGet = Get<f_GetIface>("SteamAPI_SteamUser_v023");
        f_GetIface utilGet = Get<f_GetIface>("SteamAPI_SteamUtils_v010");
        IntPtr mm = mmGet(), user = userGet(), util = utilGet();

        f_U32     getAppId = Get<f_U32>("SteamAPI_ISteamUtils_GetAppID");
        f_U64     getSid   = Get<f_U64>("SteamAPI_ISteamUser_GetSteamID");
        f_U64     reqList  = Get<f_U64>("SteamAPI_ISteamMatchmaking_RequestLobbyList");
        f_LI      byIndex  = Get<f_LI>("SteamAPI_ISteamMatchmaking_GetLobbyByIndex");
        f_LL      numMem   = Get<f_LL>("SteamAPI_ISteamMatchmaking_GetNumLobbyMembers");
        f_LL      joinLb   = Get<f_LL>("SteamAPI_ISteamMatchmaking_JoinLobby");
        f_LL      ownerLb  = Get<f_LL>("SteamAPI_ISteamMatchmaking_GetLobbyOwner");
        f_LL      dataCnt  = Get<f_LL>("SteamAPI_ISteamMatchmaking_GetLobbyDataCount");
        f_Data    dataIdx  = Get<f_Data>("SteamAPI_ISteamMatchmaking_GetLobbyDataByIndex");

        L("");
        L("AppID   (ours) : " + getAppId(util));
        ulong mySid = getSid(user);
        L("SteamID (ours) : " + mySid);
        L("");
        L("Searching for lobbies (up to " + seconds + "s, polling every " + pollMs + "ms)");
        L("");

        DateTime deadline = DateTime.Now.AddSeconds(seconds);
        ulong found = 0;
        int attempt = 0;

        while (DateTime.Now < deadline && found == 0)
        {
            attempt++;
            try { reqList(mm); } catch (Exception e) { L("RequestLobbyList threw: " + e.Message); }
            for (int k = 0; k < 12; k++) { runCb(); Thread.Sleep(40); }

            for (int i = 0; i < 20; i++)
            {
                ulong lb = 0;
                try { lb = byIndex(mm, i); } catch { break; }
                if (lb == 0) break;

                int n = 0;   try { n = (int)numMem(mm, lb); } catch { }
                ulong ow = 0; try { ow = ownerLb(mm, lb); } catch { }
                L("[attempt " + attempt + "] LOBBY FOUND  id=" + lb + "  owner=" + ow + "  members=" + n);

                int dc = 0; try { dc = (int)dataCnt(mm, lb); } catch { }
                for (int d = 0; d < dc && d < 8; d++)
                {
                    byte[] kb = new byte[256];
                    byte[] vb = new byte[1024];
                    try
                    {
                        if (dataIdx(mm, lb, d, kb, kb.Length, vb, vb.Length) != 0)
                        {
                            string key = Encoding.UTF8.GetString(kb).TrimEnd('\0');
                            string val = Encoding.UTF8.GetString(vb).TrimEnd('\0');
                            L("              data: " + key + " = " + val);
                        }
                    }
                    catch { }
                }
                found = lb;
                break;
            }
            if (found == 0 && (attempt % 3) == 0) L("[attempt " + attempt + "] no lobby visible yet...");
            if (found == 0) Thread.Sleep(pollMs);
        }

        if (found == 0)
        {
            L("");
            L("RESULT: NO LOBBY FOUND.");
            L("  - make sure the host is actually HOSTING (not just in the menu)");
            L("  - both machines on the same network, same AppID 480");
            Save(); return 10;
        }

        L("");
        L("--- attempting to JOIN lobby " + found + " ---");
        try { joinLb(mm, found); } catch (Exception e) { L("JoinLobby threw: " + e.Message); }

        int before = 0; try { before = (int)numMem(mm, found); } catch { }
        int after = before;
        for (int k = 0; k < 60; k++)
        {
            runCb();
            Thread.Sleep(100);
            int n = 0; try { n = (int)numMem(mm, found); } catch { }
            after = n;
            if (n >= 2) break;
        }
        ulong owner = 0; try { owner = ownerLb(mm, found); } catch { }

        L("");
        L("=========== RESULT ===========");
        L("  lobby          : " + found);
        L("  owner          : " + owner);
        L("  we are owner?  : " + (owner == mySid));
        L("  members        : " + after);
        L("");
        if (after >= 2)
        {
            L("  >>> LOBBY JOIN ACCEPTED. Member count went to " + after + ".");
            L("  >>> This is the matchmaking layer only. It does NOT mean a player");
            L("  >>> spawns in the party - confirm that with a real second player.");
            Save(); return 0;
        }
        L("  >>> Lobby found but the member count did not rise (members=" + after + ").");
        Save(); return 11;
    }

    static void Save() { if (logFile != null) { try { File.WriteAllText(logFile, log.ToString()); } catch { } } }
}
