#!/bin/bash
# Create a new device's keys, client profile and server Peer section.
# Run on the trusted administrator machine; never inside this repository.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/new-device.sh NAME [--index N] [--qr]

  NAME       lowercase device name, e.g. mom-iphone or p60
  --index N  use tunnel address 10.66.66.N (default: next unused, from 2)
  --qr       also print the profile as a terminal QR code (needs qrencode)

Reads from $MOLEY_KEYS_DIR (default ~/moley-keys):
  awg-shared.conf  shared AWG block from scripts/generate_amnezia_settings.py
  server.env       SERVER_PUBLIC_KEY=..., SERVER_ENDPOINT=host:port,
                   optional CLIENT_DNS=1.1.1.1, 1.0.0.1
Writes devices/NAME/ with the keys, NAME.conf and server-peer.conf.
EOF
}

fail() { echo "error: $*" >&2; exit 1; }

keys_dir="${MOLEY_KEYS_DIR:-$HOME/moley-keys}"
name=""
index=""
qr=0
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --index) [[ $# -ge 2 ]] || fail "--index needs a number"; index="$2"; shift 2 ;;
        --qr) qr=1; shift ;;
        -*) fail "unknown option $1" ;;
        *) [[ -z "$name" ]] || fail "only one device name is allowed"; name="$1"; shift ;;
    esac
done
[[ -n "$name" ]] || { usage >&2; exit 1; }
[[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || fail "NAME must be lowercase letters, digits and dashes"

if command -v awg >/dev/null; then tool=awg
elif command -v wg >/dev/null; then tool=wg
else fail "install amneziawg-tools or wireguard-tools (brew install wireguard-tools)"
fi
if ((qr)); then command -v qrencode >/dev/null || fail "install qrencode (brew install qrencode) or omit --qr"; fi

shared="$keys_dir/awg-shared.conf"
server_env="$keys_dir/server.env"
[[ -f "$shared" ]] || fail "missing $shared; create it with scripts/generate_amnezia_settings.py"
[[ -f "$server_env" ]] || fail "missing $server_env with SERVER_PUBLIC_KEY and SERVER_ENDPOINT"
grep -q '^S1[[:space:]]*=' "$shared" || fail "$shared does not look like an AWG settings block"

# Parse rather than source, so the settings file cannot run commands.
setting() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$server_env" | tail -n 1; }
server_public_key="$(setting SERVER_PUBLIC_KEY)"
server_endpoint="$(setting SERVER_ENDPOINT)"
client_dns="$(setting CLIENT_DNS)"
client_dns="${client_dns:-1.1.1.1, 1.0.0.1}"
[[ "$server_public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "SERVER_PUBLIC_KEY in $server_env is not a WireGuard public key"
[[ "$server_endpoint" =~ ^[^[:space:]]+:[0-9]+$ ]] || fail "SERVER_ENDPOINT in $server_env must be host:port"

# Tunnel addresses already handed out, from every profile kept in the keys directory.
used="$(find "$keys_dir" -type f -name '*.conf' ! -name awg-shared.conf -exec grep -h '^Address' {} + 2>/dev/null \
    | grep -oE '10\.66\.66\.[0-9]+' | cut -d. -f4 | sort -n -u || true)"
if [[ -z "$index" ]]; then
    index=2
    while grep -qx "$index" <<<"$used"; do index=$((index + 1)); done
fi
[[ "$index" =~ ^[0-9]+$ ]] && ((index >= 2 && index <= 254)) || fail "--index must be between 2 and 254"
grep -qx "$index" <<<"$used" && fail "10.66.66.$index is already used by a profile in $keys_dir"

device_dir="$keys_dir/devices/$name"
[[ ! -e "$device_dir" ]] || fail "$device_dir already exists; choose another name"
umask 077
mkdir -p "$keys_dir/devices"
mkdir "$device_dir"

"$tool" genkey > "$device_dir/$name.key"
"$tool" pubkey < "$device_dir/$name.key" > "$device_dir/$name.pub"
"$tool" genpsk > "$device_dir/$name.psk"
private_key="$(<"$device_dir/$name.key")"
public_key="$(<"$device_dir/$name.pub")"
preshared_key="$(<"$device_dir/$name.psk")"
addresses="10.66.66.$index/32, fd66:6d6f:6c65::$index/128"

profile="$device_dir/$name.conf"
{
    echo "[Interface]"
    echo "PrivateKey = $private_key"
    echo "Address = $addresses"
    echo "DNS = $client_dns"
    echo "MTU = 1280"
    cat "$shared"
    echo
    echo "[Peer]"
    echo "PublicKey = $server_public_key"
    echo "PresharedKey = $preshared_key"
    echo "Endpoint = $server_endpoint"
    echo "AllowedIPs = 0.0.0.0/0, ::/0"
    echo "PersistentKeepalive = 25"
} > "$profile"

server_peer="$device_dir/server-peer.conf"
{
    echo
    echo "# $name"
    echo "[Peer]"
    echo "PublicKey = $public_key"
    echo "PresharedKey = $preshared_key"
    echo "AllowedIPs = $addresses"
} > "$server_peer"

cat <<EOF
Created $name with tunnel address 10.66.66.$index.

Profile for the device (an access credential; send it privately, e.g. AirDrop):
  $profile

1. Append this to /etc/amnezia/amneziawg/wg0.conf on the server:
$(cat "$server_peer")

2. Load it without disconnecting other devices:
  sudo bash -c 'awg syncconf wg0 <(awg-quick strip wg0)'

3. Import the profile on the device, connect, and confirm a recent handshake:
  sudo awg show wg0 latest-handshakes

If some devices were set up by hand outside $keys_dir, check
'sudo awg show wg0 allowed-ips' to be sure 10.66.66.$index is free.
EOF

if ((qr)); then
    echo
    echo "QR code for AmneziaWG-compatible apps (Moley on iPhone imports files or pasted text):"
    qrencode -t ansiutf8 < "$profile"
fi
