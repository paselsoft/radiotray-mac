using System;
using System.IO;
using System.Text;

namespace RadioTray
{
    /// <summary>Cartella dei dati (%APPDATA%\RadioTray) e registro radiotray.log, utile per capire cosa fa il proxy.</summary>
    internal static class AppPaths
    {
        public static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "RadioTray");
        public static string Bookmarks => Path.Combine(Folder, "bookmarks.json");
        public static string Settings => Path.Combine(Folder, "settings.json");
        public static string LogFile => Path.Combine(Folder, "radiotray.log");
        public static string Favorites => Path.Combine(Folder, "brani-preferiti.json");
        public static string History => Path.Combine(Folder, "ascoltati-di-recente.json");

        public static void Ensure() => Directory.CreateDirectory(Folder);
    }

    internal static class Log
    {
        private static readonly object Lock = new object();
        private const long MaxBytes = 1024 * 1024;

        public static void Write(string message)
        {
            string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {message}{Environment.NewLine}";
            lock (Lock)
            {
                try
                {
                    AppPaths.Ensure();
                    var info = new FileInfo(AppPaths.LogFile);
                    if (info.Exists && info.Length > MaxBytes)
                    {
                        string old = AppPaths.LogFile + ".1";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(AppPaths.LogFile, old);
                    }
                    File.AppendAllText(AppPaths.LogFile, line, Encoding.UTF8);
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            System.Diagnostics.Debug.Write(line);
        }
    }
}
