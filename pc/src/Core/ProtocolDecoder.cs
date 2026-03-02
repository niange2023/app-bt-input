using System.Text;
using System.Text.Json;
using System.Diagnostics;
using BtInput.Protocol;

namespace BtInput.Core;

public sealed class ProtocolDecoder
{
    private readonly Dictionary<byte, FragmentBuffer> _fragmentBuffers = new();
    private int? _expectedSeq;

    public bool SequenceGapDetected { get; private set; }

    public IProtocolMessage? Decode(byte[] rawBytes)
    {
        if (rawBytes.Length == 0)
        {
            return null;
        }

        byte[] payloadBytes = rawBytes;
        if (LooksLikeFragment(rawBytes))
        {
            payloadBytes = HandleFragment(rawBytes);
            if (payloadBytes.Length == 0)
            {
                return null;
            }
        }

        try
        {
            var payload = Encoding.UTF8.GetString(payloadBytes);
            using var document = JsonDocument.Parse(payload);
            var root = document.RootElement;

            if (!root.TryGetProperty("t", out var typeElement))
            {
                return null;
            }

            var typeCode = typeElement.GetInt32();
            switch ((MessageType)typeCode)
            {
                case MessageType.TextDelta:
                    return DecodeTextDelta(root);
                case MessageType.TextFullSync:
                    return DecodeTextFullSync(root);
                case MessageType.Heartbeat:
                    return DecodeHeartbeat(root);
                case MessageType.InputStarted:
                    return new InputStartedMessage();
                case MessageType.InputStopped:
                    return new InputStoppedMessage();
                case MessageType.SegmentComplete:
                    return DecodeSegmentComplete(root);
                case MessageType.SpecialKey:
                    return DecodeSpecialKey(root);
                default:
                    return null;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Protocol decode failed: {ex.Message}");
            return null;
        }
    }

    private static bool LooksLikeFragment(byte[] bytes)
    {
        if (bytes.Length < 4)
        {
            return false;
        }

        return bytes[0] != (byte)'{';
    }

    private byte[] HandleFragment(byte[] bytes)
    {
        var messageId = bytes[0];
        var seqAndFlags = bytes[1];
        var total = bytes[2];

        var sequence = (seqAndFlags >> 4) & 0x0F;
        var flags = seqAndFlags & 0x0F;
        var isLast = (flags & 0x01) == 0x01;

        var chunk = bytes[3..];

        if (!_fragmentBuffers.TryGetValue(messageId, out var buffer))
        {
            buffer = new FragmentBuffer(total);
            _fragmentBuffers[messageId] = buffer;
        }

        buffer.Packets[sequence] = chunk;

        if (!isLast || buffer.Packets.Count < buffer.Total)
        {
            return Array.Empty<byte>();
        }

        var result = new List<byte>();
        for (var index = 0; index < buffer.Total; index++)
        {
            if (buffer.Packets.TryGetValue(index, out var packet) && packet is not null)
            {
                result.AddRange(packet);
            }
        }

        _fragmentBuffers.Remove(messageId);
        return result.ToArray();
    }

    private TextDeltaMessage DecodeTextDelta(JsonElement root)
    {
        var sequence = root.TryGetProperty("s", out var seqElement) ? seqElement.GetInt32() : 0;
        ValidateSequence(sequence);

        return new TextDeltaMessage
        {
            Seq = sequence,
            Op = ParseDeltaOp(root.TryGetProperty("o", out var operationElement) ? operationElement.GetString() : "A"),
            Position = root.TryGetProperty("p", out var positionElement) ? positionElement.GetInt32() : 0,
            DeleteCount = root.TryGetProperty("n", out var deleteCountElement) ? deleteCountElement.GetInt32() : 0,
            Text = root.TryGetProperty("d", out var textElement) ? textElement.GetString() ?? string.Empty : string.Empty,
            ClipboardHint = root.TryGetProperty("c", out var clipboardElement) && clipboardElement.GetBoolean()
        };
    }

    private TextFullSyncMessage DecodeTextFullSync(JsonElement root)
    {
        var sequence = root.TryGetProperty("s", out var seqElement) ? seqElement.GetInt32() : 0;
        ValidateSequence(sequence);

        return new TextFullSyncMessage
        {
            Seq = sequence,
            Text = root.TryGetProperty("d", out var textElement) ? textElement.GetString() ?? string.Empty : string.Empty
        };
    }

    private static HeartbeatMessage DecodeHeartbeat(JsonElement root)
    {
        return new HeartbeatMessage
        {
            Battery = root.TryGetProperty("bat", out var batteryElement) ? batteryElement.GetInt32() : 0,
            ImeName = root.TryGetProperty("ime", out var imeElement) ? imeElement.GetString() ?? string.Empty : string.Empty
        };
    }

    private SegmentCompleteMessage DecodeSegmentComplete(JsonElement root)
    {
        var sequence = root.TryGetProperty("s", out var seqElement) ? seqElement.GetInt32() : 0;
        ValidateSequence(sequence);

        return new SegmentCompleteMessage
        {
            Seq = sequence,
            TotalChars = root.TryGetProperty("total_chars", out var totalCharsElement) ? totalCharsElement.GetInt32() : 0
        };
    }

    private SpecialKeyMessage DecodeSpecialKey(JsonElement root)
    {
        var sequence = root.TryGetProperty("s", out var seqElement) ? seqElement.GetInt32() : 0;
        ValidateSequence(sequence);

        return new SpecialKeyMessage
        {
            Seq = sequence,
            Key = root.TryGetProperty("k", out var keyElement) ? keyElement.GetString() ?? string.Empty : string.Empty
        };
    }

    private void ValidateSequence(int received)
    {
        SequenceGapDetected = false;
        if (_expectedSeq.HasValue && _expectedSeq.Value != received)
        {
            SequenceGapDetected = true;
        }

        _expectedSeq = received + 1;
    }

    private static DeltaOp ParseDeltaOp(string? op)
    {
        return op switch
        {
            "A" => DeltaOp.Append,
            "I" => DeltaOp.Insert,
            "D" => DeltaOp.Delete,
            "R" => DeltaOp.Replace,
            _ => DeltaOp.Append
        };
    }

    private sealed class FragmentBuffer
    {
        public FragmentBuffer(int total)
        {
            Total = total;
        }

        public int Total { get; }
        public Dictionary<int, byte[]> Packets { get; } = new();
    }
}
