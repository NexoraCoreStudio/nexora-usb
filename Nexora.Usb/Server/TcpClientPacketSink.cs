using System.Net.Sockets;
using Nexora.Usb.Protocol.Helper;

namespace Nexora.Usb
{
    internal class TcpClientPacketSink : IPacketSink
    {
        private readonly TcpClient _client;

        public TcpClientPacketSink(TcpClient client)
        {
            _client = client;
        }

        public void Send(byte[] data)
        {
            var stream = _client.GetStream();
            stream.Write(data, 0, data.Length);
            stream.Flush();
        }
    }
}
