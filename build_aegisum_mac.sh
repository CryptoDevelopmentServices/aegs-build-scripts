#!/bin/bash

set -e

# --------------------------------
# Ensure $HOME is defined properly
# --------------------------------
if [[ ! "$HOME" =~ ^/ ]]; then
  echo -e "${RED}⚠ Detected invalid \$HOME: '$HOME'. Fixing...${RESET}"
  export HOME="$(eval echo ~$USER)"
  echo -e "${GREEN}✔ HOME corrected to: $HOME${RESET}"
fi

# Fix PATH so basic commands are found
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

BDB_PREFIX="$(pwd)/db4"
COMPILED_DIR="$(pwd)/compiled_wallets_macos"

echo -e "${CYAN}============================="
echo -e " Aegisum macOS Builder"
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
brew install automake libtool berkeley-db@4 boost openssl libevent qt@5 qrencode miniupnpc zeromq pkg-config create-dmg fmt

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
# Aegisum source
# --------------------------
if [ ! -d "Aegisum" ]; then
    echo -e "${GREEN}>>> Cloning Aegisum...${RESET}"
    git clone https://github.com/Aegisum/aegisum-core.git 
    mv aegisum-core Aegisum
else
    echo -e "${GREEN}>>> Updating Aegisum...${RESET}"
    cd Aegisum && git pull && cd ..
fi

cd Aegisum

# --------------------------
# Patch Boost filesystem API (overwrite_if_exists -> overwrite_existing)
# --------------------------
echo -e "${GREEN}>>> Patching Boost copy_option -> copy_options in wallet/bdb.cpp...${RESET}"
BDB_CPP_FILE="wallet/bdb.cpp"

# Replace full line including function call for better reliability
if grep -q "fs::copy_file(pathSrc, pathDest, fs::copy_option::overwrite_if_exists);" "$BDB_CPP_FILE"; then
  sed -i '' \
    -e 's|fs::copy_file(pathSrc, pathDest, fs::copy_option::overwrite_if_exists);|fs::copy_file(pathSrc, pathDest, fs::copy_options::overwrite_existing);|' \
    "$BDB_CPP_FILE"
  echo -e "${CYAN}✔ Boost copy_file patch applied to $BDB_CPP_FILE${RESET}"
else
  echo -e "${CYAN}✔ No patch needed for $BDB_CPP_FILE${RESET}"
fi

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
ARCH=$(uname -m)

if [[ "$ARCH" == "arm64" ]]; then
    echo -e "${CYAN}✔ Detected Apple Silicon (arm64)${RESET}"
    BREDB_PATH="/opt/homebrew/opt/berkeley-db@4"
    QT_PATH="/opt/homebrew/opt/qt@5"
    BOOST_PATH="/opt/homebrew/opt/boost"
    FMT_PATH="/opt/homebrew/opt/fmt"
    LIBEVENT_PATH="/opt/homebrew/opt/libevent"
else
    echo -e "${CYAN}✔ Detected Intel macOS${RESET}"
    BREDB_PATH="/usr/local/opt/berkeley-db@4"
    QT_PATH="/usr/local/opt/qt@5"
    BOOST_PATH="/usr/local/opt/boost"
    FMT_PATH="/usr/local/opt/fmt"
    LIBEVENT_PATH="/usr/local/opt/libevent"
fi

export PATH="$BREDB_PATH/bin:$QT_PATH/bin:$PATH"
export BOOST_ROOT="$BOOST_PATH"
export BOOST_INCLUDEDIR="$BOOST_PATH/include"
export BOOST_LIBRARYDIR="$BOOST_PATH/lib"
echo -e "${CYAN}✔ BOOST_LIBRARYDIR set to: $BOOST_LIBRARYDIR${RESET}"
export LDFLAGS="-L$BREDB_PATH/lib -L$QT_PATH/lib -L$BOOST_PATH/lib -L$FMT_PATH/lib -L$LIBEVENT_PATH/lib $LDFLAGS"
export CPPFLAGS="-I$BREDB_PATH/include -I$QT_PATH/include -I$BOOST_PATH/include -I$FMT_PATH/include -I$LIBEVENT_PATH/include $CPPFLAGS"
export PKG_CONFIG_PATH="$QT_PATH/lib/pkgconfig:$FMT_PATH/lib/pkgconfig:$LIBEVENT_PATH/lib/pkgconfig:$PKG_CONFIG_PATH"

# Protobuf
if [[ -n "$PROTOBUF_DIR" ]]; then
    export PATH="$PROTOBUF_DIR/bin:$PATH"
    export LD_LIBRARY_PATH="$PROTOBUF_DIR/lib:$LD_LIBRARY_PATH"
    export PKG_CONFIG_PATH="$PROTOBUF_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
    export LDFLAGS="-L$PROTOBUF_DIR/lib $LDFLAGS"
    export CPPFLAGS="-I$PROTOBUF_DIR/include $CPPFLAGS"
    export PROTOC="$PROTOBUF_DIR/bin/protoc"
fi

# 🛠️ Critical fix for Boost linking
export LIBS="$LIBS -lboost_filesystem -lboost_system"

export CC=clang
export CXX=clang++
export CXXFLAGS="-std=c++14 -Wno-deprecated-builtins"

export LDFLAGS="$(echo "$LDFLAGS" | sed 's|/opt/local[^ ]*||g')"
export CPPFLAGS="$(echo "$CPPFLAGS" | sed 's|/opt/local[^ ]*||g')"

# --------------------------
# Remove unsupported Clang flags
# --------------------------
export CXXFLAGS="$(echo "$CXXFLAGS" | sed 's/-fstack-clash-protection//g')"

# --------------------------
# Configure and Build
# --------------------------
CONFIGURE_ARGS="--with-incompatible-bdb --with-boost-libdir=$BOOST_LIBRARYDIR --with-protobuf=$PROTOBUF_DIR"

echo -e "${GREEN}>>> Running autogen.sh...${RESET}"
chmod +x share/genbuild.sh autogen.sh
./autogen.sh

echo -e "${CYAN}>>> Cleaning previous build config...${RESET}"
if [ -f Makefile ]; then
    make distclean || true
fi

echo -e "${GREEN}>>> Running configure with args: $CONFIGURE_ARGS${RESET}"
if [[ "$BUILD_CHOICE" == "1" ]]; then
    ./configure $CONFIGURE_ARGS --without-gui
elif [[ "$BUILD_CHOICE" == "2" ]]; then
    ./configure $CONFIGURE_ARGS --with-gui=qt5
elif [[ "$BUILD_CHOICE" == "3" ]]; then
    ./configure $CONFIGURE_ARGS --disable-wallet --with-gui=qt5
fi

echo -e "${CYAN}>>> Verifying Boost link target...${RESET}"
grep boost config.log | grep "$BOOST_LIBRARYDIR" || echo -e "${RED}⚠ Boost may not have been picked up from $BOOST_LIBRARYDIR${RESET}"

echo -e "${GREEN}>>> Starting make...${RESET}"
make -j"$(sysctl -n hw.logicalcpu)"

mkdir -p "$COMPILED_DIR"
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/aegisumd src/aegisum-cli src/aegisum-tx "$COMPILED_DIR/" 2>/dev/null || true
[[ "$BUILD_CHOICE" =~ [23] ]] && cp src/qt/aegisum-qt "$COMPILED_DIR/" 2>/dev/null || true

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
if [[ "$MAKE_DMG" =~ ^[Yy]$ && -f "$COMPILED_DIR/aegisum-qt" ]]; then
    echo -e "${GREEN}>>> Creating .app bundle...${RESET}"
    APP_BUNDLE_DIR="${COMPILED_DIR}/Aegisum-Qt.app"
    mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources"

    cp "$COMPILED_DIR/aegisum-qt" "$APP_BUNDLE_DIR/Contents/MacOS/"
    cat > "$APP_BUNDLE_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>aegisum-qt</string>
  <key>CFBundleIdentifier</key>
  <string>com.aegisum.wallet</string>
  <key>CFBundleName</key>
  <string>Aegisum</string>
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
    DMG_PATH="${COMPILED_DIR}/Aegisum-Wallet.dmg"
    create-dmg \
      --volname "Aegisum Wallet" \
      --window-pos 200 120 \
      --window-size 600 300 \
      --icon-size 100 \
      --icon "Aegisum-Qt.app" 175 120 \
      --hide-extension "Aegisum-Qt.app" \
      --app-drop-link 425 120 \
      "$DMG_PATH" \
      "$COMPILED_DIR"

    echo -e "${GREEN}✔ DMG created at: $DMG_PATH${RESET}"
fi

if [[ -f "$COMPILED_DIR/aegisum-cli" ]]; then
    echo -e "${CYAN}>>> Linked libraries in aegisum-cli:${RESET}"
    otool -L "$COMPILED_DIR/aegisum-cli" | grep boost || echo -e "${RED}⚠ Boost not linked properly.${RESET}"
fi


echo -e "\n${CYAN}✔ Build complete! Binaries in: ${COMPILED_DIR}${RESET}"
