#!/usr/bin/env bash
# =============================================================================
# shairport-sync AP2 Installer for Linux Mint 22.x (Ubuntu 24.04 Noble base)
# =============================================================================
# Usage:
#   sudo bash install.sh [OPTIONS]
#
# Options:
#   --name NAME    Set the AirPlay receiver name (default: hostname)
#   --output TYPE  Audio output type: alsa (default), pulseaudio, pipewire
#   --help         Show this help message
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${GREEN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Defaults / Argument parsing
# ---------------------------------------------------------------------------
# Resolve script location before any cd commands change the working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AIRPLAY_NAME="$(hostname)"
AUDIO_OUTPUT="alsa"
SPS_REPO_URL="https://github.com/kuykejoe/shairport-sync.git"
NQPTP_REPO_URL="https://github.com/mikebrady/nqptp.git"
BUILD_DIR="/tmp/sps-ap2-build"

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)    AIRPLAY_NAME="$2"; shift 2 ;;
        --output)  AUDIO_OUTPUT="$2"; shift 2 ;;
        --help|-h) usage ;;
        *)         error "Unknown option: $1. Run with --help for usage." ;;
    esac
done

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] && error "This script must be run as root or with sudo."

# Detect OS base
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    error "Cannot detect OS. /etc/os-release not found."
fi

# Accept Mint 22.x (noble base) or Ubuntu 24.04 directly
if [[ "$ID" == "linuxmint" && "${VERSION_ID%%.*}" -ge 22 ]]; then
    DISTRO="mint22"
elif [[ "$ID" == "ubuntu" && "${VERSION_ID%%.*}" -ge 24 ]]; then
    DISTRO="ubuntu24"
else
    warn "Detected OS: $PRETTY_NAME"
    warn "This installer targets Linux Mint 22+ or Ubuntu 24.04+."
    read -rp "Continue anyway? [y/N] " yn
    [[ "${yn,,}" == "y" ]] || exit 0
    DISTRO="unknown"
fi

# Validate audio output
case "$AUDIO_OUTPUT" in
    alsa|pulseaudio|pipewire) ;;
    *) error "Invalid --output value '$AUDIO_OUTPUT'. Choose: alsa, pulseaudio, pipewire" ;;
esac

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║     shairport-sync  ·  AirPlay 2  ·  Installer      ║"
echo "  ║     Target: $(printf '%-42s' "$PRETTY_NAME")║"
echo "  ║     Name:   $(printf '%-42s' "$AIRPLAY_NAME")║"
echo "  ║     Output: $(printf '%-42s' "$AUDIO_OUTPUT")║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---------------------------------------------------------------------------
# Step 1 – Install build dependencies
# ---------------------------------------------------------------------------
step "1/6  Installing build dependencies"

COMMON_PKGS=(
    build-essential git autoconf automake libtool pkg-config
    libpopt-dev libconfig-dev libssl-dev libsoxr-dev
    libavahi-client-dev avahi-daemon
    libplist-dev libsodium-dev uuid-dev libgcrypt-dev
    libavutil-dev libavcodec-dev libavformat-dev
    xxd xmltoman
)

ALSA_PKGS=(libasound2-dev)
PULSE_PKGS=(libpulse-dev)
PIPE_PKGS=(libpipewire-0.3-dev)

case "$AUDIO_OUTPUT" in
    alsa)       OUTPUT_PKGS=("${ALSA_PKGS[@]}") ;;
    pulseaudio) OUTPUT_PKGS=("${PULSE_PKGS[@]}") ;;
    pipewire)   OUTPUT_PKGS=("${PIPE_PKGS[@]}") ;;
esac

apt-get update -qq
apt-get install -y --no-install-recommends "${COMMON_PKGS[@]}" "${OUTPUT_PKGS[@]}"
success "Dependencies installed."

# ---------------------------------------------------------------------------
# Step 2 – Build & install nqptp  (required for AirPlay 2 timing)
# ---------------------------------------------------------------------------
step "2/6  Building nqptp (AirPlay 2 timing daemon)"

rm -rf "$BUILD_DIR/nqptp"
git clone --depth 1 "$NQPTP_REPO_URL" "$BUILD_DIR/nqptp"
cd "$BUILD_DIR/nqptp"
autoreconf -fi
./configure --with-systemd-startup
make -j"$(nproc)"
make install
success "nqptp installed."

# ---------------------------------------------------------------------------
# Step 3 – Build shairport-sync with AirPlay 2
# ---------------------------------------------------------------------------
step "3/6  Building shairport-sync with AirPlay 2 support"

# Resolve source: use the repo this script lives in (if available),
# otherwise clone the fork fresh.
SPS_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SPS_ROOT/configure.ac" ]]; then
    info "Using local source at $SPS_ROOT"
    cd "$SPS_ROOT"
else
    info "Cloning source from $SPS_REPO_URL"
    rm -rf "$BUILD_DIR/shairport-sync"
    git clone --depth 1 "$SPS_REPO_URL" "$BUILD_DIR/shairport-sync"
    cd "$BUILD_DIR/shairport-sync"
fi

# Build configure flags
CONFIGURE_FLAGS=(
    --sysconfdir=/etc
    --with-soxr
    --with-avahi
    --with-ssl=openssl
    --with-systemd-startup
    --with-airplay-2
)

case "$AUDIO_OUTPUT" in
    alsa)       CONFIGURE_FLAGS+=(--with-alsa) ;;
    pulseaudio) CONFIGURE_FLAGS+=(--with-pa) ;;
    pipewire)   CONFIGURE_FLAGS+=(--with-pw) ;;
esac

autoreconf -fi
./configure "${CONFIGURE_FLAGS[@]}"
make -j"$(nproc)"
make install
success "shairport-sync installed."

# ---------------------------------------------------------------------------
# Step 4 – Enable & start nqptp service
# ---------------------------------------------------------------------------
step "4/6  Enabling nqptp service"
systemctl daemon-reload
systemctl enable nqptp
systemctl restart nqptp
success "nqptp service running."

# ---------------------------------------------------------------------------
# Step 5 – Write a baseline shairport-sync config
# ---------------------------------------------------------------------------
step "5/6  Writing configuration"

CONFIG_FILE="/etc/shairport-sync.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    warn "Existing config found at $CONFIG_FILE — backing up to ${CONFIG_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

cat > "$CONFIG_FILE" << EOF
// shairport-sync.conf
// Generated by installer/install.sh  –  $(date)
// Full option reference: https://github.com/mikebrady/shairport-sync/blob/master/man/shairport-sync.conf.5.xml

general = {
  name = "${AIRPLAY_NAME}";       // AirPlay receiver name shown on iOS / macOS
  output_backend = "${AUDIO_OUTPUT}";
};

alsa = {
  // Uncomment and set to your card's mixer control name if volume control is desired
  // mixer_control_name = "Master";
};

// Uncomment to enable multi-room / AirPlay 2 group playback logging
// diagnostics = {
//   log_verbosity = 1;
// };
EOF

success "Config written to $CONFIG_FILE"

# ---------------------------------------------------------------------------
# Step 6 – Enable & start shairport-sync service
# ---------------------------------------------------------------------------
step "6/6  Enabling shairport-sync service"
systemctl daemon-reload
systemctl enable shairport-sync
systemctl restart shairport-sync

# Give it a moment to start
sleep 2

if systemctl is-active --quiet shairport-sync; then
    success "shairport-sync is running!"
else
    warn "shairport-sync did not start cleanly. Check: journalctl -u shairport-sync -n 30"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}Installation complete!${NC}"
echo ""
echo -e "  AirPlay receiver name : ${BOLD}${AIRPLAY_NAME}${NC}"
echo -e "  Audio output          : ${BOLD}${AUDIO_OUTPUT}${NC}"
echo -e "  Config file           : ${BOLD}${CONFIG_FILE}${NC}"
echo -e "  Service status        : ${BOLD}systemctl status shairport-sync${NC}"
echo -e "  Logs                  : ${BOLD}journalctl -u shairport-sync -f${NC}"
echo ""
echo "  Open Music / AirPlay on an Apple device — '${AIRPLAY_NAME}' should appear."
echo ""
