namespace BtInput.Protocol;

public enum MessageType
{
    TextDelta = 0x01,
    TextFullSync = 0x02,
    Heartbeat = 0x03,
    InputStarted = 0x04,
    InputStopped = 0x05,
    SegmentComplete = 0x06,
    SpecialKey = 0x07,
    Activate = 0x81,
    Deactivate = 0x82,
    SyncRequest = 0x83,
    Clear = 0x84
}

public enum DeltaOp
{
    Append,
    Insert,
    Delete,
    Replace
}

public interface IProtocolMessage
{
    MessageType MessageType { get; }
}

public sealed class TextDeltaMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.TextDelta;
    public int Seq { get; init; }
    public DeltaOp Op { get; init; }
    public int Position { get; init; }
    public int DeleteCount { get; init; }
    public string Text { get; init; } = string.Empty;
    public bool ClipboardHint { get; init; }
}

public sealed class TextFullSyncMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.TextFullSync;
    public int Seq { get; init; }
    public string Text { get; init; } = string.Empty;
}

public sealed class HeartbeatMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.Heartbeat;
    public int Battery { get; init; }
    public string ImeName { get; init; } = string.Empty;
}

public sealed class SegmentCompleteMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.SegmentComplete;
    public int Seq { get; init; }
    public int TotalChars { get; init; }
}

public sealed class InputStartedMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.InputStarted;
}

public sealed class InputStoppedMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.InputStopped;
}

public sealed class SpecialKeyMessage : IProtocolMessage
{
    public MessageType MessageType { get; init; } = MessageType.SpecialKey;
    public int Seq { get; init; }
    public string Key { get; init; } = string.Empty;
}
