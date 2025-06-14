#!/bin/bash

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

BDB_PREFIX="$(pwd)/db4"
COMPILED_DIR="$(pwd)/compiled_wallets_macos"

echo -e "${CYAN}============================="
echo -e " AdventureCoin macOS Builder"
echo -e "=============================${RESET}"

# 1. Build type
echo -e "\n${GREEN}Select build type:${RESET}"
echo "1) Daemon only"
echo "2) Daemon + Qt Wallet (full)"
echo "3) Qt Wallet only"
read -rp "Enter choice [1-3]: " BUILD_CHOICE

# 2. Strip?
read -rp $'\nDo you want to strip the binaries after build? (y/n): ' STRIP_BIN

# 3. Create .app + .dmg?
read -rp $'\nDo you want to create a .app and DMG for Qt Wallet? (y/n): ' MAKE_DMG

# --------------------------
# Dependencies
# --------------------------
echo -e "\n${GREEN}>>> Installing build dependencies via brew...${RESET}"
brew install automake berkeley-db@4 boost openssl libevent qt@5 protobuf qrencode miniupnpc zeromq pkg-config create-dmg

# --------------------------
# AdventureCoin source
# --------------------------
if [ ! -d "AdventureCoin" ]; then
    echo -e "${GREEN}>>> Cloning AdventureCoin...${RESET}"
    git clone https://github.com/AdventureCoin-ADVC/AdventureCoin.git
else
    echo -e "${GREEN}>>> Updating AdventureCoin...${RESET}"
    cd AdventureCoin && git pull && cd ..
fi

cd AdventureCoin

# --------------------------
# Patch configure.ac
# --------------------------
echo -e "${GREEN}>>> Patching configure.ac if needed...${RESET}"
PATCHED_CONFIGURE_AC="configure.ac"

if ! grep -q "LT_INIT" "$PATCHED_CONFIGURE_AC"; then
    sed -i.bak '/AM_INIT_AUTOMAKE/a\
AC_PROG_CC\
AC_PROG_CXX\
LT_INIT' "$PATCHED_CONFIGURE_AC"
    echo -e "${CYAN}✔ Patched configure.ac with AC_PROG_CC, AC_PROG_CXX, and LT_INIT${RESET}"
else
    echo -e "${CYAN}✔ configure.ac already patched${RESET}"
fi

# --------------------------
# Set environment paths based on architecture
# --------------------------
if [[ "$(uname -m)" == "arm64" ]]; then
    echo -e "${CYAN}✔ Detected Apple Silicon (arm64), using /opt/homebrew paths${RESET}"
    export PATH="/opt/homebrew/opt/berkeley-db@4/bin:/opt/homebrew/opt/qt@5/bin:$PATH"
    export LDFLAGS="-L/opt/homebrew/opt/berkeley-db@4/lib -L/opt/homebrew/opt/qt@5/lib"
    export CPPFLAGS="-I/opt/homebrew/opt/berkeley-db@4/include -I/opt/homebrew/opt/qt@5/include"
    export PKG_CONFIG_PATH="/opt/homebrew/opt/qt@5/lib/pkgconfig"
else
    echo -e "${CYAN}✔ Detected Intel macOS, using /usr/local paths${RESET}"
    export PATH="/usr/local/opt/berkeley-db@4/bin:/usr/local/opt/qt@5/bin:$PATH"
    export LDFLAGS="-L/usr/local/opt/berkeley-db@4/lib -L/usr/local/opt/qt@5/lib"
    export CPPFLAGS="-I/usr/local/opt/berkeley-db@4/include -I/usr/local/opt/qt@5/include"
    export PKG_CONFIG_PATH="/usr/local/opt/qt@5/lib/pkgconfig"
fi

chmod +x share/genbuild.sh
chmod +x autogen.sh
./autogen.sh

CONFIGURE_ARGS="--with-incompatible-bdb LDFLAGS=\"$LDFLAGS\" CPPFLAGS=\"$CPPFLAGS\""

if [[ "$BUILD_CHOICE" == "1" ]]; then
    eval ./configure $CONFIGURE_ARGS --without-gui
elif [[ "$BUILD_CHOICE" == "2" ]]; then
    eval ./configure $CONFIGURE_ARGS --with-gui=qt5
elif [[ "$BUILD_CHOICE" == "3" ]]; then
    eval ./configure $CONFIGURE_ARGS --disable-wallet --with-gui=qt5
fi

make -j"$(sysctl -n hw.ncpu)"

mkdir -p "$COMPILED_DIR"

[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/adventurecoind "$COMPILED_DIR/" 2>/dev/null || true
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/adventurecoin-cli "$COMPILED_DIR/" 2>/dev/null || true
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/adventurecoin-tx "$COMPILED_DIR/" 2>/dev/null || true
[[ "$BUILD_CHOICE" =~ [23] ]] && cp src/qt/adventurecoin-qt "$COMPILED_DIR/" 2>/dev/null || true

# --------------------------
# Strip Binaries
# --------------------------
if [[ "$STRIP_BIN" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}>>> Stripping binaries...${RESET}"
    strip "$COMPILED_DIR"/* || true
fi

# --------------------------
# .app Bundle and .dmg
# --------------------------
if [[ "$MAKE_DMG" =~ ^[Yy]$ && -f "$COMPILED_DIR/adventurecoin-qt" ]]; then
    echo -e "${GREEN}>>> Creating .app bundle...${RESET}"

    APP_BUNDLE_DIR="${COMPILED_DIR}/AdventureCoin-Qt.app"
    mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS"
    mkdir -p "$APP_BUNDLE_DIR/Contents/Resources"

    cp "$COMPILED_DIR/adventurecoin-qt" "$APP_BUNDLE_DIR/Contents/MacOS/"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>CFBundleExecutable</key>
  <string>adventurecoin-qt</string>
  <key>CFBundleIdentifier</key>
  <string>com.adventurecoin.wallet</string>
  <key>CFBundleName</key>
  <string>AdventureCoin</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>" > "$APP_BUNDLE_DIR/Contents/Info.plist"

    echo -e "${GREEN}>>> Running macdeployqt...${RESET}"
    macdeployqt "$APP_BUNDLE_DIR" || echo -e "${RED}✖ macdeployqt failed (ensure Qt is in PATH)${RESET}"

    echo -e "${GREEN}>>> Creating DMG...${RESET}"
    DMG_PATH="${COMPILED_DIR}/AdventureCoin-Wallet.dmg"
    create-dmg \
      --volname "AdventureCoin Wallet" \
      --window-pos 200 120 \
      --window-size 600 300 \
      --icon-size 100 \
      --icon "AdventureCoin-Qt.app" 175 120 \
      --hide-extension "AdventureCoin-Qt.app" \
      --app-drop-link 425 120 \
      "$DMG_PATH" \
      "$COMPILED_DIR"

    echo -e "${GREEN}✔ DMG created at: $DMG_PATH${RESET}"
fi

echo -e "\n${CYAN}✔ Build complete! Binaries in: ${COMPILED_DIR}${RESET}"
