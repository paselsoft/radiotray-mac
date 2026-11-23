using System;
using System.IO;
using System.Threading;

namespace RadioTray
{
    /// <summary>
    /// Tubo di byte tra la connessione di rete (scrive) e il decodificatore (legge). Se il decodificatore è lento
    /// la rete aspetta (il buffer non cresce all'infinito); chiuso il tubo, i lettori ricevono la fine dei dati.
    /// </summary>
    internal sealed class AudioPipe
    {
        private readonly byte[] _buffer;
        private int _start, _count;
        private bool _writerDone, _aborted;
        private readonly object _lock = new object();

        public AudioPipe(int capacity = 1024 * 1024) { _buffer = new byte[capacity]; }

        public long TotalWritten { get; private set; }

        public int Available { get { lock (_lock) return _count; } }

        public void Write(byte[] data, int offset, int count)
        {
            lock (_lock)
            {
                while (count > 0)
                {
                    while (_count == _buffer.Length && !_aborted) Monitor.Wait(_lock, 500);
                    if (_aborted) throw new ObjectDisposedException(nameof(AudioPipe));
                    int end = (_start + _count) % _buffer.Length;
                    int take = Math.Min(count, Math.Min(_buffer.Length - _count, _buffer.Length - end));
                    Buffer.BlockCopy(data, offset, _buffer, end, take);
                    _count += take;
                    offset += take;
                    count -= take;
                    TotalWritten += take;
                    Monitor.PulseAll(_lock);
                }
            }
        }

        /// <summary>Legge almeno un byte (aspetta se serve); 0 = fine dei dati.</summary>
        public int Read(byte[] data, int offset, int count)
        {
            lock (_lock)
            {
                while (_count == 0 && !_writerDone && !_aborted) Monitor.Wait(_lock, 500);
                if (_aborted || _count == 0) return 0;
                int read = 0;
                while (read < count && _count > 0)
                {
                    int take = Math.Min(count - read, Math.Min(_count, _buffer.Length - _start));
                    Buffer.BlockCopy(_buffer, _start, data, offset + read, take);
                    _start = (_start + take) % _buffer.Length;
                    _count -= take;
                    read += take;
                }
                Monitor.PulseAll(_lock);
                return read;
            }
        }

        /// <summary>Copia i primi byte senza consumarli: aspetta di averne <paramref name="wanted"/>, la fine dei dati o il tempo massimo.</summary>
        public byte[] Peek(int wanted, TimeSpan timeout, CancellationToken ct)
        {
            var until = DateTime.UtcNow + timeout;
            lock (_lock)
            {
                while (_count < wanted && !_writerDone && !_aborted && DateTime.UtcNow < until && !ct.IsCancellationRequested)
                    Monitor.Wait(_lock, 200);
                var copy = new byte[Math.Min(wanted, _count)];
                for (int i = 0; i < copy.Length; i++) copy[i] = _buffer[(_start + i) % _buffer.Length];
                return copy;
            }
        }

        /// <summary>La rete ha finito: i lettori ricevono quello che resta e poi la fine.</summary>
        public void CompleteWriting()
        {
            lock (_lock) { _writerDone = true; Monitor.PulseAll(_lock); }
        }

        /// <summary>Si chiude tutto: chi scrive riceve un errore, chi legge la fine.</summary>
        public void Abort()
        {
            lock (_lock) { _aborted = true; Monitor.PulseAll(_lock); }
        }

        public bool IsFinished { get { lock (_lock) return _aborted || (_writerDone && _count == 0); } }

        public Stream AsStream() => new PipeStream(this);

        /// <summary>
        /// Il tubo come Stream in sola lettura. Read riempie sempre tutto il blocco richiesto (salvo fine dei dati):
        /// il lettore di frame MP3 di NAudio lo dà per scontato.
        /// </summary>
        private sealed class PipeStream : Stream
        {
            private readonly AudioPipe _pipe;
            private long _position;
            public PipeStream(AudioPipe pipe) { _pipe = pipe; }
            public override bool CanRead => true;
            public override bool CanSeek => false;
            public override bool CanWrite => false;
            public override long Length => throw new NotSupportedException();
            public override long Position { get => _position; set => throw new NotSupportedException(); }
            public override void Flush() { }
            public override int Read(byte[] buffer, int offset, int count)
            {
                int total = 0;
                while (total < count)
                {
                    int n = _pipe.Read(buffer, offset + total, count - total);
                    if (n <= 0) break;
                    total += n;
                }
                _position += total;
                return total;
            }
            public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
            public override void SetLength(long value) => throw new NotSupportedException();
            public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        }
    }
}
