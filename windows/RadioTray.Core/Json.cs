using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace RadioTray
{
    /// <summary>
    /// JSON minimo, senza dipendenze: oggetti → Dictionary&lt;string, object&gt; (l'ordine delle chiavi resta),
    /// elenchi → List&lt;object&gt;, numeri → double, true/false → bool, null → null.
    /// </summary>
    public static class Json
    {
        public sealed class JsonException : Exception
        {
            public JsonException(string message) : base(message) { }
        }

        public static object Parse(string text)
        {
            var p = new Parser(text ?? "");
            p.SkipSpace();
            var value = p.ReadValue();
            p.SkipSpace();
            if (!p.AtEnd) throw p.Error("testo in più dopo la fine");
            return value;
        }

        private sealed class Parser
        {
            private readonly string _s;
            private int _i;
            public Parser(string s)
            {
                _s = s;
                if (_s.Length > 0 && _s[0] == '﻿') _i = 1;
            }
            public bool AtEnd => _i >= _s.Length;

            public JsonException Error(string what)
            {
                int line = 1, col = 1;
                for (int k = 0; k < _i && k < _s.Length; k++)
                {
                    if (_s[k] == '\n') { line++; col = 1; } else col++;
                }
                return new JsonException($"{what} (riga {line}, colonna {col})");
            }

            public void SkipSpace()
            {
                while (_i < _s.Length && (_s[_i] == ' ' || _s[_i] == '\t' || _s[_i] == '\r' || _s[_i] == '\n')) _i++;
            }

            public object ReadValue()
            {
                if (AtEnd) throw Error("il testo finisce troppo presto");
                char c = _s[_i];
                switch (c)
                {
                    case '{': return ReadObject();
                    case '[': return ReadArray();
                    case '"': return ReadString();
                    case 't': Expect("true"); return true;
                    case 'f': Expect("false"); return false;
                    case 'n': Expect("null"); return null;
                    default:
                        if (c == '-' || (c >= '0' && c <= '9')) return ReadNumber();
                        throw Error($"carattere inatteso '{c}'");
                }
            }

            private void Expect(string word)
            {
                if (string.CompareOrdinal(_s, _i, word, 0, word.Length) != 0) throw Error($"atteso \"{word}\"");
                _i += word.Length;
            }

            private Dictionary<string, object> ReadObject()
            {
                var obj = new Dictionary<string, object>();
                _i++;
                SkipSpace();
                if (!AtEnd && _s[_i] == '}') { _i++; return obj; }
                while (true)
                {
                    SkipSpace();
                    if (AtEnd || _s[_i] != '"') throw Error("atteso il nome di un campo tra virgolette");
                    string key = ReadString();
                    SkipSpace();
                    if (AtEnd || _s[_i] != ':') throw Error("attesi i due punti ':'");
                    _i++;
                    SkipSpace();
                    obj[key] = ReadValue();
                    SkipSpace();
                    if (AtEnd) throw Error("manca la parentesi '}'");
                    if (_s[_i] == ',') { _i++; continue; }
                    if (_s[_i] == '}') { _i++; return obj; }
                    throw Error("attesa una virgola o '}'");
                }
            }

            private List<object> ReadArray()
            {
                var list = new List<object>();
                _i++;
                SkipSpace();
                if (!AtEnd && _s[_i] == ']') { _i++; return list; }
                while (true)
                {
                    SkipSpace();
                    list.Add(ReadValue());
                    SkipSpace();
                    if (AtEnd) throw Error("manca la parentesi ']'");
                    if (_s[_i] == ',') { _i++; continue; }
                    if (_s[_i] == ']') { _i++; return list; }
                    throw Error("attesa una virgola o ']'");
                }
            }

            private string ReadString()
            {
                var sb = new StringBuilder();
                _i++;
                while (true)
                {
                    if (AtEnd) throw Error("manca la virgoletta di chiusura");
                    char c = _s[_i++];
                    if (c == '"') return sb.ToString();
                    if (c == '\\')
                    {
                        if (AtEnd) throw Error("sequenza \\ incompleta");
                        char e = _s[_i++];
                        switch (e)
                        {
                            case '"': sb.Append('"'); break;
                            case '\\': sb.Append('\\'); break;
                            case '/': sb.Append('/'); break;
                            case 'b': sb.Append('\b'); break;
                            case 'f': sb.Append('\f'); break;
                            case 'n': sb.Append('\n'); break;
                            case 'r': sb.Append('\r'); break;
                            case 't': sb.Append('\t'); break;
                            case 'u':
                                if (_i + 4 > _s.Length || !int.TryParse(_s.Substring(_i, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int code))
                                    throw Error("sequenza \\u non valida");
                                sb.Append((char)code);
                                _i += 4;
                                break;
                            default: throw Error($"sequenza \\{e} non valida");
                        }
                    }
                    else if (c < ' ')
                    {
                        throw Error("a capo dentro una stringa");
                    }
                    else sb.Append(c);
                }
            }

            private double ReadNumber()
            {
                int start = _i;
                if (_s[_i] == '-') _i++;
                while (_i < _s.Length && "0123456789.eE+-".IndexOf(_s[_i]) >= 0) _i++;
                string n = _s.Substring(start, _i - start);
                if (!double.TryParse(n, NumberStyles.Float, CultureInfo.InvariantCulture, out double v)) throw Error($"numero non valido \"{n}\"");
                return v;
            }
        }

        /// <summary>JSON leggibile (rientro di 3 spazi come i file di Radiotray-NG), senza "\/".</summary>
        public static string Write(object value)
        {
            var sb = new StringBuilder();
            WriteValue(sb, value, 0);
            sb.Append('\n');
            return sb.ToString();
        }

        private static void Indent(StringBuilder sb, int level) => sb.Append(' ', level * 3);

        private static void WriteValue(StringBuilder sb, object value, int level)
        {
            switch (value)
            {
                case null: sb.Append("null"); break;
                case bool b: sb.Append(b ? "true" : "false"); break;
                case string s: WriteString(sb, s); break;
                case double d: sb.Append(d.ToString("R", CultureInfo.InvariantCulture)); break;
                case int n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); break;
                case long l: sb.Append(l.ToString(CultureInfo.InvariantCulture)); break;
                case IDictionary<string, object> obj:
                    if (obj.Count == 0) { sb.Append("{}"); break; }
                    sb.Append("{\n");
                    int k = 0;
                    foreach (var kv in obj)
                    {
                        Indent(sb, level + 1);
                        WriteString(sb, kv.Key);
                        sb.Append(": ");
                        WriteValue(sb, kv.Value, level + 1);
                        if (++k < obj.Count) sb.Append(',');
                        sb.Append('\n');
                    }
                    Indent(sb, level);
                    sb.Append('}');
                    break;
                case System.Collections.IEnumerable list:
                    var items = new List<object>();
                    foreach (var o in list) items.Add(o);
                    if (items.Count == 0) { sb.Append("[]"); break; }
                    sb.Append("[\n");
                    for (int i = 0; i < items.Count; i++)
                    {
                        Indent(sb, level + 1);
                        WriteValue(sb, items[i], level + 1);
                        if (i + 1 < items.Count) sb.Append(',');
                        sb.Append('\n');
                    }
                    Indent(sb, level);
                    sb.Append(']');
                    break;
                default:
                    WriteString(sb, Convert.ToString(value, CultureInfo.InvariantCulture));
                    break;
            }
        }

        private static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }
    }
}
