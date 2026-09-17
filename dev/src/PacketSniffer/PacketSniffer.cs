using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

// Standalone Goldberg announce-packet sniffer.
//
// Decodes the emulator's peer-discovery broadcasts so you can see whether a peer
// is announcing, on which interface, with which AppID, and how many peers it has
// learned about.
//
// PORT CAVEAT
//   The game binds 0.0.0.0:47584. On Windows a wildcard bind blocks a later
//   wildcard bind on the same port, so this tool cannot take 47584 while the
//   game holds it. It therefore binds SPECIFIC addresses (127.0.0.1, each local
//   IPv4) on the same ports - Windows allows that, and since the emulator
//   broadcasts to every interface these sockets receive a copy of the packets.
//
// USAGE
//   PacketSniffer [--seconds N] [--ports 47584,47585] [--log FILE] [--listen-only]
//
// SCOPE: this is a packet-level diagnostic. It proves the emulator is announcing
// and who it is announcing as. It does not prove a game session works.
public static class PacketSniffer
{
    static StringBuilder report;
    static void W(string s) { report.AppendLine(s); Console.WriteLine(s); }

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

    public static int Main(string[] argv)
    {
        int seconds = 30;
        string outFile = null;
        bool listenOnly = false;
        bool showHex = false;
        var ports = new List<int>();

        for (int i = 0; i < argv.Length; i++)
        {
            if (argv[i] == "--seconds" && i + 1 < argv.Length) seconds = int.Parse(argv[++i]);
            else if (argv[i] == "--log" && i + 1 < argv.Length) outFile = argv[++i];
            else if (argv[i] == "--hex") showHex = true;
            else if (argv[i] == "--listen-only") listenOnly = true;
            else if (argv[i] == "--ports" && i + 1 < argv.Length)
            {
                string[] parts = argv[++i].Split(',');
                for (int k = 0; k < parts.Length; k++)
                {
                    int p;
                    if (int.TryParse(parts[k].Trim(), out p)) ports.Add(p);
                }
            }
        }
        if (ports.Count == 0) { ports.Add(47584); ports.Add(47585); }

        report = new StringBuilder();
        // W is a static helper (C# 5 has no local functions)

        W("=========== GOLDBERG ANNOUNCE SNIFFER ===========");
        W("time    = " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        W("seconds = " + seconds);
        if (listenOnly) W("mode    = listen only (not sending anything)");

        // collect the addresses to bind
        var addresses = new List<string>();
        addresses.Add("127.0.0.1");
        addresses.Add("127.0.0.2");
        try
        {
            var locals = Dns.GetHostAddresses(Dns.GetHostName());
            for (int i = 0; i < locals.Length; i++)
            {
                if (locals[i].AddressFamily == AddressFamily.InterNetwork)
                {
                    string a = locals[i].ToString();
                    if (a != "127.0.0.1" && !addresses.Contains(a)) addresses.Add(a);
                }
            }
        }
        catch { }

        var sockets = new List<Socket>();
        var label = new Dictionary<Socket, string>();
        for (int pi = 0; pi < ports.Count; pi++)
        {
            for (int ai = 0; ai < addresses.Count; ai++)
            {
                try
                {
                    var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                    s.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                    s.Bind(new IPEndPoint(IPAddress.Parse(addresses[ai]), ports[pi]));
                    sockets.Add(s);
                    label[s] = addresses[ai] + ":" + ports[pi];
                }
                catch { }
            }
        }

        if (sockets.Count == 0) { W("could not bind any socket - is the port range in use?"); Save(outFile, report); return 1; }
        W("bound   = " + sockets.Count + " sockets on ports " + string.Join(",", PortStrings(ports)));

        // a transmitter that announces us as a peer, so the emulator answers with PONG
        Socket tx = null;
        int txPort = 0;
        if (!listenOnly)
        {
            try
            {
                tx = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                tx.Bind(new IPEndPoint(IPAddress.Any, 0));
                txPort = ((IPEndPoint)tx.LocalEndPoint).Port;
                W("probe   = announcing as a peer on ephemeral port " + txPort);
            }
            catch { }
        }

        W("");
        var senders = new Dictionary<string, int>();
        var appIds = new HashSet<uint>();
        var steamIds = new HashSet<ulong>();
        var realSteamIds = new HashSet<ulong>();
        var idBySender = new Dictionary<string, ulong>();
        int announce = 0, datagrams = 0;
        var buf = new byte[65535];
        var start = DateTime.UtcNow;
        var lastPing = DateTime.UtcNow;

        while ((DateTime.UtcNow - start).TotalSeconds < seconds)
        {
            if (tx != null && (DateTime.UtcNow - lastPing).TotalSeconds > 3)
            {
                for (int pi = 0; pi < ports.Count; pi++)
                {
                    try { tx.SendTo(BuildPing(0x0110000100000001UL, 480, txPort), new IPEndPoint(IPAddress.Loopback, ports[pi])); }
                    catch { }
                }
                lastPing = DateTime.UtcNow;
            }

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
                    ulong type = 0;   // proto3 default = PING(0)
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

                            if (field == 3)
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
                                            // Announce.ids is a raw run of varints, with no
                                            // per-entry tag. It carries the internal key and the
                                            // sender's real SteamID64, so decode each one.
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
                    if (sourceId == 0x0110000100000001UL) continue;   // our own probe

                    announce++;
                    var from = (IPEndPoint)ep;
                    string who = from.Address + ":" + from.Port;
                    senders[who] = senders.ContainsKey(who) ? senders[who] + 1 : 1;
                    appIds.Add(appId);
                    steamIds.Add(sourceId);
                    for (int r = 0; r < realIds.Count; r++) realSteamIds.Add(realIds[r]);
                    if (realIds.Count > 0) idBySender[who] = realIds[realIds.Count - 1];

                    if (announce <= 12)
                    {
                        W(string.Format("  [{0,2}] {1,-4} from {2,-21} appid={3,-4} tcp_port={4,-5} key={5} peers={6}",
                            announce, (type == 0 ? "PING" : "PONG"), who, appId, tcpPort, sourceId, peers));
                        W("        real steamid = " + (realIds.Count == 0 ? "(none in this packet)" : JoinList(realIds)));
                        if (showHex) DumpProto(d);
                    }
                }
                catch (SocketException) { }
                catch (ObjectDisposedException) { }
            }
        }

        foreach (var s in sockets) { try { s.Close(); } catch { } }
        if (tx != null) { try { tx.Close(); } catch { } }

        W("");
        W("=========== RESULT ===========");
        W("  datagrams received : " + datagrams);
        W("  announces decoded  : " + announce);
        W("  senders            : " + senders.Count +
          (senders.Count > 0 ? "  [" + string.Join(", ", new List<string>(senders.Keys).ToArray()) + "]" : ""));
        W("  appids             : " + (appIds.Count == 0 ? "(none)" : Join(appIds)));
        W("");
        W("  real SteamIDs heard (from Announce.ids - these are the ones to compare");
        W("  against %APPDATA%\\Goldberg SteamEmu Saves\\settings\\user_steam_id.txt):");
        if (realSteamIds.Count == 0) W("    (none)");
        else
        {
            foreach (var who in idBySender.Keys)
                W("    " + idBySender[who] + "   from " + who);
        }
        W("");
        W("  internal connection keys (source_id - NOT SteamIDs, do not compare");
        W("  them with any settings file):");
        W("    " + (steamIds.Count == 0 ? "(none)" : Join(steamIds)));
        W("");
        if (announce > 0) W("  >>> emulator is announcing (appid " + Join(appIds) + ")");
        else W("  >>> nothing heard. The emulator only announces once you enter multiplayer.");
        Save(outFile, report);
        return announce > 0 ? 0 : 10;
    }

    // Diagnostic: prints every top-level protobuf field with the bytes exactly as
    // they arrived, so the wire encoding can be compared against the values the
    // emulator stores on disk (settings\user_steam_id.txt).
    static void DumpProto(byte[] d)
    {
        int i = 0;
        while (i < d.Length)
        {
            int tagStart = i;
            ulong key;
            try { key = ReadVarint(d, ref i); } catch { break; }
            int field = (int)(key >> 3), wire = (int)(key & 7);
            int tagLen = i - tagStart;

            if (wire == 0)
            {
                int valStart = i;
                ulong v;
                try { v = ReadVarint(d, ref i); } catch { break; }
                W(string.Format("        . raw field {0} varint: tag={1} bytes={2} value={3}",
                    field, Hex(d, tagStart, tagLen), Hex(d, valStart, i - valStart), v));
            }
            else if (wire == 2)
            {
                int lenStart = i;
                ulong len64;
                try { len64 = ReadVarint(d, ref i); } catch { break; }
                int len = (int)len64;
                if (i + len > d.Length) break;
                W(string.Format("        . raw field {0} length: tag={1} lenbytes={2} len={3}",
                    field, Hex(d, tagStart, tagLen), Hex(d, lenStart, i - lenStart), len));
                var sub = new byte[len];
                Array.Copy(d, i, sub, 0, len);
                DumpProtoAt(sub, "            ");
                i += len;
            }
            else if (wire == 5) { W("        . raw field " + field + " fixed32"); i += 4; }
            else if (wire == 1) { W("        . raw field " + field + " fixed64"); i += 8; }
            else { W("        . unknown wire type " + wire + " at byte " + tagStart); break; }
        }
    }

    static void DumpProtoAt(byte[] d, string indent)
    {
        int i = 0;
        while (i < d.Length)
        {
            int tagStart = i;
            ulong key;
            try { key = ReadVarint(d, ref i); } catch { break; }
            int field = (int)(key >> 3), wire = (int)(key & 7);
            if (wire == 0)
            {
                int valStart = i;
                ulong v;
                try { v = ReadVarint(d, ref i); } catch { break; }
                W(string.Format("{0}. field {1} varint bytes={2} value={3} (0x{4:X16})",
                    indent, field, Hex(d, valStart, i - valStart), v, v));
            }
            else if (wire == 2)
            {
                ulong len64;
                try { len64 = ReadVarint(d, ref i); } catch { break; }
                int len = (int)len64;
                if (i + len > d.Length) break;
                W(string.Format("{0}. field {1} bytes[{2}] = {3}", indent, field, len, Hex(d, i, len)));
                i += len;
            }
            else if (wire == 5) i += 4;
            else if (wire == 1) i += 8;
            else break;
        }
    }

    static string Hex(byte[] d, int start, int count)
    {
        var sb = new StringBuilder();
        for (int k = 0; k < count; k++)
        {
            if (k > 0) sb.Append(' ');
            sb.Append(d[start + k].ToString("X2"));
        }
        return sb.ToString();
    }

    // A real SteamID64 for an individual account has the shape 0x0110 0001 xxxxxxxx:
    // universe = 1 (public), account type = 1 (individual), instance = 1.
    // Goldberg's internal connection keys use 0x0130 0001..., so this separates them.
    static bool LooksLikeSteamId(ulong v)
    {
        uint universe = (uint)((v >> 56) & 0xFF);
        uint type = (uint)((v >> 52) & 0x0F);
        uint instance = (uint)((v >> 32) & 0xFFFFF);
        return universe == 1 && type == 1 && instance == 1;
    }

    static string JoinList(List<ulong> v)
    {
        var a = new List<string>();
        for (int i = 0; i < v.Count; i++) a.Add(v[i].ToString());
        return string.Join(",", a.ToArray());
    }

    static byte[] BuildPing(ulong id, uint appid, int tcpPort)
    {
        var ann = new List<byte>();
        AddVarintField(ann, 1, 0);                 // type = PING
        AddVarintField(ann, 2, id);                // ids
        AddVarintField(ann, 3, (ulong)tcpPort);    // tcp_port
        AddVarintField(ann, 5, appid);             // appid

        var cm = new List<byte>();
        AddVarintField(cm, 1, id);                 // source_id
        AddLengthField(cm, 3, ann.ToArray());      // announce
        return cm.ToArray();
    }

    static void AddVarintField(List<byte> buf, int field, ulong value)
    {
        WriteVarint(buf, (ulong)((field << 3) | 0));
        WriteVarint(buf, value);
    }

    static void AddLengthField(List<byte> buf, int field, byte[] data)
    {
        WriteVarint(buf, (ulong)((field << 3) | 2));
        WriteVarint(buf, (ulong)data.Length);
        buf.AddRange(data);
    }

    static void WriteVarint(List<byte> buf, ulong v)
    {
        do
        {
            byte b = (byte)(v & 0x7F);
            v >>= 7;
            if (v != 0) b |= 0x80;
            buf.Add(b);
        } while (v != 0);
    }

    static string[] PortStrings(List<int> ports)
    {
        var a = new List<string>();
        for (int i = 0; i < ports.Count; i++) a.Add(ports[i].ToString());
        return a.ToArray();
    }

    static string Join<T>(HashSet<T> set)
    {
        var a = new List<string>();
        foreach (var v in set) a.Add(v.ToString());
        return string.Join(",", a.ToArray());
    }

    static void Save(string path, StringBuilder rep)
    {
        if (path == null) return;
        try { File.WriteAllText(path, rep.ToString()); Console.WriteLine("log written to " + path); } catch { }
    }
}


