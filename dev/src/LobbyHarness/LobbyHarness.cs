using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Lobby harness for the Goldberg Steam emulator.
//
// Drives the emulator's lobby API directly, without the game, so lobby
// propagation between two independent emulator instances can be verified.
//
// Modes:
//   --host [maxMembers]  Create a public lobby and keep it alive.
//   --join <lobbyId>     Join a specific lobby and report the member count.
//   --joinauto           Poll RequestLobbyList until a lobby appears, then join it.
//   --list               (default) Poll RequestLobbyList and print what is visible.
//
// Common: --seconds N   --tag NAME   --log FILE   --dll PATH
//
// SCOPE: this covers the matchmaking layer. It does not exercise the P2P data
// channel or Netcode, so it does not prove a player spawns in the game's party.
//
// Compiled with the classic .NET Framework csc.exe - no local functions, no
// tuples, no newer syntax.
public static class LobbyHarness
{
    static StringBuilder log = new StringBuilder();
    static string logFile = null;
    static bool echo = true;

    static void L(string s) { log.AppendLine(s); if (echo) Console.WriteLine(s); }
    static void E(string s) { log.AppendLine(s); Console.WriteLine(s); }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern IntPtr LoadLibraryA(string path);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr h, string n);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte f_Init();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void f_Void();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr f_GetIface();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint f_U32(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_U64(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int f_I32(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_LI(IntPtr self, int i);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_LL(IntPtr self, ulong lobby);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_Create(IntPtr self, int type, int maxMembers);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte f_SetData(IntPtr self, ulong lobby, string key, string val);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte f_Data(IntPtr self, ulong lobby, int i, byte[] key, int klen, byte[] val, int vlen);

    static IntPtr Lib;
    static T Get<T>(string name) where T : class
    {
        IntPtr p = GetProcAddress(Lib, name);
        if (p == IntPtr.Zero) throw new Exception("missing export: " + name);
        return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
    }

    // lobby member enumeration
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong f_Member(IntPtr self, ulong lobby, int i);

    public static int Main(string[] argv)
    {
        string dir = null, mode = "list", tag = "HARNESS";
        ulong joinTarget = 0;
        int seconds = 60, maxMembers = 8, intervalMs = 3000;

        for (int i = 0; i < argv.Length; i++)
        {
            if (argv[i] == "--dir" && i + 1 < argv.Length) dir = argv[++i];
            else if (argv[i] == "--host") { mode = "host"; if (i + 1 < argv.Length && !argv[i + 1].StartsWith("--")) maxMembers = int.Parse(argv[++i]); }
            else if (argv[i] == "--join" && i + 1 < argv.Length) { mode = "join"; joinTarget = ulong.Parse(argv[++i]); }
            else if (argv[i] == "--joinauto") mode = "joinauto";
            else if (argv[i] == "--list") mode = "list";
            else if (argv[i] == "--seconds" && i + 1 < argv.Length) seconds = int.Parse(argv[++i]);
            else if (argv[i] == "--tag" && i + 1 < argv.Length) tag = argv[++i];
            else if (argv[i] == "--interval" && i + 1 < argv.Length) intervalMs = int.Parse(argv[++i]);
            else if (argv[i] == "--log" && i + 1 < argv.Length) logFile = argv[++i];
            else if (argv[i] == "--quiet") echo = false;
        }
        if (dir == null) dir = Directory.GetCurrentDirectory();
        Directory.SetCurrentDirectory(dir);

        L("=========== LOBBY HARNESS ===========");
        L("tag   = " + tag);
        L("mode  = " + mode);
        L("dir   = " + dir);
        L("time  = " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));

        string dll = Path.Combine(dir, "steam_api64.dll");
        Lib = LoadLibraryA(dll);
        if (Lib == IntPtr.Zero) { E("failed to load " + dll); Save(); return 2; }

        f_Init init = Get<f_Init>("SteamAPI_Init");
        byte ok = 0;
        try { ok = init(); } catch (Exception e) { E("init threw: " + e.Message); Save(); return 3; }
        if (ok == 0)
        {
            L("init returned FALSE, retrying with env AppID 480...");
            Environment.SetEnvironmentVariable("SteamAppId", "480");
            Environment.SetEnvironmentVariable("SteamGameId", "480");
            try { ok = init(); } catch { }
        }
        L("SteamAPI_Init() -> " + ok);
        if (ok == 0) { E("INIT FAILED"); Save(); return 3; }

        f_Void    runCb     = Get<f_Void>("SteamAPI_RunCallbacks");
        f_GetIface mmGet    = Get<f_GetIface>("SteamAPI_SteamMatchmaking_v009");
        f_GetIface userGet  = Get<f_GetIface>("SteamAPI_SteamUser_v023");
        f_GetIface utilGet  = Get<f_GetIface>("SteamAPI_SteamUtils_v010");
        IntPtr mm = mmGet(), user = userGet(), util = utilGet();

        f_U32     getAppId  = Get<f_U32>("SteamAPI_ISteamUtils_GetAppID");
        f_U64     getSid    = Get<f_U64>("SteamAPI_ISteamUser_GetSteamID");
        f_U64     reqList   = Get<f_U64>("SteamAPI_ISteamMatchmaking_RequestLobbyList");
        f_LI      byIndex   = Get<f_LI>("SteamAPI_ISteamMatchmaking_GetLobbyByIndex");
        f_LL      numMem    = Get<f_LL>("SteamAPI_ISteamMatchmaking_GetNumLobbyMembers");
        f_LL      joinLb    = Get<f_LL>("SteamAPI_ISteamMatchmaking_JoinLobby");
        f_LL      ownerLb   = Get<f_LL>("SteamAPI_ISteamMatchmaking_GetLobbyOwner");
        f_Create  createLb  = Get<f_Create>("SteamAPI_ISteamMatchmaking_CreateLobby");
        f_SetData setData   = Get<f_SetData>("SteamAPI_ISteamMatchmaking_SetLobbyData");
        f_Member  memberAt  = Get<f_Member>("SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex");

        int appId = (int)getAppId(util);
        ulong mySid = getSid(user);
        L("AppID   = " + appId);
        L("SteamID = " + mySid);
        L("");

        // ---------------------------------------------------------- host
        if (mode == "host")
        {
            // k_ELobbyTypePublic = 2
            ulong lobby = 0;
            try { lobby = createLb(mm, 2, maxMembers); }
            catch (Exception e) { E("CreateLobby threw: " + e.Message); Save(); return 4; }
            L("CreateLobby(public, " + maxMembers + ") requested");

            DateTime lim = DateTime.Now.AddSeconds(seconds);
            while (lobby == 0 && DateTime.Now < lim)
            {
                runCb();
                Thread.Sleep(100);
            }

            // the emulator answers asynchronously; poll the lobby list for our own lobby
            for (int k = 0; k < 30 && lobby == 0; k++)
            {
                runCb();
                try { reqList(mm); } catch { }
                for (int k2 = 0; k2 < 10; k2++) { runCb(); Thread.Sleep(40); }
                for (int i = 0; i < 20; i++)
                {
                    ulong lb = 0;
                    try { lb = byIndex(mm, i); } catch { break; }
                    if (lb == 0) break;
                    ulong ow = 0;
                    try { ow = ownerLb(mm, lb); } catch { }
                    if (ow == mySid) { lobby = lb; break; }
                }
                if (lobby == 0) Thread.Sleep(500);
            }

            if (lobby == 0) { E("could not resolve our own lobby id"); Save(); return 5; }

            L("HOSTING lobby " + lobby + " as owner " + mySid);
            try { setData(mm, lobby, "HOST_TAG", tag); } catch { }
            try { setData(mm, lobby, "HOST_STEAMID", mySid.ToString()); } catch { }
            E("HOST_LOBBY id=" + lobby + " owner=" + mySid);

            lim = DateTime.Now.AddSeconds(seconds);
            while (DateTime.Now < lim)
            {
                runCb();
                int n = 0;
                try { n = (int)numMem(mm, lobby); } catch { }
                if (n >= 2)
                {
                    E("HOST_SEES_MEMBERS=" + n + " (a client joined)");
                    for (int i = 0; i < n; i++)
                    {
                        ulong mid = 0;
                        try { mid = memberAt(mm, lobby, i); } catch { }
                        L("   member[" + i + "] = " + mid);
                    }
                    break;
                }
                Thread.Sleep(200);
            }
            Save(); return 0;
        }

        // ---------------------------------------------------------- list / joinauto / join
        ulong found = 0;
        int attempt = 0;
        DateTime deadline = DateTime.Now.AddSeconds(seconds);

        while (DateTime.Now < deadline && found == 0)
        {
            attempt++;
            try { reqList(mm); } catch { }
            for (int k = 0; k < 12; k++) { runCb(); Thread.Sleep(40); }

            for (int i = 0; i < 20; i++)
            {
                ulong lb = 0;
                try { lb = byIndex(mm, i); } catch { break; }
                if (lb == 0) break;
                int n = 0;   try { n = (int)numMem(mm, lb); } catch { }
                ulong ow = 0; try { ow = ownerLb(mm, lb); } catch { }
                E("FOUND lobby=" + lb + " owner=" + ow + " members=" + n);
                found = lb;
                break;
            }
            if (found == 0)
            {
                if ((attempt % 4) == 0) L("  attempt " + attempt + ": no lobby yet");
                Thread.Sleep(intervalMs);
            }
        }

        if (found == 0) { E("NO_LOBBY_FOUND"); Save(); return 10; }

        if (mode == "list") { L("listing only - not joining"); Save(); return 0; }

        L("joining lobby " + found);
        try { joinLb(mm, found); } catch (Exception e) { E("JoinLobby threw: " + e.Message); }

        int after = 0;
        for (int k = 0; k < 80; k++)
        {
            runCb();
            Thread.Sleep(100);
            try { after = (int)numMem(mm, found); } catch { }
            if (after >= 2) break;
        }
        E("JOINED lobby=" + found + " members=" + after + " self=" + mySid);
        Save();
        return after >= 2 ? 0 : 11;
    }

    static void Save() { if (logFile != null) { try { File.WriteAllText(logFile, log.ToString()); } catch { } } }
}
