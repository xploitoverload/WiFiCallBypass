# WiFiCallBypass

This script enables **tunneling of Wi‑Fi Calling traffic over an SSH tunnel**.
It helps when mobile providers block Wi‑Fi Calling by IP/geolocation.

## Why Use This?

Some mobile providers restrict Wi-Fi Calling to users within their home country by blocking connections from foreign IP addresses.  
By tunneling your Wi-Fi Calling traffic through an SSH server in your home country, you can bypass these restrictions and use Wi-Fi Calling from anywhere.

## Features

- Tunnels Wi‑Fi Calling traffic over SSH using `sshuttle` (TPROXY)
- Route multiple destination servers (`--servers`)
- Support for HTTP/SOCKS proxies and `proxychains` (`--proxies`, `--use-proxychains`)
- Optional Tor support (`--tor`) to route through `socks5://127.0.0.1:9050`
- SSH pivoting / multi‑hop via `-J` (`--ssh-hops`)
- Automatic cleanup of ip rules/routes on exit

## Usage

1. **Ensure you have an SSH server in your home country.**  
   This is necessary to tunnel your Wi-Fi Calling traffic through a trusted location.

2. **Connect your phone to the Wi-Fi network you created (AP).**  
   For example, you can use a tool like [linux-wifi-hotspot](https://github.com/lakinduakash/linux-wifi-hotspot) to set up your access point.

3. **Run the script on your device or router.**  
    The script must be executed with root privileges.

4. **Script parameters**

   The script uses named parameters (order doesn't matter):

   - `--mnc`: Mobile Network Code (e.g., `001`)
   - `--mcc`: Mobile Country Code (e.g., `228`)
   - `--ssh`: SSH connection string (e.g., `user@host`)
   - `--servers`: Comma-separated destination hostnames or IPs (default: `epdg.epc.mnc${MNC}.mcc${MCC}.pub.3gppnetwork.org`)
   - `--proxies`: Comma-separated proxies (`socks5://host:port`, `http://host:port`, etc.)
   - `--use-proxychains`: Wrap `sshuttle` with `proxychains[4]` (uses system config or `--proxies`)
   - `--tor`: Add `socks5://127.0.0.1:9050` to proxies (requires Tor running locally)
   - `--ssh-hops`: Comma-separated SSH hops for `-J` (jump) proxying, e.g. `hop1@h1,hop2@h2`
   - `--tmark`: (Optional) Firewall mark for TPROXY (default: `0x01`)

   Basic example:

   ```bash
   sudo ./WiFiCallBypass.sh --mnc 001 --mcc 228 --ssh user@your-ssh-server
   ```

   Example with multiple servers, a local Tor proxy and SSH hops:

   ```bash
   sudo ./WiFiCallBypass.sh \
     --mnc 001 --mcc 228 \
     --ssh user@your-ssh-server \
     --servers epdg.epc.mnc001.mcc228.pub.3gppnetwork.org,example.com \
     --tor --use-proxychains \
     --ssh-hops hop1@h1,hop2@h2
   ```

5. **Verify connectivity from your phone:**  
   - Check that Wi-Fi Calling is enabled and works as expected.

### Notes

- The script will automatically configure routing and policy rules for transparent proxying and attempts to clean them up on exit.
- If you enable `--use-proxychains` and pass `--proxies`, the script will generate a temporary `proxychains` config and run `sshuttle` through it.
- Ensure your SSH credentials and server are reachable from the machine running the script.

## Requirements

- `sshuttle` (TPROXY mode)
- `ssh` (OpenSSH client)
- `iproute2` (`ip` command)
- `proxychains4` or `proxychains` (optional, for `--use-proxychains`)
- `tor` (optional, if using `--tor`)
- Root privileges (required for network configuration)

## Disclaimer

This software is provided "AS IS" for educational and research purposes only. Users are solely responsible for ensuring their use complies with applicable laws, regulations, and service provider terms of service. The author(s) assume no responsibility for any consequences resulting from the use of this software, including but not limited to service termination, legal action, or other penalties.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
