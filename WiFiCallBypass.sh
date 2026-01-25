#!/bin/bash

# Default values
TMARK="0x01"
ROUTE_TABLE="100"
USE_PROXYCHAINS=0
USE_TOR=0

# Temporary proxychains config (if needed)
TMP_PROXYCHAINS_CONF=""

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., sudo $0 ...)"
  exit 1
fi

# Help message
usage() {
  echo "Usage: $0 --mnc <MNC> --mcc <MCC> --ssh <SSH_CONNECTION> [--servers <server1,server2,...>] [--servers <...>] [--proxies <proto://host:port,...>] [--use-proxychains] [--tor] [--ssh-hops <hop1,hop2,...>] [--tmark <TMARK>]"
  echo "Example: $0 --mnc 001 --mcc 228 --ssh user@host --servers epdg.epc.mnc001.mcc228.pub.3gppnetwork.org --proxies socks5://127.0.0.1:9050 --use-proxychains --ssh-hops hop1@host1,hop2@host2 --tmark 0x01"
  exit 1
}

# Parse named parameters
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --mnc)
      MNC="$2"
      shift; shift
      ;;
    --mcc)
      MCC="$2"
      shift; shift
      ;;
    --ssh)
      SSH_CONNECTION="$2"
      shift; shift
      ;;
    --tmark)
      TMARK="$2"
      shift; shift
      ;;
    --proxies)
      PROXIES="$2"
      shift; shift
      ;;
    --use-proxychains)
      USE_PROXYCHAINS=1
      shift
      ;;
    --tor)
      USE_TOR=1
      shift
      ;;
    --ssh-hops)
      SSH_HOPS="$2"
      shift; shift
      ;;
    --servers)
      SERVERS="$2"
      shift; shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Check required parameters
if [[ -z "$MNC" || -z "$MCC" || -z "$SSH_CONNECTION" ]]; then
  usage
fi

# Build server list
if [[ -n "$SERVERS" ]]; then
  IFS=',' read -ra SERVER_LIST <<< "$SERVERS"
else
  SERVER_LIST=("epdg.epc.mnc${MNC}.mcc${MCC}.pub.3gppnetwork.org")
fi

## Validate required commands
for cmd in ip sshuttle ssh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd"
    exit 1
  fi
done

# Cleanup function to ensure routes/rules are removed
cleanup() {
  if [[ -n "$SSHUTTLE_PID" ]]; then
    kill "$SSHUTTLE_PID" 2>/dev/null || true
    wait "$SSHUTTLE_PID" 2>/dev/null || true
  fi
  ip route flush table ${ROUTE_TABLE} 2>/dev/null || true
  ip rule del fwmark "${TMARK}" lookup "${ROUTE_TABLE}" 2>/dev/null || true
  ip -6 route flush table "${ROUTE_TABLE}" 2>/dev/null || true
  ip -6 rule del fwmark "${TMARK}" lookup "${ROUTE_TABLE}" 2>/dev/null || true
  if [[ -n "$TMP_PROXYCHAINS_CONF" && -f "$TMP_PROXYCHAINS_CONF" ]]; then
    rm -f "$TMP_PROXYCHAINS_CONF"
  fi
}

trap cleanup EXIT INT TERM

# If tor flag is set, add the default tor socks proxy
if [[ "$USE_TOR" -eq 1 ]]; then
  if [[ -n "$PROXIES" ]]; then
    PROXIES="${PROXIES},socks5://127.0.0.1:9050"
  else
    PROXIES="socks5://127.0.0.1:9050"
  fi
fi

# If proxies were provided, enable proxychains wrapping (we'll write a temp config)
WRAPPER_CMD=""
if [[ -n "$PROXIES" || "$USE_PROXYCHAINS" -eq 1 ]]; then
  if [[ -z "$PROXIES" ]]; then
    echo "No proxies specified; --use-proxychains will use system proxychains configuration."
  fi
  # Build temporary proxychains4 config if PROXIES provided
  if [[ -n "$PROXIES" ]]; then
    IFS=',' read -ra PROXY_LIST <<< "$PROXIES"
    TMP_PROXYCHAINS_CONF=$(mktemp /tmp/proxychains.XXXX.conf)
    cat > "$TMP_PROXYCHAINS_CONF" <<EOF
strict_chain
proxy_dns
[ProxyList]
EOF
    for p in "${PROXY_LIST[@]}"; do
      proto="${p%%:*}"
      rest="${p#*://}"
      host="${rest%%:*}"
      port="${rest##*:}"
      case "$proto" in
        socks5|socks4|http)
          echo "$proto $host $port" >> "$TMP_PROXYCHAINS_CONF"
          ;;
        *)
          echo "Unsupported proxy proto: $proto (use socks5/socks4/http)"
          ;;
      esac
    done
  fi

  if command -v proxychains4 >/dev/null 2>&1; then
    if [[ -n "$TMP_PROXYCHAINS_CONF" ]]; then
      WRAPPER_CMD="proxychains4 -f $TMP_PROXYCHAINS_CONF -q"
    else
      WRAPPER_CMD="proxychains4 -q"
    fi
  elif command -v proxychains >/dev/null 2>&1; then
    if [[ -n "$TMP_PROXYCHAINS_CONF" ]]; then
      WRAPPER_CMD="proxychains -f $TMP_PROXYCHAINS_CONF"
    else
      WRAPPER_CMD="proxychains"
    fi
  else
    echo "proxychains not found; install proxychains4 or proxychains to use proxy support"
    exit 1
  fi
fi

# Build SSH jump option if hops provided
SSH_EXTRA=""
if [[ -n "$SSH_HOPS" ]]; then
  # SSH -J accepts a comma-separated list of hops
  SSH_EXTRA="-J ${SSH_HOPS}"
fi

# Required by TPROXY (https://sshuttle.readthedocs.io/en/stable/tproxy.html)
ip route add local default dev lo table "${ROUTE_TABLE}"
ip rule add fwmark "${TMARK}" lookup "${ROUTE_TABLE}"
ip -6 route add local default dev lo table "${ROUTE_TABLE}"
ip -6 rule add fwmark "${TMARK}" lookup "${ROUTE_TABLE}"

# Build ssh command string for sshuttle
SSH_CMD="ssh ${SSH_EXTRA} -o PubkeyAuthentication=no"

# Construct and run sshuttle (optionally wrapped)
SERVER_LIST_JOINED="${SERVER_LIST[*]}"
SSHUTTLE_CMD="sshuttle -t \"${TMARK}\" --method=tproxy -r \"${SSH_CONNECTION}\" -e \"${SSH_CMD}\" --listen 0.0.0.0:0 ${SERVER_LIST_JOINED}"
if [[ -n "$WRAPPER_CMD" ]]; then
  FULL_CMD="$WRAPPER_CMD $SSHUTTLE_CMD"
else
  FULL_CMD="$SSHUTTLE_CMD"
fi

echo "Starting sshuttle..."
eval "$FULL_CMD &"
SSHUTTLE_PID=$!
wait "$SSHUTTLE_PID"

# cleanup will run via trap
