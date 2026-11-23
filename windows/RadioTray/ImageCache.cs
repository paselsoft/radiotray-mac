using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>
    /// Copertine e loghi, scaricati attraverso il proxy e tenuti in %LOCALAPPDATA%\RadioTray\immagini.
    /// Le richieste senza risultato non si ripetono (fino al riavvio).
    /// </summary>
    internal static class ImageCache
    {
        private static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RadioTray", "immagini");
        private static readonly ConcurrentDictionary<string, bool> Missing = new ConcurrentDictionary<string, bool>();

        private static string FileFor(string key)
        {
            using (var sha = SHA1.Create())
            {
                var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(key));
                return Path.Combine(Folder, string.Concat(hash.Select(b => b.ToString("x2"))) + ".img");
            }
        }

        private static byte[] ReadCached(string key)
        {
            try
            {
                string f = FileFor(key);
                return File.Exists(f) ? File.ReadAllBytes(f) : null;
            }
            catch (IOException) { return null; }
        }

        private static void Store(string key, byte[] data)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                File.WriteAllBytes(FileFor(key), data);
            }
            catch (Exception e) { Log.Write("Immagine non salvata in cache: " + e.Message); }
        }

        private static async Task<string> GetString(string url, CancellationToken ct)
        {
            using (var r = await Net.GetHeadersAsync(new Uri(url), false, TimeSpan.FromSeconds(10), ct).ConfigureAwait(false))
                return r.IsSuccessStatusCode ? await r.Content.ReadAsStringAsync().ConfigureAwait(false) : null;
        }

        /// <summary>Scarica un'immagine; null se non è un'immagine leggibile.</summary>
        private static async Task<byte[]> GetImage(string url, CancellationToken ct)
        {
            try
            {
                using (var r = await Net.GetHeadersAsync(new Uri(url), false, TimeSpan.FromSeconds(10), ct).ConfigureAwait(false))
                {
                    if (!r.IsSuccessStatusCode) return null;
                    var data = await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                    if (data.Length < 100 || data.Length > 5 * 1024 * 1024) return null;
                    using (var ms = new MemoryStream(data))
                    using (Image.FromStream(ms)) { }   // controlla che Windows la sappia leggere
                    return data;
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception) { return null; }
        }

        /// <summary>Copertina del brano: prima quella ufficiale della radio (RDS, GEDI), poi il catalogo di Apple.</summary>
        public static async Task<byte[]> CoverAsync(string title, string artist, string officialUrl, CancellationToken ct)
        {
            if (!string.IsNullOrEmpty(officialUrl))
            {
                string okey = "url|" + officialUrl;
                var cached = ReadCached(okey);
                if (cached != null) return cached;
                if (!Missing.ContainsKey(okey))
                {
                    var data = await GetImage(officialUrl, ct).ConfigureAwait(false);
                    if (data != null) { Store(okey, data); return data; }
                    Missing[okey] = true;
                }
            }
            if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(artist)) return null;
            string key = "cover|" + Artwork.CacheKey(title, artist);
            var hit = ReadCached(key);
            if (hit != null) return hit;
            if (Missing.ContainsKey(key)) return null;
            try
            {
                string json = await GetString(Artwork.SearchUrl(title, artist), ct).ConfigureAwait(false);
                string url = json == null ? null : Artwork.ArtworkUrlFromJson(json, title, artist);
                var data = url == null ? null : await GetImage(url, ct).ConfigureAwait(false);
                if (data != null) { Store(key, data); return data; }
                if (json != null) Missing[key] = true;   // nessun risultato (non un errore di rete)
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception e) { Log.Write("Copertina non scaricata: " + e.Message); }
            return null;
        }

        /// <summary>Logo della stazione: il campo "image" del file delle stazioni (file o indirizzo), poi Radio Browser.</summary>
        public static async Task<byte[]> LogoAsync(string name, string stationUrl, string image, CancellationToken ct)
        {
            if (!string.IsNullOrEmpty(image))
            {
                try
                {
                    if (File.Exists(image)) return File.ReadAllBytes(image);
                }
                catch (Exception) { }
                if (BookmarksDocument.IsWebUrl(image))
                {
                    var c = ReadCached("url|" + image);
                    if (c != null) return c;
                    var d = await GetImage(image, ct).ConfigureAwait(false);
                    if (d != null) { Store("url|" + image, d); return d; }
                }
            }
            if (string.IsNullOrEmpty(stationUrl)) return null;
            string key = "logo|" + stationUrl.ToLowerInvariant();
            var hit = ReadCached(key);
            if (hit != null) return hit;
            if (Missing.ContainsKey(key)) return null;
            try
            {
                var candidates = new List<string>();
                string server = RadioBrowser.Servers[0];
                string byUrl = await GetString(Artwork.LogoByUrlQuery(server, stationUrl), ct).ConfigureAwait(false);
                if (byUrl != null) candidates.AddRange(Artwork.FaviconsFromJson(byUrl));
                if (!string.IsNullOrEmpty(name))
                {
                    string byName = await GetString(Artwork.LogoByNameQuery(server, name), ct).ConfigureAwait(false);
                    if (byName != null) candidates.AddRange(Artwork.FaviconsFromJson(byName).Where(f => !candidates.Contains(f)));
                }
                foreach (var f in candidates.Take(6))
                {
                    var data = await GetImage(f, ct).ConfigureAwait(false);
                    if (data != null) { Store(key, data); return data; }
                }
                Missing[key] = true;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception e) { Log.Write("Logo non scaricato: " + e.Message); }
            return null;
        }

        /// <summary>Immagine da byte (copiata, così lo stream si può chiudere).</summary>
        public static Image ToImage(byte[] data)
        {
            if (data == null) return null;
            try
            {
                using (var ms = new MemoryStream(data))
                using (var img = Image.FromStream(ms))
                    return new Bitmap(img);
            }
            catch (Exception) { return null; }
        }
    }
}
