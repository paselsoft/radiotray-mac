using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace RadioTray
{
    /// <summary>
    /// Il "ripetitore interno": un piccolo server HTTP solo su 127.0.0.1 (non raggiungibile da altri PC) che
    /// consegna al decodificatore di Windows (Media Foundation) l'audio già scaricato attraverso il proxy.
    /// Così il lettore non va mai su Internet da solo e un solo componente conosce il proxy.
    /// </summary>
    internal sealed class LocalRelay : IDisposable
    {
        private sealed class Entry
        {
            public AudioPipe Pipe;
            public string ContentType;
            public Socket Current;   // l'ultima connessione vince: Media Foundation a volte apre due volte
        }

        private readonly TcpListener _listener;
        private readonly Dictionary<string, Entry> _entries = new Dictionary<string, Entry>();
        private readonly object _lock = new object();
        private volatile bool _stopped;

        public int Port { get; }

        public LocalRelay()
        {
            _listener = new TcpListener(IPAddress.Loopback, 0);
            _listener.Start();
            Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            new Thread(AcceptLoop) { IsBackground = true, Name = "RadioTray relay" }.Start();
            Log.Write($"Ripetitore interno su 127.0.0.1:{Port}");
        }

        /// <summary>Pubblica il tubo e restituisce l'indirizzo locale da dare al decodificatore.</summary>
        public string Register(AudioPipe pipe, string extension, string contentType)
        {
            string token = Guid.NewGuid().ToString("N");
            lock (_lock) _entries[token] = new Entry { Pipe = pipe, ContentType = contentType };
            return $"http://127.0.0.1:{Port}/{token}.{extension}";
        }

        public void Unregister(string url)
        {
            string token = TokenFromPath(new Uri(url).AbsolutePath);
            Socket socket = null;
            lock (_lock)
            {
                if (_entries.TryGetValue(token, out var e)) socket = e.Current;
                _entries.Remove(token);
            }
            try { socket?.Close(); } catch (SocketException) { }
        }

        private static string TokenFromPath(string path)
        {
            string t = path.TrimStart('/');
            int dot = t.IndexOf('.');
            return dot >= 0 ? t.Substring(0, dot) : t;
        }

        private void AcceptLoop()
        {
            while (!_stopped)
            {
                Socket client;
                try { client = _listener.AcceptSocket(); }
                catch (SocketException) { if (_stopped) return; continue; }
                catch (Exception) { return; }   // ascolto chiuso
                new Thread(() => Serve(client)) { IsBackground = true, Name = "RadioTray relay client" }.Start();
            }
        }

        private void Serve(Socket client)
        {
            Entry entry = null;
            try
            {
                client.NoDelay = true;
                client.ReceiveTimeout = 10000;
                string request = ReadRequest(client);
                string[] first = request.Split('\n')[0].Trim().Split(' ');
                string method = first.Length > 0 ? first[0] : "";
                string path = first.Length > 1 ? first[1] : "/";
                lock (_lock)
                {
                    if (_entries.TryGetValue(TokenFromPath(path), out entry))
                    {
                        try { entry.Current?.Close(); } catch (SocketException) { }
                        entry.Current = client;
                    }
                }
                if (entry == null)
                {
                    Send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    return;
                }
                Send(client, "HTTP/1.1 200 OK\r\nContent-Type: " + entry.ContentType +
                             "\r\nCache-Control: no-cache\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n");
                if (method == "HEAD") return;
                var buffer = new byte[16384];
                int n;
                while ((n = entry.Pipe.Read(buffer, 0, buffer.Length)) > 0)
                {
                    lock (_lock) if (entry.Current != client) return;   // è arrivata una connessione più nuova
                    client.Send(buffer, 0, n, SocketFlags.None);
                }
            }
            catch (Exception e) when (e is SocketException || e is ObjectDisposedException || e is IOException) { }
            catch (Exception e)
            {
                Log.Write("Ripetitore interno: " + e.Message);
            }
            finally
            {
                lock (_lock) if (entry != null && entry.Current == client) entry.Current = null;
                try { client.Close(); } catch (SocketException) { }
            }
        }

        private static string ReadRequest(Socket client)
        {
            var sb = new StringBuilder();
            var one = new byte[1024];
            while (sb.Length < 16384)
            {
                int n = client.Receive(one);
                if (n <= 0) break;
                sb.Append(Encoding.ASCII.GetString(one, 0, n));
                if (sb.ToString().Contains("\r\n\r\n")) break;
            }
            return sb.ToString();
        }

        private static void Send(Socket s, string text)
        {
            var b = Encoding.ASCII.GetBytes(text);
            s.Send(b, 0, b.Length, SocketFlags.None);
        }

        public void Dispose()
        {
            _stopped = true;
            try { _listener.Stop(); } catch (SocketException) { }
        }
    }
}
