using System;
using System.Collections.Generic;
using System.Text;

namespace RadioTray
{
    /// <summary>Tag ID3v2 (nei segmenti HLS): titoli, artista e il JSON con cui RDS manda il brano.</summary>
    public static class Id3
    {
        public sealed class Frame
        {
            public string Id;
            public byte[] Data;
        }

        /// <summary>Lunghezza del tag ID3v2 che comincia a <paramref name="offset"/>, oppure 0 se non c'è.</summary>
        public static int TagLength(byte[] d, int offset, int count)
        {
            if (count < 10 || d[offset] != 'I' || d[offset + 1] != 'D' || d[offset + 2] != '3') return 0;
            if (d[offset + 3] == 0xFF || d[offset + 4] == 0xFF) return 0;
            int size = Syncsafe(d, offset + 6);
            if (size < 0) return 0;
            bool footer = (d[offset + 5] & 0x10) != 0;
            return 10 + size + (footer ? 10 : 0);
        }

        private static int Syncsafe(byte[] d, int i)
        {
            if ((d[i] | d[i + 1] | d[i + 2] | d[i + 3]) >= 0x80) return -1;
            return (d[i] << 21) | (d[i + 1] << 14) | (d[i + 2] << 7) | d[i + 3];
        }

        /// <summary>Quanti byte di tag ID3 ci sono all'inizio (anche più tag di fila).</summary>
        public static int LeadingTagsLength(byte[] d, int count)
        {
            int pos = 0;
            while (pos < count)
            {
                int len = TagLength(d, pos, count - pos);
                if (len == 0) break;
                pos = Math.Min(count, pos + len);
            }
            return pos;
        }

        /// <summary>I frame di un tag ID3v2.3/2.4 (gli altri si ignorano).</summary>
        public static List<Frame> Frames(byte[] d, int offset, int count)
        {
            var frames = new List<Frame>();
            int len = TagLength(d, offset, count);
            if (len == 0) return frames;
            int version = d[offset + 3];
            if (version < 3) return frames;
            int end = Math.Min(offset + count, offset + len);
            int pos = offset + 10;
            if ((d[offset + 5] & 0x40) != 0 && pos + 4 <= end)
            {
                // intestazione estesa
                int ext = version == 4 ? Syncsafe(d, pos) : (d[pos] << 24 | d[pos + 1] << 16 | d[pos + 2] << 8 | d[pos + 3]) + 4;
                if (ext > 0) pos += ext;
            }
            while (pos + 10 <= end)
            {
                if (d[pos] == 0) break;   // riempimento
                string id = Encoding.ASCII.GetString(d, pos, 4);
                int size = version == 4 ? Syncsafe(d, pos + 4) : (d[pos + 4] << 24 | d[pos + 5] << 16 | d[pos + 6] << 8 | d[pos + 7]);
                if (size < 0 || pos + 10 + size > end) break;
                var data = new byte[size];
                Buffer.BlockCopy(d, pos + 10, data, 0, size);
                frames.Add(new Frame { Id = id, Data = data });
                pos += 10 + size;
            }
            return frames;
        }

        /// <summary>Testo di un frame T*** (il primo byte è la codifica).</summary>
        public static string Text(byte[] data)
        {
            if (data == null || data.Length < 2) return "";
            Encoding enc;
            switch (data[0])
            {
                case 1: enc = Encoding.Unicode; break;            // UTF-16 con BOM
                case 2: enc = Encoding.BigEndianUnicode; break;   // UTF-16BE
                case 3: enc = Encoding.UTF8; break;
                default: enc = PlaylistParser.Latin1; break;
            }
            string s = enc.GetString(data, 1, data.Length - 1);
            return s.Trim('\0', '﻿', ' ');
        }

        /// <summary>
        /// Il titolo nel formato "Artista - Titolo" da un tag ID3: prima il JSON della radio (RDS, in JSI3/TXXX/PRIV),
        /// poi TIT2 e TPE1. Null se il tag non dice niente sul brano.
        /// </summary>
        public static string StreamTitle(byte[] d, int offset, int count)
        {
            string title = null, artist = null;
            foreach (var f in Frames(d, offset, count))
            {
                var song = TrackInfo.StationSongFromData(f.Data);
                if (song != null) return song.Value.artist.Length > 0 ? song.Value.artist + " - " + song.Value.title : song.Value.title;
                if (f.Id == "TIT2") title = Text(f.Data);
                else if (f.Id == "TPE1") artist = Text(f.Data);
            }
            if (string.IsNullOrEmpty(title)) return null;
            return string.IsNullOrEmpty(artist) || title.Contains(" - ") ? title : artist + " - " + title;
        }
    }
}
