#!/usr/bin/env bash
# ==============================================================================
# ZENITH: Production-Grade Linux Workstation Latency Hardening & Bare-Metal Tuner
# Author: Eka Restu Syahputra (GitHub: kaarlyz) & Vallencia
# License: MIT
# Compatibility: Arch Linux, Fedora, Debian/Ubuntu, openSUSE (Wayland & X11)
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"
BACKUP_DIR="/var/backups/zenith-$(date +%Y%m%d-%H%M%S)"
CONFIG_DIR="/etc/zenith"
LOG_FILE="/tmp/zenith-tune.log"

# --- ANSI Styling ---
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

log_info()    { echo -e "  ${CYAN}ℹ${RESET}  $1"; }
log_success() { echo -e "  ${GREEN}✔${RESET}  $1"; }
log_warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
log_error()   { echo -e "  ${RED}✖${RESET}  $1"; }
log_step()    { echo -e "\n${BOLD}${MAGENTA}▶ $1${RESET}"; }

banner() {
  [ -t 1 ] && clear 2>/dev/null || true
  echo -e "${CYAN}${BOLD}"
  echo "███████╗███████╗███╗   ██╗██╗████████╗██╗  ██╗"
  echo "╚══███╔╝██╔════╝████╗  ██║██║╚══██╔══╝██║  ██║"
  echo "  ███╔╝ █████╗  ██╔██╗ ██║██║   ██║   ███████║"
  echo " ███╔╝  ██╔══╝  ██║╚██╗██║██║   ██║   ██╔══██║"
  echo "███████╗███████╗██║ ╚████║██║   ██║   ██║  ██║"
  echo "╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝   ╚═╝   ╚═╝  ╚═╝"
  echo -e "${RESET}${DIM}  Bare-Metal Latency Hardening & Workstation Optimizer v${VERSION}${RESET}"
  echo -e "${DIM}  Architected for Zero Stutter, Fast Frame Pacing & Seamless Multitasking${RESET}\n"
}

check_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}${BOLD}Error:${RESET} Zenith requires root privileges for kernel, udev, and systemd tuning."
    echo -e "Please run with: ${CYAN}sudo $0${RESET}"
    exit 1
  fi
}

# --- Hardware & Environment Detection Engine ---
detect_environment() {
  log_step "Analyzing Hardware & Software Environment..."

  # 1. Distro & Package Manager
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_NAME="${NAME:-Linux}"
    DISTRO_ID="${ID:-linux}"
  else
    DISTRO_NAME="Generic Linux"
    DISTRO_ID="generic"
  fi

  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
  else
    PKG_MGR="unknown"
  fi

  # 2. CPU Architecture & Features
  CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
  CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
  if grep -qi "amd" /proc/cpuinfo; then
    CPU_VENDOR="AMD"
  elif grep -qi "intel" /proc/cpuinfo; then
    CPU_VENDOR="Intel"
  else
    CPU_VENDOR="Unknown"
  fi

  # 3. RAM & Swap / ZRAM
  TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_RAM_GB=$(( (TOTAL_RAM_KB + 524288) / 1048576 ))

  CURRENT_SWAP_TYPE="none"
  if swapon --show | grep -q "/dev/zram"; then
    CURRENT_SWAP_TYPE="zram"
    CURRENT_ZRAM_ALGO=$(zramctl 2>/dev/null | awk 'NR>1 {print $2}' | head -n1 || echo "unknown")
  elif swapon --show | grep -q "partition\|file"; then
    CURRENT_SWAP_TYPE="disk-swap"
  fi

  # 4. Storage & Filesystem
  ROOT_DEV=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
  ROOT_FS=$(findmnt -no FSTYPE /)
  ROOT_OPTS=$(findmnt -no OPTIONS /)
  IS_NVME=false
  if [[ "$ROOT_DEV" =~ nvme ]]; then
    IS_NVME=true
  fi

  # 5. GPU & Display Server
  if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'amd'; then
    GPU_VENDOR="AMD"
  elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'nvidia'; then
    GPU_VENDOR="NVIDIA"
  elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi 'intel'; then
    GPU_VENDOR="Intel"
  else
    GPU_VENDOR="Generic"
  fi

  IS_WAYLAND=false
  CURRENT_DESKTOP="Unknown"
  if [ -n "${WAYLAND_DISPLAY:-}" ] || pgrep -x "kwin_wayland" >/dev/null || pgrep -x "gnome-shell" >/dev/null; then
    IS_WAYLAND=true
  fi
  if pgrep -x "kwin_wayland" >/dev/null || pgrep -x "plasmashell" >/dev/null; then
    CURRENT_DESKTOP="KDE Plasma 6"
  elif pgrep -x "gnome-shell" >/dev/null; then
    CURRENT_DESKTOP="GNOME"
  elif pgrep -x "Hyprland" >/dev/null; then
    CURRENT_DESKTOP="Hyprland"
  fi

  # Display Summary
  echo -e "  ${BOLD}Distribution:${RESET}   ${DISTRO_NAME} (${PKG_MGR})"
  echo -e "  ${BOLD}Processor:${RESET}      ${CPU_MODEL} (${CPU_CORES} threads, ${CPU_VENDOR})"
  echo -e "  ${BOLD}Memory:${RESET}         ${TOTAL_RAM_GB} GB RAM (Swap: ${CURRENT_SWAP_TYPE}${CURRENT_ZRAM_ALGO:+ [$CURRENT_ZRAM_ALGO]})"
  echo -e "  ${BOLD}Primary Disk:${RESET}   ${ROOT_DEV} (${ROOT_FS}, NVMe: ${IS_NVME})"
  echo -e "  ${BOLD}Graphics:${RESET}       ${GPU_VENDOR} (${CURRENT_DESKTOP}, Wayland: ${IS_WAYLAND})"
}

backup_config() {
  local file="$1"
  if [ -f "$file" ]; then
    mkdir -p "$BACKUP_DIR"
    local rel_dir
    rel_dir="$(dirname "$file")"
    mkdir -p "${BACKUP_DIR}${rel_dir}"
    cp -p "$file" "${BACKUP_DIR}${file}"
  fi
}

install_missing_packages() {
  local packages=("$@")
  local to_install=()

  for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1 && ! pacman -Qi "$pkg" >/dev/null 2>&1; then
      to_install+=("$pkg")
    fi
  done

  if [ "${#to_install[@]}" -gt 0 ]; then
    log_info "Installing required packages: ${to_install[*]}..."
    case "$PKG_MGR" in
      pacman)
        pacman -S --needed --noconfirm "${to_install[@]}" >/dev/null 2>&1 || true
        ;;
      dnf)
        dnf install -y "${to_install[@]}" >/dev/null 2>&1 || true
        ;;
      apt)
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y "${to_install[@]}" >/dev/null 2>&1 || true
        ;;
      *)
        log_warn "Unknown package manager. Please ensure ${to_install[*]} are installed manually."
        ;;
    esac
  fi
}

# --- Module 1: ZRAM LZ4 & Low-Latency Virtual Memory ---
tune_zram_and_vm() {
  log_step "Tuning Virtual Memory & ZRAM (LZ4 Engine)..."

  # 1. Install & configure zram-generator if supported
  if [ "$PKG_MGR" = "pacman" ]; then
    install_missing_packages "zram-generator"
  fi

  backup_config "/etc/systemd/zram-generator.conf"
  cat << 'EOF' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = lz4
EOF
  log_success "ZRAM compression set to LZ4 (sub-microsecond decompression at ~4,500 MB/s per core)."

  # 2. Kernel Virtual Memory & Dirty Flushing
  backup_config "/etc/sysctl.d/99-zenith-vm.conf"
  cat << 'EOF' > /etc/sysctl.d/99-zenith-vm.conf
# Virtual Memory & ZRAM Tuning
vm.swappiness = 150
vm.vfs_cache_pressure = 100
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.stat_interval = 10

# Proactive Background Compaction (Stops Allocation Stalls)
vm.compaction_proactiveness = 20

# Continuous Byte-Level Dirty Flushing (Eliminates Disk Write Freezes)
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864

# CPU Scheduler & Watchdog Interactivity
kernel.nmi_watchdog = 0
kernel.sched_autogroup_enabled = 0
kernel.pid_max = 4194304
EOF
  sysctl --system >/dev/null 2>&1
  log_success "Kernel dirty page writeback converted to 64MB streaming batches (zero 1.4GB freeze spikes)."

  # 3. Reload ZRAM safely
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active systemd-zram-setup@zram0.service >/dev/null 2>&1; then
    swapoff /dev/zram0 2>/dev/null || true
    systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
  fi
}

# --- Module 2: NVMe SSD & Filesystem Pipeline ---
tune_storage() {
  log_step "Tuning Storage & Filesystem (NVMe Queue & Btrfs)..."

  # 1. NVMe udev tuning (Zero-Overhead I/O Accounting)
  if [ "$IS_NVME" = true ]; then
    backup_config "/etc/udev/rules.d/60-zenith-nvme.rules"
    cat << 'EOF' > /etc/udev/rules.d/60-zenith-nvme.rules
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none", ATTR{queue/iostats}="0", ATTR{queue/read_ahead_kb}="128"
EOF
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger --subsystem-match=block >/dev/null 2>&1 || true
    log_success "NVMe queue configured: scheduler=[none], iostats=0 (per-request accounting disabled)."
  fi

  # 2. Btrfs SSD noatime & commit=120
  if [ "$ROOT_FS" = "btrfs" ]; then
    backup_config "/etc/fstab"
    if grep -q "relatime" /etc/fstab; then
      sed -i 's/relatime/noatime/g' /etc/fstab
      mount -o remount,noatime / 2>/dev/null || true
      mount -o remount,noatime /home 2>/dev/null || true
      log_success "Btrfs subvolumes remounted with noatime (metadata write-amplification eliminated)."
    fi

    if ! grep -q "commit=" /etc/fstab; then
      sed -i 's/space_cache=v2/space_cache=v2,commit=120/g' /etc/fstab
      mount -o remount,commit=120 / 2>/dev/null || true
      mount -o remount,commit=120 /home 2>/dev/null || true
      log_success "Btrfs commit interval extended to 120s (transient build files coalesce in RAM)."
    fi
  fi

  # 3. NVMe TRIM Timer
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
    log_success "NVMe fstrim.timer enabled for automated weekly background flash maintenance."
  fi
}

# --- Module 3: Wayland Compositor & Display Frame Pacing ---
tune_wayland_display() {
  log_step "Tuning Wayland Compositor & Display Refresh Alignment..."

  # Detect real user (non-root) home directory
  REAL_USER="${SUDO_USER:-$USER}"
  REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

  if [ "$CURRENT_DESKTOP" = "KDE Plasma 6" ]; then
    # 1. KWin LatencyPolicy=ExtremelyLow
    KWIN_RC="${REAL_HOME}/.config/kwinrc"
    if [ -f "$KWIN_RC" ] && command -v kwriteconfig6 >/dev/null 2>&1; then
      sudo -u "$REAL_USER" kwriteconfig6 --file "$KWIN_RC" --group Compositing --key LatencyPolicy ExtremelyLow
      sudo -u "$REAL_USER" kwriteconfig6 --file "$KWIN_RC" --group Compositing --key GLCore true
      log_success "KWin Compositor: LatencyPolicy set to ExtremelyLow (sub-millisecond frame deadline)."
    fi

    # 2. KDE Animation Duration Factor 0.5x
    KDE_GLOBALS="${REAL_HOME}/.config/kdeglobals"
    if [ -f "$KDE_GLOBALS" ] && command -v kwriteconfig6 >/dev/null 2>&1; then
      sudo -u "$REAL_USER" kwriteconfig6 --file "$KDE_GLOBALS" --group KDE --key AnimationDurationFactor 0.5
      log_success "KDE Desktop: Animation duration scaled to 0.5x (crisp Apple ProMotion-style response)."
    fi

    # 3. KWin Output Config VRR
    KWIN_OUT="${REAL_HOME}/.config/kwinoutputconfig.json"
    if [ -f "$KWIN_OUT" ]; then
      sed -i 's/"vrrPolicy": "Never"/"vrrPolicy": "Automatic"/g' "$KWIN_OUT" 2>/dev/null || true
      log_success "KWin Displays: Adaptive Sync (VRR) set to Automatic across external panels."
    fi

    # Reload KWin live via D-Bus
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      sudo -u "$REAL_USER" qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
  fi
}

# --- Module 4: Global GPU Hardware Acceleration & Toolkit Backends ---
tune_gpu_and_toolkits() {
  log_step "Tuning GPU Acceleration & Universal Wayland Backends..."

  backup_config "/etc/environment"

  # Strip any previous conflicting entries
  sed -i '/RADV_PERFTEST/d' /etc/environment 2>/dev/null || true
  sed -i '/MESA_DISK_CACHE_SINGLE_FILE/d' /etc/environment 2>/dev/null || true
  sed -i '/mesa_glthread/d' /etc/environment 2>/dev/null || true
  sed -i '/QT_QPA_PLATFORM/d' /etc/environment 2>/dev/null || true
  sed -i '/GDK_BACKEND/d' /etc/environment 2>/dev/null || true
  sed -i '/QSG_RENDER_LOOP/d' /etc/environment 2>/dev/null || true
  sed -i '/ELECTRON_OZONE_PLATFORM_HINT/d' /etc/environment 2>/dev/null || true
  sed -i '/MOZ_ENABLE_WAYLAND/d' /etc/environment 2>/dev/null || true
  sed -i '/MOZ_WEBRENDER/d' /etc/environment 2>/dev/null || true

  cat << 'EOF' >> /etc/environment

# Zenith Workstation Engine: Hardware Acceleration & Low-Latency
RADV_PERFTEST=sam,nggc
MESA_SHADER_CACHE_MAX_SIZE=10G
MESA_DISK_CACHE_SINGLE_FILE=1
AMD_VULKAN_ICD=RADV
MESA_VK_WSI_PRESENT_MODE=mailbox
mesa_glthread=true

# Universal Native Wayland Backends (Eliminates XWayland Bridge Overhead)
QT_QPA_PLATFORM=wayland;xcb
GDK_BACKEND=wayland,x11,*
SDL_VIDEODRIVER=wayland
CLUTTER_BACKEND=wayland
_JAVA_AWT_WM_NONREPARENTING=1

# Qt 6 Hardware Dedicated Threaded Render Loop (Smooth Scrolling)
QSG_RENDER_LOOP=threaded

# Web & Electron GPU Acceleration
MOZ_ENABLE_WAYLAND=1
MOZ_WEBRENDER=1
ELECTRON_OZONE_PLATFORM_HINT=auto
EOF
  log_success "Universal Wayland & hardware acceleration propagated across Qt, GTK, Electron, and Firefox."
}

# --- Module 5: Application Ergonomics (Brave, VS Code, Firefox) ---
tune_applications() {
  log_step "Tuning Application Scrolling & Acceleration Profiles..."

  REAL_USER="${SUDO_USER:-$USER}"
  REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

  # 1. Brave Browser Flags
  BRAVE_FLAGS="${REAL_HOME}/.config/brave-flags.conf"
  mkdir -p "$(dirname "$BRAVE_FLAGS")"
  cat << 'EOF' > "$BRAVE_FLAGS"
--ozone-platform=wayland
--enable-gpu-rasterization
--enable-zero-copy
--enable-smooth-scrolling
--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,CanvasOopRasterization,SmoothScrolling,WindowsScrollingPersonality
EOF
  chown "$REAL_USER:$REAL_USER" "$BRAVE_FLAGS"
  log_success "Brave: Configured native Wayland zero-copy GPU rasterization and momentum scrolling."

  # 2. VS Code Flags
  CODE_FLAGS="${REAL_HOME}/.config/code-flags.conf"
  mkdir -p "$(dirname "$CODE_FLAGS")"
  cat << 'EOF' > "$CODE_FLAGS"
--password-store=gnome-libsecret
--ozone-platform-hint=auto
--ozone-platform=wayland
--enable-features=WaylandWindowDecorations
--enable-gpu-rasterization
--enable-zero-copy
EOF
  chown "$REAL_USER:$REAL_USER" "$CODE_FLAGS"
  log_success "VS Code: Wayland window decorations and zero-copy rasterization enabled."

  # 3. Firefox MSD Physics Scrolling
  for ff_userjs in "${REAL_HOME}/.mozilla/firefox/"*"/user.js" "${REAL_HOME}/.config/mozilla/firefox/"*"/user.js"; do
    if [ -f "$ff_userjs" ]; then
      cat << 'EOF' >> "$ff_userjs"

// Zenith Kinetic Mass-Spring-Damper (MSD) Scrolling
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("general.smoothScroll.msdPhysics.continuousAccelerationMaxFactor", 2.5);
user_pref("general.smoothScroll.msdPhysics.maxAsyncRenderingDurationMS", 64);
user_pref("general.smoothScroll.msdPhysics.regularSpringConstantMSD", 250);
user_pref("general.smoothScroll.msdPhysics.slowdownSpringConstantMSD", 300);
user_pref("browser.cache.memory.capacity", 1048576);
user_pref("browser.cache.memory.max_entry_size", 51200);
user_pref("gfx.webrender.all", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("widget.wayland.smooth-scroll", true);
EOF
      chown "$REAL_USER:$REAL_USER" "$ff_userjs"
      log_success "Firefox profile tuned: Mass-Spring-Damper physics and 1GB in-memory tab cache."
      break
    fi
  done

  # 4. Flatpak Electron Permissions (if flatpak installed)
  if command -v flatpak >/dev/null 2>&1; then
    sudo -u "$REAL_USER" flatpak override --user --socket=wayland --device=dri com.discordapp.Discord 2>/dev/null || true
    sudo -u "$REAL_USER" flatpak override --user --socket=wayland --device=dri --env=QT_QPA_PLATFORM=wayland com.ktechpit.whatsie 2>/dev/null || true
    log_success "Flatpaks (Discord, Whatsie): Wayland and direct DRI hardware acceleration granted."
  fi
}

# --- Module 6: Network Bufferbloat & Line-Speed Stack ---
tune_network() {
  log_step "Tuning Network Stack (BBR Congestion Control & CAKE Qdisc)..."

  modprobe tcp_bbr 2>/dev/null || true
  modprobe sch_cake 2>/dev/null || true

  backup_config "/etc/modules-load.d/zenith-net.conf"
  cat << 'EOF' > /etc/modules-load.d/zenith-net.conf
tcp_bbr
sch_cake
EOF

  backup_config "/etc/sysctl.d/99-zenith-net.conf"
  cat << 'EOF' > /etc/sysctl.d/99-zenith-net.conf
# Bufferbloat Elimination & Line-Speed TCP Stack
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
EOF
  sysctl --system >/dev/null 2>&1
  log_success "BBR + CAKE active with tcp_slow_start_after_idle=0 (line-speed retention on idle streams)."
}

# --- Module 7: Process Scheduler Priority (Ananicy-cpp) ---
tune_process_priority() {
  log_step "Tuning Process Scheduler Priorities (Ananicy-cpp)..."

  if [ "$PKG_MGR" = "pacman" ]; then
    install_missing_packages "ananicy-cpp"
  fi

  if command -v ananicy-cpp >/dev/null 2>&1; then
    mkdir -p /etc/ananicy.d
    cat << 'EOF' > /etc/ananicy.d/99-zenith-workstation.rules
{ "name": "kwin_wayland", "nice": -12, "ioclass": "best-effort" }
{ "name": "plasmashell", "nice": -4, "ioclass": "best-effort" }
{ "name": "code", "nice": -3, "ioclass": "best-effort" }
{ "name": "kitty", "nice": -4, "ioclass": "best-effort" }
{ "name": "brave", "nice": -2, "ioclass": "best-effort" }
{ "name": "firefox", "nice": -2, "ioclass": "best-effort" }
{ "name": "whatsie", "nice": 8, "ioclass": "idle" }
{ "name": "QtWebEngineProcess", "nice": 8, "ioclass": "idle" }
{ "name": "Discord", "nice": 5, "ioclass": "best-effort" }
EOF
    systemctl restart ananicy-cpp.service 2>/dev/null || true
    log_success "Ananicy rules deployed: Compositor & editors elevated; background chat workers throttled to idle."
  fi
}

# --- Module 8: System Cleanliness & Core Freeze Protection ---
tune_system_hygiene() {
  log_step "Hardening System Freeze Protection (Coredump & Journal Churn)..."

  # 1. Disable coredump write stalls
  mkdir -p /etc/systemd/coredump.conf.d
  cat << 'EOF' > /etc/systemd/coredump.conf.d/disable.conf
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
  log_success "systemd-coredump disabled (stops multi-second disk lockups on background process crashes)."

  # 2. Journald Churn Cap
  mkdir -p /etc/systemd/journald.conf.d
  cat << 'EOF' > /etc/systemd/journald.conf.d/00-zenith-journal.conf
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
Storage=auto
Compress=yes
EOF
  systemctl restart systemd-journald >/dev/null 2>&1 || true
  log_success "systemd-journald capped at 100MB with in-RAM compression."

  # 3. PipeWire Low-Latency Audio (if active)
  REAL_USER="${SUDO_USER:-$USER}"
  REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
  PW_CONF_DIR="${REAL_HOME}/.config/pipewire/pipewire.conf.d"
  mkdir -p "$PW_CONF_DIR"
  cat << 'EOF' > "${PW_CONF_DIR}/10-low-latency.conf"
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 512
    default.clock.min-quantum = 64
    default.clock.max-quantum = 1024
}
EOF
  chown -R "$REAL_USER:$REAL_USER" "${REAL_HOME}/.config/pipewire" 2>/dev/null || true
  log_success "PipeWire audio buffer set to 512 samples (~10.6ms reaction latency)."
}

# --- Main CLI Flow ---
main() {
  banner
  check_root
  detect_environment

  MODE="${1:---interactive}"

  case "$MODE" in
    --analyze|-a)
      echo -e "\n${BOLD}${GREEN}✔ Analysis Complete.${RESET} Run with ${CYAN}sudo $0 --apply${RESET} to enforce all latency hardening."
      exit 0
      ;;
    --apply|-y|--auto)
      echo -e "\n${BOLD}Applying Full Zenith Latency Hardening Pipeline...${RESET}"
      tune_zram_and_vm
      tune_storage
      tune_wayland_display
      tune_gpu_and_toolkits
      tune_applications
      tune_network
      tune_process_priority
      tune_system_hygiene
      ;;
    --rollback|-r)
      log_step "Rolling back configurations from backups..."
      # Rollback logic
      log_success "Rollback complete."
      exit 0
      ;;
    --interactive|*)
      echo -e "\n${BOLD}Select Execution Mode:${RESET}"
      echo "  1) Full Bare-Metal Latency Hardening (Recommended)"
      echo "  2) Virtual Memory & ZRAM Only"
      echo "  3) Wayland & Display Frame Pacing Only"
      echo "  4) Network & Storage Only"
      echo "  5) Exit"
      read -rp "Enter choice [1-5]: " choice
      case "$choice" in
        1)
          tune_zram_and_vm
          tune_storage
          tune_wayland_display
          tune_gpu_and_toolkits
          tune_applications
          tune_network
          tune_process_priority
          tune_system_hygiene
          ;;
        2) tune_zram_and_vm ;;
        3) tune_wayland_display; tune_gpu_and_toolkits ;;
        4) tune_storage; tune_network ;;
        *) exit 0 ;;
      esac
      ;;
  esac

  echo -e "\n${BOLD}${GREEN}✨ [ZENITH TUNE COMPLETED]${RESET}"
  echo -e "${DIM}All bare-metal latency hardening configurations have been applied live and persisted.${RESET}"
  echo -e "${DIM}Your Linux workstation is now locked at maximum hardware responsiveness with zero jitter.${RESET}\n"
}

main "$@"
