using System;

namespace RadioTray
{
    public enum AudioKind { Unknown, Mp3, Aac, Ogg, Flac, Html, Hls }

    /// <summary>Riconosce il formato dello stream dal Content-Type e, se serve, dai primi byte.</summary>
    public static class AudioFormat
    {
        public static AudioKind FromContentType(string contentType)
        {
            string ct = (contentType ?? "").ToLowerInvariant();
            int semi = ct.IndexOf(';');
            if (semi >= 0) ct = ct.Substring(0, semi);
            ct = ct.Trim();
            switch (ct)
            {
                case "audio/mpeg": case "audio/mp3": case "audio/mpeg3": case "audio/x-mpeg": case "audio/x-mp3":
                    return AudioKind.Mp3;
                case "audio/aac": case "audio/aacp": case "audio/x-aac": case "application/aacp": case "audio/vnd.dlna.adts":
                    return AudioKind.Aac;
                case "application/ogg": case "audio/ogg": case "audio/opus": case "audio/vorbis": case "audio/x-ogg":
                    return AudioKind.Ogg;
                case "audio/flac": case "audio/x-flac":
                    return AudioKind.Flac;
                case "text/html":
                    return AudioKind.Html;
                case "application/vnd.apple.mpegurl": case "application/x-mpegurl": case "audio/x-mpegurl": case "audio/mpegurl":
                    return AudioKind.Hls;
                default:
                    return AudioKind.Unknown;
            }
        }

        /// <summary>Dai primi byte dell'audio: ID3, sincronismo MPEG (layer III = MP3, layer "00" = ADTS/AAC), OggS, fLaC, HTML.</summary>
        public static AudioKind Sniff(byte[] data, int length)
        {
            if (data == null || length < 4) return AudioKind.Unknown;
            if (data[0] == 'I' && data[1] == 'D' && data[2] == '3') return AudioKind.Mp3;
            if (data[0] == 'O' && data[1] == 'g' && data[2] == 'g' && data[3] == 'S') return AudioKind.Ogg;
            if (data[0] == 'f' && data[1] == 'L' && data[2] == 'a' && data[3] == 'C') return AudioKind.Flac;
            string head = System.Text.Encoding.ASCII.GetString(data, 0, Math.Min(length, 64)).TrimStart().ToLowerInvariant();
            if (head.StartsWith("<!doctype html", StringComparison.Ordinal) || head.StartsWith("<html", StringComparison.Ordinal)) return AudioKind.Html;
            if (head.StartsWith("#extm3u", StringComparison.Ordinal)) return AudioKind.Hls;
            // si cercano due intestazioni di frame consecutive per non farsi ingannare da byte casuali
            int mp3 = 0, aac = 0;
            for (int i = 0; i + 1 < length && i < 16384; i++)
            {
                if (data[i] != 0xFF || (data[i + 1] & 0xE0) != 0xE0) continue;
                int layer = (data[i + 1] >> 1) & 0x03;
                if (layer == 0 && (data[i + 1] & 0xF6) == 0xF0)
                {
                    // ADTS: lunghezza del frame nei byte 3-5
                    if (i + 6 >= length) break;
                    int frame = ((data[i + 3] & 0x03) << 11) | (data[i + 4] << 3) | (data[i + 5] >> 5);
                    if (frame > 7 && i + frame + 1 < length && data[i + frame] == 0xFF && (data[i + frame + 1] & 0xF6) == 0xF0)
                    {
                        if (++aac >= 2) return AudioKind.Aac;
                        i += frame - 1;
                    }
                }
                else if (layer == 1)
                {
                    int len = Mp3FrameLength(data, i, length);
                    if (len > 0 && i + len + 1 < length && data[i + len] == 0xFF && (data[i + len + 1] & 0xE0) == 0xE0)
                    {
                        if (++mp3 >= 2) return AudioKind.Mp3;
                        i += len - 1;
                    }
                }
            }
            return AudioKind.Unknown;
        }

        private static readonly int[] BitratesV1L3 = { 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 };
        private static readonly int[] BitratesV2L3 = { 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0 };
        private static readonly int[] RatesV1 = { 44100, 48000, 32000, 0 };

        private static int Mp3FrameLength(byte[] d, int i, int length)
        {
            if (i + 3 >= length) return 0;
            int version = (d[i + 1] >> 3) & 0x03;   // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
            if (version == 1) return 0;
            int bitrateIndex = (d[i + 2] >> 4) & 0x0F, rateIndex = (d[i + 2] >> 2) & 0x03, padding = (d[i + 2] >> 1) & 1;
            int kbps = version == 3 ? BitratesV1L3[bitrateIndex] : BitratesV2L3[bitrateIndex];
            int rate = RatesV1[rateIndex];
            if (kbps == 0 || rate == 0) return 0;
            if (version == 2) rate /= 2;
            if (version == 0) rate /= 4;
            return (version == 3 ? 144 : 72) * kbps * 1000 / rate + padding;
        }
    }
}
