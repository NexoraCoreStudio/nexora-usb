using System.Collections.Generic;
using Nexora.Usb.Protocol.Helper;

namespace Nexora.Usb.Tests
{
    internal class FakePacketSink : IPacketSink
    {
        public List<byte[]> SentPackets { get; } = new();

        public byte[] LastPacket => SentPackets[^1];

        public void Send(byte[] data)
        {
            SentPackets.Add(data);
        }
    }
}
