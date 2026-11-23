using System;
using System.IO;
using NAudio.Wave;

namespace RadioTray
{
    /// <summary>Un decodificatore di stream: dà PCM a blocchi; 0 = fine.</summary>
    internal interface IStreamDecoder : IDisposable
    {
        WaveFormat WaveFormat { get; }
        int Read(byte[] buffer, int offset, int count);
        string Name { get; }
    }

    /// <summary>MP3 frame per frame con il codec MP3 di Windows (ACM): adatto agli stream senza fine.</summary>
    internal sealed class Mp3StreamDecoder : IStreamDecoder
    {
        private readonly Stream _source;
        private IMp3FrameDecompressor _decompressor;
        private readonly byte[] _pcm = new byte[16384 * 4];
        private int _pcmOffset, _pcmCount;

        public WaveFormat WaveFormat { get; private set; }
        public string Name => "MP3 (codec di Windows)";

        public Mp3StreamDecoder(Stream source)
        {
            _source = source;
            // il primo frame serve a conoscere il formato
            if (!DecodeNext()) throw new InvalidDataException("Nello stream non c'è audio MP3 leggibile");
        }

        private bool DecodeNext()
        {
            for (int errors = 0; errors < 20;)
            {
                Mp3Frame frame;
                try
                {
                    frame = Mp3Frame.LoadFromStream(_source);
                }
                catch (EndOfStreamException) { return false; }
                catch (InvalidDataException) { errors++; continue; }
                if (frame == null) return false;
                if (_decompressor == null)
                {
                    var format = new Mp3WaveFormat(frame.SampleRate, frame.ChannelMode == ChannelMode.Mono ? 1 : 2, frame.FrameLength, frame.BitRate);
                    _decompressor = new AcmMp3FrameDecompressor(format);
                    WaveFormat = _decompressor.OutputFormat;
                }
                try
                {
                    _pcmCount = _decompressor.DecompressFrame(frame, _pcm, 0);
                    _pcmOffset = 0;
                    if (_pcmCount > 0) return true;
                }
                catch (Exception) { errors++; }
            }
            throw new InvalidDataException("Troppi errori nella decodifica MP3");
        }

        public int Read(byte[] buffer, int offset, int count)
        {
            if (_pcmCount == 0 && !DecodeNext()) return 0;
            int take = Math.Min(count, _pcmCount);
            Buffer.BlockCopy(_pcm, _pcmOffset, buffer, offset, take);
            _pcmOffset += take;
            _pcmCount -= take;
            return take;
        }

        public void Dispose() => _decompressor?.Dispose();
    }

    /// <summary>
    /// Media Foundation (il motore audio di Windows: AAC, HE-AAC, MP3), che legge dal ripetitore interno su 127.0.0.1:
    /// così non va su Internet da solo e non deve conoscere il proxy.
    /// </summary>
    internal sealed class MediaFoundationDecoder : IStreamDecoder
    {
        private readonly MediaFoundationReader _reader;
        public WaveFormat WaveFormat => _reader.WaveFormat;
        public string Name => "Media Foundation";

        public MediaFoundationDecoder(string localUrl)
        {
            _reader = new MediaFoundationReader(localUrl, new MediaFoundationReader.MediaFoundationReaderSettings { RequestFloatOutput = false, RepositionInRead = false, SingleReaderObject = true });
        }

        public int Read(byte[] buffer, int offset, int count) => _reader.Read(buffer, offset, count);

        public void Dispose() => _reader.Dispose();
    }
}
