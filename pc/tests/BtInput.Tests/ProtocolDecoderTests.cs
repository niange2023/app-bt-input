using System.Text;
using BtInput.Core;
using BtInput.Protocol;

namespace BtInput.Tests;

public class ProtocolDecoderTests
{
    [Fact]
    public void Decode_TextDelta_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":1,\"s\":1,\"o\":\"A\",\"p\":0,\"n\":0,\"d\":\"你\",\"c\":false}");

        var message = decoder.Decode(bytes);

        var typed = Assert.IsType<TextDeltaMessage>(message);
        Assert.Equal(1, typed.Seq);
        Assert.Equal(DeltaOp.Append, typed.Op);
        Assert.Equal("你", typed.Text);
    }

    [Fact]
    public void Decode_TextFullSync_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":2,\"s\":8,\"d\":\"完整\"}");

        var message = decoder.Decode(bytes);

        var typed = Assert.IsType<TextFullSyncMessage>(message);
        Assert.Equal("完整", typed.Text);
    }

    [Fact]
    public void Decode_Heartbeat_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":3,\"bat\":85,\"ime\":\"搜狗\"}");

        var message = decoder.Decode(bytes);

        var typed = Assert.IsType<HeartbeatMessage>(message);
        Assert.Equal(85, typed.Battery);
        Assert.Equal("搜狗", typed.ImeName);
    }

    [Fact]
    public void Decode_InputStarted_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":4}");

        var message = decoder.Decode(bytes);

        Assert.IsType<InputStartedMessage>(message);
    }

    [Fact]
    public void Decode_InputStopped_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":5}");

        var message = decoder.Decode(bytes);

        Assert.IsType<InputStoppedMessage>(message);
    }

    [Fact]
    public void Decode_SegmentComplete_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":6,\"s\":10,\"total_chars\":500}");

        var message = decoder.Decode(bytes);

        var typed = Assert.IsType<SegmentCompleteMessage>(message);
        Assert.Equal(500, typed.TotalChars);
    }

    [Fact]
    public void Decode_SpecialKey_ReturnsMessage()
    {
        var decoder = new ProtocolDecoder();
        var bytes = Encoding.UTF8.GetBytes("{\"t\":7,\"s\":11,\"k\":\"Ctrl+V\"}");

        var message = decoder.Decode(bytes);

        var typed = Assert.IsType<SpecialKeyMessage>(message);
        Assert.Equal(11, typed.Seq);
        Assert.Equal("Ctrl+V", typed.Key);
    }
}
