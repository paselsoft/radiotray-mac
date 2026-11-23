using System;
using System.Collections.Generic;

namespace RadioTray
{
    /// <summary>
    /// Separa da un flusso MPEG-TS (segmenti HLS .ts) l'audio (AAC ADTS o MP3) e i metadati ID3.
    /// I dati possono arrivare a pezzi qualsiasi.
    /// </summary>
    public sealed class TsDemuxer
    {
        private const int PacketSize = 188;
        private readonly byte[] _partial = new byte[PacketSize];
        private int _partialCount;
        private int _pmtPid = -1, _audioPid = -1, _id3Pid = -1;
        private readonly List<byte> _id3Pes = new List<byte>();
        private bool _audioPesStarted;

        /// <summary>Tipo dell'audio trovato nella tabella PMT.</summary>
        public AudioKind Audio { get; private set; } = AudioKind.Unknown;

        public event Action<byte[], int, int> AudioData;
        public event Action<string> Title;

        public void Feed(byte[] data, int offset, int count)
        {
            int i = offset, end = offset + count;
            if (_partialCount > 0)
            {
                int take = Math.Min(PacketSize - _partialCount, count);
                Buffer.BlockCopy(data, i, _partial, _partialCount, take);
                _partialCount += take;
                i += take;
                if (_partialCount < PacketSize) return;
                Packet(_partial, 0);
                _partialCount = 0;
            }
            while (i < end)
            {
                if (data[i] != 0x47) { i++; continue; }   // si cerca il sincronismo
                if (end - i < PacketSize)
                {
                    Buffer.BlockCopy(data, i, _partial, 0, end - i);
                    _partialCount = end - i;
                    return;
                }
                Packet(data, i);
                i += PacketSize;
            }
        }

        /// <summary>Fine del segmento: si consegnano i metadati rimasti in sospeso.</summary>
        public void Flush()
        {
            FlushId3();
        }

        private void Packet(byte[] p, int o)
        {
            bool start = (p[o + 1] & 0x40) != 0;
            int pid = ((p[o + 1] & 0x1F) << 8) | p[o + 2];
            int afc = (p[o + 3] >> 4) & 0x03;
            int pos = o + 4;
            if (afc == 2 || afc == 0) return;            // solo adaptation field
            if (afc == 3) pos += 1 + p[pos];
            int payloadEnd = o + PacketSize;
            if (pos >= payloadEnd) return;

            if (pid == 0) { if (start) Pat(p, pos + 1 + p[pos], payloadEnd); return; }
            if (pid == _pmtPid) { if (start) Pmt(p, pos + 1 + p[pos], payloadEnd); return; }
            if (pid == _audioPid)
            {
                if (start)
                {
                    int header = PesHeaderLength(p, pos, payloadEnd);
                    if (header < 0) return;
                    pos += header;
                    _audioPesStarted = true;
                }
                if (!_audioPesStarted || pos >= payloadEnd) return;
                AudioData?.Invoke(p, pos, payloadEnd - pos);
                return;
            }
            if (pid == _id3Pid)
            {
                if (start)
                {
                    FlushId3();
                    int header = PesHeaderLength(p, pos, payloadEnd);
                    if (header < 0) return;
                    pos += header;
                }
                for (int k = pos; k < payloadEnd; k++) _id3Pes.Add(p[k]);
            }
        }

        private void FlushId3()
        {
            if (_id3Pes.Count == 0) return;
            var d = _id3Pes.ToArray();
            _id3Pes.Clear();
            string t = Id3.StreamTitle(d, 0, d.Length);
            if (t != null) Title?.Invoke(t);
        }

        private static int PesHeaderLength(byte[] p, int pos, int end)
        {
            if (end - pos < 9 || p[pos] != 0 || p[pos + 1] != 0 || p[pos + 2] != 1) return -1;
            return 9 + p[pos + 8];
        }

        private void Pat(byte[] p, int pos, int end)
        {
            if (pos + 8 > end) return;
            int sectionLength = ((p[pos + 1] & 0x0F) << 8) | p[pos + 2];
            int stop = Math.Min(end, pos + 3 + sectionLength - 4);
            for (int k = pos + 8; k + 4 <= stop; k += 4)
            {
                int program = (p[k] << 8) | p[k + 1];
                if (program == 0) continue;   // rete
                _pmtPid = ((p[k + 2] & 0x1F) << 8) | p[k + 3];
                return;
            }
        }

        private void Pmt(byte[] p, int pos, int end)
        {
            if (pos + 12 > end) return;
            int sectionLength = ((p[pos + 1] & 0x0F) << 8) | p[pos + 2];
            int stop = Math.Min(end, pos + 3 + sectionLength - 4);
            int infoLength = ((p[pos + 10] & 0x0F) << 8) | p[pos + 11];
            for (int k = pos + 12 + infoLength; k + 5 <= stop;)
            {
                int type = p[k];
                int pid = ((p[k + 1] & 0x1F) << 8) | p[k + 2];
                int esInfo = ((p[k + 3] & 0x0F) << 8) | p[k + 4];
                if (_audioPid < 0 && (type == 0x0F || type == 0x03 || type == 0x04))
                {
                    _audioPid = pid;
                    Audio = type == 0x0F ? AudioKind.Aac : AudioKind.Mp3;
                }
                else if (type == 0x15 && _id3Pid < 0)
                {
                    _id3Pid = pid;
                }
                k += 5 + esInfo;
            }
        }
    }
}
