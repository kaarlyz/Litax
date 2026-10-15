# ⚡ Zenith: Bare-Metal Linux Latency Hardening & Workstation Tuner

> **Production-grade automation script for eliminating desktop micro-stutter, CPU burst spikes, frame drops, and input lag on Linux workstations.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Arch%20%7C%20Fedora%20%7C%20Debian%20%7C%20Ubuntu-orange.svg)](#)
[![Wayland Ready](https://img.shields.io/badge/Wayland-KDE%20Plasma%206%20%7C%20GNOME%20%7C%20Hyprland-brightgreen.svg)](#)

---

## 🚀 Quick Start (One-Liner)

### 1. Analyze Only (Non-Invasive Audit)
```bash
curl -fsSL https://raw.githubusercontent.com/kaarlyz/zenith-tune/main/zenith.sh | sudo bash -s -- --analyze
```

### 2. Apply Full Latency Hardening
```bash
curl -fsSL https://raw.githubusercontent.com/kaarlyz/zenith-tune/main/zenith.sh | sudo bash -s -- --apply
```

### 3. Clone & Interactive Execution
```bash
git clone https://github.com/kaarlyz/zenith-tune.git
cd zenith-tune
sudo ./zenith.sh
```

---

## 🎯 What Problems Does Zenith Solve?

| Linux Desktop Bottleneck | Standard Linux Default | Zenith Tuned Architecture |
| :--- | :--- | :--- |
| **ZRAM Compression Stutter** | `zstd` (high CPU compression latency) | **`lz4` (~4,500 MB/s per core, sub-microsecond swapping)** |
| **Dirty Disk Flush Freeze** | `vm.dirty_ratio = 10%` (>1 GB freeze spikes) | **`dirty_background_bytes = 64MB` continuous streaming** |
| **Btrfs SSD Metadata Churn** | `relatime`, default 30s commit | **`noatime`, `commit=120` (RAM coalescing on build files)** |
| **NVMe Flash Block Stalls** | `fstrim.timer` disabled on fresh installs | **Automated weekly TRIM + instant flash reclamation** |
| **Wayland Frame Delay** | KWin safe multi-frame buffer queue | **`LatencyPolicy=ExtremelyLow` (sub-millisecond deadline)** |
| **Browser Kinetic Scroll** | Step-based robotic mouse wheel ticks | **Firefox Mass-Spring-Damper (MSD) Physics + Brave GPU momentum** |
| **Flatpak Chat CPU Drain** | XWayland software rasterizer (100–300% CPU) | **Native Wayland + Direct DRI GPU acceleration** |
| **Network Bufferbloat** | Cubic congestion control + pfifo_fast | **BBR + CAKE + `tcp_slow_start_after_idle=0` (line-speed retention)** |
| **Audio Reaction Latency** | PipeWire 1024 samples (21.3 ms) | **512 samples (~10.6 ms with 64-sample floor)** |
| **Crash Lockups** | `systemd-coredump` freezes desktop on OOM/crash | **Coredump disk thrashing disabled (`Storage=none`)** |

---

## 🧩 Architectural Modules

### 1. Virtual Memory & ZRAM Engine
* Migrates `/dev/zram0` from `zstd` to `lz4`.
* Calibrates `vfs_cache_pressure = 100` so file metadata doesn't evict active apps into swap.
* Sets proactive background memory compaction (`compaction_proactiveness = 20`) to eliminate allocation pauses.

### 2. Storage & NVMe I/O Pipeline
* Configures `/etc/udev/rules.d/60-zenith-nvme.rules` with `scheduler=none` and `iostats=0` (disables per-request I/O accounting overhead).
* Patches `/etc/fstab` for Btrfs SSD mounts to enforce `noatime` and `commit=120`.

### 3. Display Frame Pacing & Wayland Compositing
* Sets KWin Plasma 6 `LatencyPolicy=ExtremelyLow` and aligns `MaxFPS` with detected monitor refresh rate (60Hz / 100Hz / 144Hz).
* Enables Adaptive Sync (VRR) on high-refresh external panels.
* Scales desktop transitions to `0.5x` for crisp Apple ProMotion responsiveness.

### 4. GPU Direct Framebuffer Scanout
* Enforces single-file memory-mapped shader caching (`MESA_DISK_CACHE_SINGLE_FILE=1`).
* Enables multi-threaded OpenGL dispatch (`mesa_glthread=true`).
* Injects universal Wayland toolkit variables across Qt 6, GTK 3/4, Electron, and SDL.

### 5. Application-Level Acceleration
* **Firefox**: Injects Mass-Spring-Damper (MSD) kinetic scroll physics, hardware WebRender, and 1 GB in-memory tab cache.
* **Brave**: Configures `--enable-smooth-scrolling` and zero-copy Wayland rasterization.
* **VS Code**: Enables Wayland window decorations and zero-copy GPU acceleration.
* **Flatpaks**: Automatically grants `--socket=wayland --device=dri` to Discord and WhatsApp clients.

### 6. Process Scheduling (Ananicy-cpp)
* Automatically installs and configures `ananicy-cpp` rules to elevate the compositor, text editor, and terminal (`nice -12` to `-3`) while restricting background chat wrappers to idle I/O priority.

---

## 🛠️ Requirements & Compatibility

* **Operating System**: Arch Linux, Fedora, Debian, Ubuntu, openSUSE, or any modern systemd Linux distribution.
* **Privileges**: Root (`sudo`) required for kernel and systemd unit configuration.
* **Shell**: Bash 4.4+.

---

## 📜 License

MIT License — Copyright (c) 2026 Eka Restu Syahputra ([@kaarlyz](https://github.com/kaarlyz)).
