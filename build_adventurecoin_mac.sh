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

# --------------------------
# 1. Build type
# --------------------------
echo -e "\n${GREEN}Select build type:${RESET}"
echo "1) Daemon only"
echo "2) Daemon + Qt Wallet (full)"
echo "3) Qt Wallet only"
read -rp "Enter choice [1-3]: " BUILD_CHOICE

# --------------------------
# 2. Strip?
# --------------------------
read -rp $'\nDo you want to strip the binaries after build? (y/n): ' STRIP_BIN

# --------------------------
# 3. Create .app + .dmg?
# --------------------------
read -rp $'\nDo you want to create a .app and DMG for Qt Wallet? (y/n): ' MAKE_DMG

# --------------------------
# Environment PATH fallback
# --------------------------
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# --------------------------
# Dependencies
# --------------------------
echo -e "\n${GREEN}>>> Installing build dependencies via brew...${RESET}"
brew install automake libtool berkeley-db@4 boost openssl libevent qt@5 qrencode miniupnpc zeromq pkg-config create-dmg

# --------------------------
# Install Protobuf 3.6.1 (Legacy compatible)
# --------------------------
PROTOBUF_DIR="$HOME/local/protobuf-3.6.1"
PROTOBUF_TAR="protobuf-cpp-3.6.1.tar.gz"
PROTOBUF_URL="https://github.com/protocolbuffers/protobuf/releases/download/v3.6.1/${PROTOBUF_TAR}"

if [ ! -f "$PROTOBUF_DIR/bin/protoc" ]; then
    echo -e "${GREEN}>>> Installing Protobuf 3.6.1 (compatible version)...${RESET}"
    mkdir -p "$HOME/local"
    CUR_DIR="$(pwd)"
    cd /tmp
    curl -LO "$PROTOBUF_URL"
    tar -xvf "$PROTOBUF_TAR"
    cd protobuf-3.6.1
    ./configure --prefix="$PROTOBUF_DIR"
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
    echo -e "${CYAN}✔ Installed Protobuf 3.6.1 to $PROTOBUF_DIR${RESET}"
    cd "$CUR_DIR"
else
    echo -e "${CYAN}✔ Protobuf 3.6.1 already installed at $PROTOBUF_DIR${RESET}"
fi

# --------------------------
# Fix missing protobuf.pc if needed
# --------------------------
if [ ! -f "$PROTOBUF_DIR/lib/pkgconfig/protobuf.pc" ]; then
    echo -e "${GREEN}>>> Creating missing protobuf.pc...${RESET}"
    mkdir -p "$PROTOBUF_DIR/lib/pkgconfig"
    cat > "$PROTOBUF_DIR/lib/pkgconfig/protobuf.pc" <<EOF
prefix=$PROTOBUF_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Protocol Buffers
Description: Google's Data Interchange Format
Version: 3.6.1
Libs: -L\${libdir} -lprotobuf
Cflags: -I\${includedir}
EOF
    echo -e "${CYAN}✔ Created protobuf.pc at $PROTOBUF_DIR/lib/pkgconfig${RESET}"
fi

# --------------------------
# GitHub Actions Env Export (if running in CI)
# --------------------------
if [ -n "$GITHUB_ENV" ]; then
  echo "PKG_CONFIG_PATH=$PROTOBUF_DIR/lib/pkgconfig:\$PKG_CONFIG_PATH" >> "$GITHUB_ENV"
  echo "LD_LIBRARY_PATH=$PROTOBUF_DIR/lib:\$LD_LIBRARY_PATH" >> "$GITHUB_ENV"
  echo "LDFLAGS=-L$PROTOBUF_DIR/lib \$LDFLAGS" >> "$GITHUB_ENV"
  echo "CPPFLAGS=-I$PROTOBUF_DIR/include \$CPPFLAGS" >> "$GITHUB_ENV"
  echo "PATH=$PROTOBUF_DIR/bin:\$PATH" >> "$GITHUB_ENV"
fi

# --------------------------
# AdventureCoin source
# --------------------------
if [ ! -d "AdventureCoin" ]; then
    echo -e "${GREEN}>>> Cloning AdventureCoin...${RESET}"
    git clone https://github.com/CryptoDevelopmentServices/AdventureCoin.git
else
    echo -e "${GREEN}>>> Updating AdventureCoin...${RESET}"
    cd AdventureCoin && git pull && cd ..
fi

cd AdventureCoin

# --------------------------
# Confirm Protobuf environment
# --------------------------
echo -e "${CYAN}>>> Checking protoc version...${RESET}"
which protoc
protoc --version || { echo -e "${RED}✖ protoc not found or not working.${RESET}"; exit 1; }

echo -e "${CYAN}>>> Checking pkg-config path for protobuf...${RESET}"
pkg-config --modversion protobuf || echo -e "${RED}⚠ protobuf not found via pkg-config${RESET}"

# --------------------------
# Patch configure.ac properly
# --------------------------
echo -e "${GREEN}>>> Patching configure.ac for macOS (LT_INIT, AC_PROG_CXX, etc)...${RESET}"
CONFIG_AC="configure.ac"

if grep -q "AM_INIT_AUTOMAKE" "$CONFIG_AC"; then
    PATCHED=0
    if ! grep -q "LT_INIT" "$CONFIG_AC"; then
        awk '{print} /AM_INIT_AUTOMAKE/ && !x {print "LT_INIT"; x=1}' "$CONFIG_AC" > "$CONFIG_AC.tmp" && mv "$CONFIG_AC.tmp" "$CONFIG_AC"
        echo -e "${CYAN}✔ Inserted LT_INIT${RESET}"
        PATCHED=1
    fi
    if ! grep -q "AC_PROG_CXX" "$CONFIG_AC"; then
        awk '{print} /AM_INIT_AUTOMAKE/ && !x {print "AC_PROG_CXX"; x=1}' "$CONFIG_AC" > "$CONFIG_AC.tmp" && mv "$CONFIG_AC.tmp" "$CONFIG_AC"
        echo -e "${CYAN}✔ Inserted AC_PROG_CXX${RESET}"
        PATCHED=1
    fi
    if ! grep -q "AC_PROG_CC" "$CONFIG_AC"; then
        awk '{print} /AM_INIT_AUTOMAKE/ && !x {print "AC_PROG_CC"; x=1}' "$CONFIG_AC" > "$CONFIG_AC.tmp" && mv "$CONFIG_AC.tmp" "$CONFIG_AC"
        echo -e "${CYAN}✔ Inserted AC_PROG_CC${RESET}"
        PATCHED=1
    fi
    if [[ "$PATCHED" == 1 ]]; then
        echo -e "${GREEN}>>> Creating m4 directory and running aclocal...${RESET}"
        mkdir -p m4
        aclocal -I m4 || true
    fi
else
    echo -e "${RED}✖ Could not find AM_INIT_AUTOMAKE in configure.ac — please verify manually.${RESET}"
    exit 1
fi

# --------------------------
# Set environment paths
# --------------------------
if [[ "$(uname -m)" == "arm64" ]]; then
    echo -e "${CYAN}✔ Detected Apple Silicon (arm64)${RESET}"
    export PATH="/opt/homebrew/opt/berkeley-db@4/bin:/opt/homebrew/opt/qt@5/bin:$PATH"
    export BOOST_ROOT="/opt/homebrew/opt/boost"
    export BOOST_INCLUDEDIR="$BOOST_ROOT/include"
    export BOOST_LIBRARYDIR="$BOOST_ROOT/lib"
    export LDFLAGS="-L/opt/homebrew/opt/berkeley-db@4/lib -L/opt/homebrew/opt/qt@5/lib -L$BOOST_LIBRARYDIR $LDFLAGS"
    export CPPFLAGS="-I/opt/homebrew/opt/berkeley-db@4/include -I/opt/homebrew/opt/qt@5/include -I$BOOST_INCLUDEDIR $CPPFLAGS"
    export PKG_CONFIG_PATH="/opt/homebrew/opt/qt@5/lib/pkgconfig:$PKG_CONFIG_PATH"
else
    echo -e "${CYAN}✔ Detected Intel macOS${RESET}"
    export PATH="/usr/local/opt/berkeley-db@4/bin:/usr/local/opt/qt@5/bin:$PATH"
    export BOOST_ROOT="/usr/local/opt/boost"
    export BOOST_INCLUDEDIR="$BOOST_ROOT/include"
    export BOOST_LIBRARYDIR="$BOOST_ROOT/lib"
    export LDFLAGS="-L/usr/local/opt/berkeley-db@4/lib -L/usr/local/opt/qt@5/lib -L$BOOST_LIBRARYDIR $LDFLAGS"
    export CPPFLAGS="-I/usr/local/opt/berkeley-db@4/include -I/usr/local/opt/qt@5/include -I$BOOST_INCLUDEDIR $CPPFLAGS"
    export PKG_CONFIG_PATH="/usr/local/opt/qt@5/lib/pkgconfig:$PKG_CONFIG_PATH"
fi

# Add Protobuf environment (safely appended)
export PATH="$PROTOBUF_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$PROTOBUF_DIR/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PROTOBUF_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export LDFLAGS="-L$PROTOBUF_DIR/lib $LDFLAGS"
export CPPFLAGS="-I$PROTOBUF_DIR/include $CPPFLAGS"
export PROTOC="$PROTOBUF_DIR/bin/protoc"

export CXXFLAGS="-std=c++11"

# --------------------------
# Apply macOS Compatibility Patches
# --------------------------
echo -e "${GREEN}>>> Applying macOS compatibility patches...${RESET}"

BOOST_FILES=("src/init.cpp" "src/torcontrol.cpp" "src/validation.cpp" "src/validationinterface.cpp" "src/scheduler.cpp")
for FILE in "${BOOST_FILES[@]}"; do
    if ! grep -q "BOOST_BIND_GLOBAL_PLACEHOLDERS" "$FILE"; then
        sed -i.bak '1i\
#define BOOST_BIND_GLOBAL_PLACEHOLDERS\
' "$FILE"
        echo -e "${CYAN}✔ Patched $FILE with BOOST_BIND_GLOBAL_PLACEHOLDERS${RESET}"
    fi
done

PROTOCOL_CPP="rpc/protocol.cpp"
if grep -q 'is_complete' "$PROTOCOL_CPP"; then
    echo -e "${GREEN}>>> Patching deprecated is_complete() in $PROTOCOL_CPP...${RESET}"
    sed -i.bak 's/\.is_complete()/\.is_absolute()/g' "$PROTOCOL_CPP"
    echo -e "${CYAN}✔ Patched: .is_complete() → .is_absolute()${RESET}"
else
    echo -e "${CYAN}✔ No .is_complete() usage found in $PROTOCOL_CPP${RESET}"
fi

# --------------------------
# Configure and Build
# --------------------------
CONFIGURE_ARGS="--with-incompatible-bdb --with-boost-libdir=$BOOST_LIBRARYDIR --with-protobuf=$PROTOBUF_DIR"

echo -e "${GREEN}>>> Running autogen.sh...${RESET}"
chmod +x share/genbuild.sh autogen.sh
./autogen.sh

echo -e "${GREEN}>>> Running configure with args: $CONFIGURE_ARGS${RESET}"
if [[ "$BUILD_CHOICE" == "1" ]]; then
    ./configure $CONFIGURE_ARGS --without-gui
elif [[ "$BUILD_CHOICE" == "2" ]]; then
    ./configure $CONFIGURE_ARGS --with-gui=qt5
elif [[ "$BUILD_CHOICE" == "3" ]]; then
    ./configure $CONFIGURE_ARGS --disable-wallet --with-gui=qt5
fi

echo -e "${GREEN}>>> Starting make...${RESET}"
make -j"$(sysctl -n hw.logicalcpu)"

mkdir -p "$COMPILED_DIR"
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/adventurecoind src/adventurecoin-cli src/adventurecoin-tx "$COMPILED_DIR/" 2>/dev/null || true
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
    mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources"

    cp "$COMPILED_DIR/adventurecoin-qt" "$APP_BUNDLE_DIR/Contents/MacOS/"
    cat > "$APP_BUNDLE_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
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
</plist>
EOF

    echo -e "${GREEN}>>> Running macdeployqt...${RESET}"
    macdeployqt "$APP_BUNDLE_DIR" || { echo -e "${RED}✖ macdeployqt failed. Ensure Qt is in PATH and compatible.${RESET}"; exit 1; }

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
