#!/usr/bin/env bash
# Run INSIDE Ubuntu Desktop after first boot, in a Terminal.
# Installs Flutter SDK, GTK dev deps, clones icefelix-window-manager,
# verifies Linux toolchain.

set -e

echo "===== icefelix-window-manager Linux VM provisioning ====="
echo ""

# 1. apt deps for Flutter Linux desktop builds
echo "[1/5] Installing build dependencies (sudo password may be required)..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl git unzip xz-utils zip wget \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libblkid-dev liblzma-dev \
  libsecret-1-dev libjsoncpp-dev libdecor-0-dev \
  libxkbcommon-dev libwayland-dev wayland-protocols

# 2. Flutter SDK
echo ""
echo "[2/5] Installing Flutter SDK (stable channel)..."
if [ ! -d "$HOME/flutter" ]; then
  git clone -b stable --depth 1 https://github.com/flutter/flutter.git "$HOME/flutter"
fi
if ! grep -q "flutter/bin" "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/flutter/bin:$HOME/.pub-cache/bin:$PATH"
flutter --version
flutter config --enable-linux-desktop --no-analytics > /dev/null

# 3. Melos
echo ""
echo "[3/5] Installing Melos..."
dart pub global activate melos > /dev/null 2>&1

# 4. Clone repo
echo ""
echo "[4/5] Cloning icefelix-window-manager..."
cd "$HOME"
if [ ! -d icefelix-window-manager ]; then
  git clone https://github.com/ICE-Felix/icefelix-window-manager.git
fi
cd icefelix-window-manager
melos bootstrap

# 5. Verify
echo ""
echo "[5/5] Verifying Linux toolchain..."
flutter doctor 2>&1 | grep -E "^\[|^   " | head -10
echo ""
echo "===== READY ====="
echo "Repo at: ~/icefelix-window-manager"
echo "Linux briefing: ~/icefelix-window-manager/docs/ADDING_LINUX.md"
echo ""
echo "Try:"
echo "  cd ~/icefelix-window-manager/packages/icefelix_window_manager"
echo "  flutter test                       # 72 unit tests"
echo "  cd example && flutter run -d linux # currently fails — no linux/ dir, this is v0.4 work"
