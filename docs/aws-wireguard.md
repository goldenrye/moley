# AWS WireGuard Setup

This is a manual deployment guide, not an already-provisioned server. Commands
assume a **dedicated, new Ubuntu 24.04 EC2 instance**. Review them before running;
do not replace the firewall on a shared host. Budget for EC2, public IPv4,
storage, and internet egress. Configure billing alerts.

## 1. AWS Network

- Choose a US region such as `us-east-1` and an Ubuntu EC2 instance.
- Place it in a public subnet with `0.0.0.0/0` routed to an Internet Gateway.
- Associate an Elastic IP so configurations survive instance replacement.
- Security group inbound: UDP 51820 from family networks (or `0.0.0.0/0` if they
  roam). Only authenticated WireGuard peers can decrypt traffic.
- Administration: prefer SSM; otherwise SSH 22 only from your administrator IP.
  Do not expose a public HTTP/SOCKS proxy or administration dashboard.
- Require IMDSv2, set the metadata hop limit to 1, and attach no unnecessary IAM
  permissions. The host firewall below also blocks metadata/private destinations.
- Disable the instance's source/destination check for its VPN-router role.
- Outbound must permit the DNS and public web services the family needs.

An optional DNS A record, e.g. `vpn.example.com`, can point at the Elastic IP.
Do not publish an AAAA record unless the server really accepts IPv6 WireGuard.

## 2. Install and Generate Keys

On the server:

```bash
sudo apt-get update
sudo apt-get install wireguard nftables
sudo install -d -m 700 /etc/wireguard
sudo -i
umask 077
wg genkey > /etc/wireguard/server.key
wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub
```

Generate each **device's** key on a trusted administrator machine with
`wireguard-tools` installed. Use a private directory outside this repository:

```bash
umask 077
wg genkey > family-phone.key
wg pubkey < family-phone.key > family-phone.pub
wg genpsk > family-phone.psk
```

Only the public key and optional preshared key need to go to the server. Never
reuse the same device key/address across phones. The sample below is device 2;
increment to 3, 4, etc. for other devices.

## 3. Server Configuration

Create `/etc/wireguard/wg0.conf`, mode `0600`, replacing the uppercase markers
with the corresponding file contents:

```ini
[Interface]
PrivateKey = SERVER_PRIVATE_KEY
Address = 10.66.66.1/24, fd66:6d6f:6c65::1/64
ListenPort = 51820
MTU = 1280

[Peer]
PublicKey = DEVICE_PUBLIC_KEY
PresharedKey = DEVICE_PRESHARED_KEY
AllowedIPs = 10.66.66.2/32, fd66:6d6f:6c65::2/128
```

**Server** AllowedIPs must be the individual device addresses, never the client
default routes. Add another Peer section for every device.

Persist these settings in `/etc/sysctl.d/70-moley.conf`:

```ini
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

Then run `sudo sysctl --system`. IPv6 forwarding is enabled so IPv6 packets enter
the firewall and are explicitly rejected, not left on the phone's native route.
This starter deployment provides **IPv4 internet egress only**. IPv6-only websites
will not work; dual-stack websites should fall back to IPv4.

## 4. Dedicated-Host Firewall

Find the public-facing Linux interface with `ip -4 route show default` (often
`ens5`). Replace `ens5` below if needed. On a fresh dedicated host, place these
tables in `/etc/nftables.conf`. There is deliberately no `flush ruleset`; do not
erase rules belonging to other services. Do not combine this guide with UFW,
Docker, or another firewall manager without reconciling their forwarding rules.

```nft
#!/usr/sbin/nft -f

table inet moley_filter {
    chain input {
        type filter hook input priority -10; policy accept;
        # VPN peers cannot access SSH, metadata relays, or services on this host.
        iifname "wg0" counter reject
    }
    chain forward {
        type filter hook forward priority -10; policy accept;
        iifname "wg0" oifname "wg0" counter reject
        # Capture IPv6 inside the VPN, but do not forward it to the internet.
        iifname "wg0" meta nfproto ipv6 counter reject
        # Block private/VPC, loopback, link-local/metadata and special ranges.
        iifname "wg0" ip daddr {
            0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
            169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
            192.0.0.0/24, 192.0.2.0/24, 198.18.0.0/15,
            198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4
        } counter reject
        iifname "wg0" oifname "ens5" ip saddr 10.66.66.0/24 counter accept
        iifname "wg0" counter reject
        oifname "wg0" ct state established,related counter accept
        oifname "wg0" counter reject
    }
}

table ip moley_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 10.66.66.0/24 oifname "ens5" masquerade
    }
}
```

Validate before enabling:

```bash
sudo nft --check --file /etc/nftables.conf
sudo systemctl enable --now nftables
sudo systemctl enable --now wg-quick@wg0
sudo wg show wg0
```

Make firewall startup a prerequisite for WireGuard using
`sudo systemctl edit wg-quick@wg0`:

```ini
[Unit]
Requires=nftables.service
After=nftables.service
```

Run `sudo systemctl daemon-reload`. If the firewall was already running before
editing its file, explicitly load the reviewed configuration and verify it with
`sudo nft list ruleset`. Reboot-test persistence before giving family access.

## 5. iPhone Configuration

Create a private `family-phone.conf` with actual keys and endpoint:

```ini
[Interface]
PrivateKey = DEVICE_PRIVATE_KEY
Address = 10.66.66.2/32, fd66:6d6f:6c65::2/128
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280

[Peer]
PublicKey = SERVER_PUBLIC_KEY
PresharedKey = DEVICE_PRESHARED_KEY
Endpoint = YOUR_ELASTIC_IP_OR_HOSTNAME:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

The DNS choice here is Cloudflare's public resolver; choose a resolver you trust.
Both IPv4 and IPv6 defaults must be present, even for this IPv4-only AWS egress.
Moley rejects a missing IPv6 default rather than silently leaking IPv6 routes.

Share via a trusted private channel (for example AirDrop), import in Moley,
approve the system VPN prompt and connect. Delete delivery copies and empty
recently-deleted storage as appropriate. A `.conf` file is an access credential.

On Android, Windows, macOS, and Linux, official WireGuard clients can use the
same configuration format, with a **different key and address per device**.

## 6. Verify and Operate

- Confirm a recent handshake in both Moley and `sudo wg show wg0`.
- Check your public IPv4 using a trusted IP-check website; it should be the
  Elastic IP. Confirm IPv6 does not reveal the phone's normal network.
- Check DNS behavior, Wi-Fi/cellular switching, screen lock, and server restart.
- Confirm peers cannot reach EC2 metadata (`169.254.169.254`), VPC hosts, other
  peers, or server administration services. Include the instance's public IP:
  local input via `wg0` should also be rejected.
- A server handshake does not prove forwarding, DNS, NAT, or website access.
  If browsing fails, inspect routes, firewall counters, security groups, and NAT.
- To revoke a lost device immediately:
  `sudo wg set wg0 peer DEVICE_PUBLIC_KEY remove`.
  Also remove its Peer section from `/etc/wireguard/wg0.conf`, or it will return
  on restart. Delete or rotate the corresponding preshared key.
- Keep Ubuntu and WireGuard patched. Restrict key backups and administrator
  access; monitor bandwidth/cost without recording browsing content.

These AWS/firewall steps are provided for deployment and must be validated on
your actual instance. No AWS resources have been created or modified here.
