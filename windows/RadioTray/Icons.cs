using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>L'icona dell'app: a colori quando suona, grigia quando è spenta.</summary>
    internal static class Icons
    {
        public static readonly Icon App = Load();
        private static Icon _on, _off;

        private static Icon Load()
        {
            using (var s = typeof(Icons).Assembly.GetManifestResourceStream("RadioTray.ico"))
                return new Icon(s);
        }

        private static Size TraySize => SystemInformation.SmallIconSize;

        public static Icon On => _on ?? (_on = new Icon(App, TraySize));

        public static Icon Off
        {
            get
            {
                if (_off != null) return _off;
                using (var color = new Icon(App, TraySize).ToBitmap())
                using (var gray = new Bitmap(color.Width, color.Height, PixelFormat.Format32bppArgb))
                {
                    using (var g = Graphics.FromImage(gray))
                    using (var attributes = new ImageAttributes())
                    {
                        attributes.SetColorMatrix(new ColorMatrix(new[]
                        {
                            new[] { 0.30f, 0.30f, 0.30f, 0, 0 },
                            new[] { 0.59f, 0.59f, 0.59f, 0, 0 },
                            new[] { 0.11f, 0.11f, 0.11f, 0, 0 },
                            new[] { 0f, 0, 0, 0.85f, 0 },
                            new[] { 0f, 0, 0, 0, 1 },
                        }));
                        g.DrawImage(color, new Rectangle(0, 0, color.Width, color.Height), 0, 0, color.Width, color.Height, GraphicsUnit.Pixel, attributes);
                    }
                    IntPtr handle = gray.GetHicon();
                    _off = (Icon)Icon.FromHandle(handle).Clone();
                    NativeMethods.DestroyIcon(handle);
                }
                return _off;
            }
        }

        private static class NativeMethods
        {
            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern bool DestroyIcon(IntPtr handle);
        }
    }
}
