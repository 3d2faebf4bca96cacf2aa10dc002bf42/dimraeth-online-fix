using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;

// Minimal decoder for the Goldberg Steam emulator's announce protocol.
//
// The emulator broadcasts a protobuf Common_Message containing an Announce
// message (see dll/net.proto upstream):
//
//   Common_Message { uint64 source_id = 1;  Announce announce = 3; }
//   Announce       { Types type = 1;  repeated uint64 ids = 2;
//                    uint32 tcp_port = 3;  repeated Other_Peers peers = 4;
//                    uint32 appid = 5; }
//
// PROTO3 TRAP: Announce.Types has PING = 0, which is the proto3 default, so a
// PING packet carries NO field 1 at all. Any decoder that initialises
// "type = something-not-zero" and only accepts 0/1 will silently discard every
// PING. That is why the type field is defaulted to 0 here.
//
// This is kept as a shared helper so the diagnostics script can call it via
// Add-Type and decode announce packets without taking the game's port.
public static class CapSpecific
{
    static ulong ReadVarint(byte[] d, ref int i)
    {
        ulong r = 0; int s = 0;
        while (i < d.Length)
        {
            byte b = d[i++];
            r |= (ulong)(b & 0x7F) << s;
            if ((b & 0x80) == 0) break;
            s += 7;
            if (s > 63) break;
        }
        return r;
    }

    // Binds several specific local addresses on the given ports and decodes any
    // Goldberg announce packets it sees.
    //
    // Binding SPECIFIC addresses (127.0.0.1, 10.x.x.x) works even while the game
    // holds 0.0.0.0:47584, because Windows allows a more specific bind on the
    // same port. The emulator broadcasts to every interface, so those sockets
    // receive a copy - no need to steal the game's port.
    public static string Run(int[] ports, string[] addresses, int seconds)
    {
        var report = new StringBuilder();
        var sockets = new List<Socket>();
        var label = new Dictionary<Socket, string>();

        foreach (int p in ports)
        {
            foreach (string a in addresses)
            {
                try
                {
                    var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                    s.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                    s.Bind(new IPEndPoint(IPAddress.Parse(a), p));
                    sockets.Add(s);
                    label[s] = a + ":" + p;
                }
                catch { }
            }
        }
        if (sockets.Count == 0) return "  could not bind any address\n";
        report.AppendLine("  listening on " + sockets.Count + " sockets (specific addresses; the game keeps its own port)");

        var senders   = new Dictionary<string, int>();
        var appIds    = new HashSet<uint>();
        var steamIds  = new HashSet<ulong>();
        var realSteamIds = new HashSet<ulong>();
        var tcpPorts  = new HashSet<int>();
        int announce = 0, datagrams = 0;
        var buf = new byte[65535];
        var start = DateTime.UtcNow;

        while ((DateTime.UtcNow - start).TotalSeconds < seconds)
        {
            List<Socket> ready;
            try { ready = new List<Socket>(sockets); Socket.Select(ready, null, null, 400000); }
            catch { break; }

            foreach (var s in ready)
            {
                try
                {
                    EndPoint ep = new IPEndPoint(IPAddress.Any, 0);
                    int n = s.ReceiveFrom(buf, ref ep);
                    datagrams++;
                    var d = new byte[n];
                    Array.Copy(buf, d, n);
                    if (n < 10 || d[0] != 0x08) continue;

                    int i = 0;
                    ulong sourceId = 0;
                    bool isAnnounce = false;
                    ulong type = 0;          // proto3 default is PING(0) - see note above
                    uint appId = 0, tcpPort = 0;
                    int peers = 0;
                    var realIds = new List<ulong>();

                    while (i < d.Length)
                    {
                        ulong key;
                        try { key = ReadVarint(d, ref i); } catch { break; }
                        int field = (int)(key >> 3), wire = (int)(key & 7);

                        if (wire == 0)
                        {
                            ulong v = ReadVarint(d, ref i);
                            if (field == 1) sourceId = v;
                        }
                        else if (wire == 2)
                        {
                            ulong len64 = ReadVarint(d, ref i);
                            int len = (int)len64;
                            if (i + len > d.Length) break;
                            var sub = new byte[len];
                            Array.Copy(d, i, sub, 0, len);
                            i += len;

                            if (field == 3)     // Announce
                            {
                                isAnnounce = true;
                                int j = 0;
                                while (j < sub.Length)
                                {
                                    ulong k2 = ReadVarint(sub, ref j);
                                    int f2 = (int)(k2 >> 3), w2 = (int)(k2 & 7);
                                    if (w2 == 0)
                                    {
                                        ulong v = ReadVarint(sub, ref j);
                                        if (f2 == 1) type = v;
                                        else if (f2 == 3) tcpPort = (uint)v;
                                        else if (f2 == 5) appId = (uint)v;
                                    }
                                    else if (w2 == 2)
                                    {
                                        ulong l2 = ReadVarint(sub, ref j);
                                        if (f2 == 4) peers++;
                                        else if (f2 == 2)
                                        {
                                            // Announce.ids is a raw run of varints with no
                                            // per-entry tag. It carries the internal key and the
                                            // sender's real SteamID64, so decode each entry.
                                            int end = j + (int)l2;
                                            if (end > sub.Length) end = sub.Length;
                                            while (j < end)
                                            {
                                                ulong idv = ReadVarint(sub, ref j);
                                                if (LooksLikeSteamId(idv)) realIds.Add(idv);
                                            }
                                            continue;
                                        }
                                        j += (int)l2;
                                    }
                                    else break;
                                }
                            }
                        }
                        else if (wire == 5) i += 4;
                        else if (wire == 1) i += 8;
                        else break;
                    }

                    if (!isAnnounce) continue;

                    announce++;
                    var from = (IPEndPoint)ep;
                    string who = from.Address + ":" + from.Port;
                    senders[who] = senders.ContainsKey(who) ? senders[who] + 1 : 1;
                    appIds.Add(appId);
                    steamIds.Add(sourceId);
                    for (int r = 0; r < realIds.Count; r++) realSteamIds.Add(realIds[r]);
                    tcpPorts.Add((int)tcpPort);

                    if (announce <= 8)
                    {
                        report.AppendLine(string.Format(
                            "  [{0,2}] {1,-4} from {2,-21} appid={3,-4} tcp_port={4,-5} key={5} peers={6}   (heard on {7})",
                            announce, (type == 0 ? "PING" : "PONG"), who, appId, tcpPort, sourceId, peers, label[s]));
                        if (realIds.Count > 0)
                            report.AppendLine("        real steamid = " + realIds[realIds.Count - 1]);
                    }
                }
                catch (SocketException) { }
                catch (ObjectDisposedException) { }
            }
        }

        foreach (var s in sockets) { try { s.Close(); } catch { } }

        report.AppendLine("");
        report.AppendLine("  datagrams received    : " + datagrams);
        report.AppendLine("  goldberg announces    : " + announce);
        report.AppendLine("  senders               : " + senders.Count +
                          (senders.Count > 0 ? "  [" + string.Join(", ", new List<string>(senders.Keys).ToArray()) + "]" : ""));
        report.AppendLine("  appids                : " + (appIds.Count == 0 ? "(none)" : string.Join(",", ToStrings(appIds))));
        report.AppendLine("  real SteamIDs heard   : " + (realSteamIds.Count == 0 ? "(none)" : string.Join(",", ToStrings(realSteamIds))));
        report.AppendLine("  internal keys (source_id - NOT SteamIDs): " + (steamIds.Count == 0 ? "(none)" : string.Join(",", ToStrings(steamIds))));
        report.AppendLine("  tcp_port advertised   : " + (tcpPorts.Count == 0 ? "(none)" : string.Join(",", ToStrings(tcpPorts))));
        report.AppendLine("");
        if (announce > 0) report.AppendLine("  >>> the emulator IS announcing (appid " + string.Join(",", ToStrings(appIds)) + ")");
        else report.AppendLine("  >>> no announce seen: enter the game's MULTIPLAYER menu (create or browse a lobby).");
        return report.ToString();
    }

    // A real SteamID64 for an individual account has the shape 0x0110 0001 xxxxxxxx:
    // universe 1 (public), account type 1 (individual), instance 1. Goldberg's
    // internal connection keys use the 0x0130 0001 prefix, so this separates them.
    static bool LooksLikeSteamId(ulong v)
    {
        uint universe = (uint)((v >> 56) & 0xFF);
        uint type = (uint)((v >> 52) & 0x0F);
        uint instance = (uint)((v >> 32) & 0xFFFFF);
        return universe == 1 && type == 1 && instance == 1;
    }

    static string[] ToStrings<T>(HashSet<T> set)
    {
        var list = new List<string>();
        foreach (var v in set) list.Add(v.ToString());
        return list.ToArray();
    }
}
