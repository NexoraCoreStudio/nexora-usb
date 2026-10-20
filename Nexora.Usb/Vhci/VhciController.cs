using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using NLog;

namespace Nexora.Usb.Vhci
{
    /// <summary>
    /// Connects a Nexora USB/IP export using the locally installed usbip-win2
    /// command-line client. This avoids depending on a particular private VHCI IOCTL
    /// layout. Requires a compatible, installed usbip.exe and its signed driver.
    /// </summary>
    public sealed class VhciController
    {
        private static readonly string UsbipExe = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "USBip", "usbip.exe");

        private readonly Logger _logger = LogManager.GetCurrentClassLogger();

        public bool TryAttach(string host, string service, string busid, out int port, out string? error)
        {
            port = 0;
            error = null;

            if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(service) ||
                string.IsNullOrWhiteSpace(busid))
            {
                error = "USB/IP host, service and busid are required.";
                return false;
            }

            if (!int.TryParse(service, NumberStyles.None, CultureInfo.InvariantCulture,
                    out var tcpPort) || tcpPort < 1024 || tcpPort > 65535)
            {
                error = $"Invalid USB/IP service port: {service}";
                return false;
            }

            var info = NewProcess();
            // Global TCP port option must precede the subcommand.
            if (tcpPort != 3240)
            {
                info.ArgumentList.Add("--tcp-port");
                info.ArgumentList.Add(service);
            }
            info.ArgumentList.Add("attach");
            info.ArgumentList.Add("--remote");
            info.ArgumentList.Add(host);
            info.ArgumentList.Add("--bus-id");
            info.ArgumentList.Add(busid);
            info.ArgumentList.Add("--once");
            info.ArgumentList.Add("--terse");

            if (!Run(info, out var output, out error))
            {
                _logger.Warn($"usbip attach failed: {error}");
                return false;
            }

            // --terse prints the allocated hub port on supported usbip-win2 versions.
            var match = Regex.Match(output, @"(?m)^\s*(\d+)\s*$");
            if (!match.Success)
                match = Regex.Match(output, @"(?i)\bport\s+(\d+)\b");

            if (!match.Success || !int.TryParse(match.Groups[1].Value,
                    NumberStyles.None, CultureInfo.InvariantCulture, out port) || port <= 0)
            {
                error = "USB/IP attach returned success but no usable hub port: " + output.Trim();
                _logger.Warn(error);
                return false;
            }

            var attachedPort = port;
            _logger.Info(() => $"usbip attached busid={busid} host={host} service={service} to port={attachedPort}");
            return true;
        }

        public bool TryDetach(int port, out string? error)
        {
            error = null;
            if (port <= 0)
            {
                error = $"Invalid hub port: {port}";
                return false;
            }

            var info = NewProcess();
            info.ArgumentList.Add("detach");
            info.ArgumentList.Add("--port");
            info.ArgumentList.Add(port.ToString(CultureInfo.InvariantCulture));

            var success = Run(info, out _, out error);
            if (!success)
                _logger.Warn($"usbip detach port={port} failed: {error}");
            else
                _logger.Info(() => $"usbip detached port={port}");
            return success;
        }

        private static ProcessStartInfo NewProcess()
        {
            return new ProcessStartInfo
            {
                FileName = UsbipExe,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
        }

        private static bool Run(ProcessStartInfo info, out string output, out string? error)
        {
            output = string.Empty;
            error = null;

            if (!File.Exists(info.FileName))
            {
                error = "USB/IP executable not found: " + info.FileName;
                return false;
            }

            try
            {
                using var process = new Process { StartInfo = info };
                if (!process.Start())
                {
                    error = "Could not start USB/IP client.";
                    return false;
                }

                Task<string> stdOut = process.StandardOutput.ReadToEndAsync();
                Task<string> stdErr = process.StandardError.ReadToEndAsync();

                if (!process.WaitForExit(30000))
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit();
                    error = "USB/IP command timed out after 30 seconds.";
                    return false;
                }

                output = stdOut.GetAwaiter().GetResult();
                var stderr = stdErr.GetAwaiter().GetResult();
                if (process.ExitCode != 0)
                {
                    error = $"usbip.exe exited with code {process.ExitCode}: " +
                            (string.IsNullOrWhiteSpace(stderr) ? output.Trim() : stderr.Trim());
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                error = $"USB/IP process failed: {ex.Message}";
                return false;
            }
        }
    }
}
