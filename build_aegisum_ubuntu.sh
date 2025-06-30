#!/bin/bash

set -e

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

BDB_PREFIX="$(pwd)/db4"
COMPILED_DIR="$(pwd)/compiled_wallets"

echo -e "${CYAN}============================="
echo -e " Aegisum Ubuntu Builder"
echo -e "=============================${RESET}"

# 1. Build type
echo -e "\n${GREEN}Select build type:${RESET}"
echo "1) Daemon only"
echo "2) Daemon + Qt Wallet (full)"
echo "3) Qt Wallet only"
read -rp "Enter choice [1-3]: " BUILD_CHOICE

# 2. Strip?
read -rp $'\nDo you want to strip the binaries after build? (y/n): ' STRIP_BIN

# 3. .deb?
read -rp $'\nDo you want to create a .deb package? (y/n): ' DEB_PACKAGE

# 4. .tar.gz?
read -rp $'\nDo you want to create a .tar.gz archive? (y/n): ' TAR_PACKAGE

# 5. Desktop shortcut?
read -rp $'\nDo you want to create a .desktop shortcut for Qt wallet? (y/n): ' DESKTOP_SHORTCUT

# 6. Full Qt Wallet launcher .deb with icon?
read -rp $'\nDo you want to create a full desktop launcher .deb for Qt wallet (with icon)? (y/n): ' QT_LAUNCHER_DEB

# --------------------------
# Dependencies
# --------------------------
echo -e "\n${GREEN}>>> Installing build dependencies...${RESET}"
sudo apt-get update
sudo apt-get install -y build-essential libtool autotools-dev automake pkg-config libssl-dev \
libevent-dev bsdmainutils python3 libminiupnpc-dev libzmq3-dev \
libqt5gui5 libqt5core5a libqt5dbus5 qttools5-dev qttools5-dev-tools \
libprotobuf-dev protobuf-compiler libqrencode-dev git curl fakeroot dpkg-dev imagemagick \
libboost-system-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-thread-dev libboost-chrono-dev

# --------------------------
# Berkeley DB 4.8
# --------------------------
echo -e "${GREEN}>>> Installing Berkeley DB 4.8...${RESET}"
mkdir -p "$BDB_PREFIX"
if [ ! -d "db-4.8.30.NC" ]; then
    curl -LO 'http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz'
    tar -xzf db-4.8.30.NC.tar.gz
fi

cd db-4.8.30.NC

# Patch __atomic_compare_exchange for GCC 11+
echo -e "${GREEN}>>> Patching Berkeley DB for GCC compatibility...${RESET}"
sed -i 's/__atomic_compare_exchange/__db_atomic_compare_exchange/g' dbinc/atomic.h

cd build_unix
../dist/configure --prefix="$BDB_PREFIX" --enable-cxx --disable-shared --with-pic
make -j"$(nproc)"
make install
cd ../../


# --------------------------
# Aegisum source
# --------------------------
if [ ! -d "Aegisum" ]; then
    echo -e "${GREEN}>>> Cloning Aegisum...${RESET}"
    git clone https://github.com/Aegisum/aegisum-core.git
else
    echo -e "${GREEN}>>> Updating Aegisum...${RESET}"
    cd Aegisum && git pull && cd ..
fi

cd Aegisum

# This is for if you want it to use a specific branch
# echo -e "${GREEN}>>> Checking out update-to-compile-2204-2404 branch...${RESET}"
# git fetch origin
# git checkout update-to-compile-2204-2404

chmod +x share/genbuild.sh
chmod +x autogen.sh
./autogen.sh

CONFIGURE_ARGS="LDFLAGS=-L${BDB_PREFIX}/lib/ CPPFLAGS=-I${BDB_PREFIX}/include/"

if [[ "$BUILD_CHOICE" == "1" ]]; then
    ./configure $CONFIGURE_ARGS --without-gui
elif [[ "$BUILD_CHOICE" == "2" ]]; then
    ./configure $CONFIGURE_ARGS --with-gui=qt5
elif [[ "$BUILD_CHOICE" == "3" ]]; then
    ./configure $CONFIGURE_ARGS --disable-wallet --with-gui=qt5
fi

make -j"$(nproc)"

mkdir -p "$COMPILED_DIR"

[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/aegisumd "$COMPILED_DIR/"
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/aegisum-cli "$COMPILED_DIR/"
[[ "$BUILD_CHOICE" =~ [12] ]] && cp src/aegisum-tx "$COMPILED_DIR/"
[[ "$BUILD_CHOICE" =~ [23] ]] && cp src/qt/aegisum-qt "$COMPILED_DIR/"

# --------------------------
# Strip Binaries
# --------------------------
if [[ "$STRIP_BIN" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}>>> Stripping binaries...${RESET}"
    strip "$COMPILED_DIR"/* || true
fi

# --------------------------
# .desktop shortcut
# --------------------------
if [[ "$DESKTOP_SHORTCUT" =~ ^[Yy]$ && -f "$COMPILED_DIR/aegisum-qt" ]]; then
    echo -e "${GREEN}>>> Creating desktop shortcut...${RESET}"
    mkdir -p ~/.local/share/applications
    cat <<EOF > ~/.local/share/applications/aegisum.desktop
[Desktop Entry]
Name=Aegisum Wallet
Comment=Launch Aegisum Qt Wallet
Exec=${COMPILED_DIR}/aegisum-qt
Icon=wallet
Terminal=false
Type=Application
Categories=Finance;
EOF
    chmod +x ~/.local/share/applications/aegisum.desktop
    echo -e "${GREEN}✔ Desktop entry created at ~/.local/share/applications/aegisum.desktop${RESET}"
fi

# --------------------------
# .deb package
# --------------------------
if [[ "$DEB_PACKAGE" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}>>> Creating .deb package...${RESET}"

    mkdir -p aegs-deb/DEBIAN
    mkdir -p aegs-deb/usr/local/bin

    cat <<EOF > aegs-deb/DEBIAN/control
Package: aegisum
Version: 1.0
Section: base
Priority: optional
Architecture: amd64
Maintainer: Crypto Development Services
Description: Aegisum Wallet Binaries
EOF

    cp "$COMPILED_DIR"/aegisumd aegs-deb/usr/local/bin/ 2>/dev/null || true
    cp "$COMPILED_DIR"/aegisum-cli aegs-deb/usr/local/bin/ 2>/dev/null || true
    cp "$COMPILED_DIR"/aegisum-tx aegs-deb/usr/local/bin/ 2>/dev/null || true
    cp "$COMPILED_DIR"/aegisum-qt aegs-deb/usr/local/bin/ 2>/dev/null || true

    dpkg-deb --build aegs-deb
    mv aegs-deb.deb "$COMPILED_DIR/aegisum_wallet.deb"
    rm -rf aegs-deb

    echo -e "${GREEN}✔ .deb package created at $COMPILED_DIR/aegisum_wallet.deb${RESET}"
fi

# --------------------------
# .tar.gz package
# --------------------------
if [[ "$TAR_PACKAGE" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}>>> Creating .tar.gz archive...${RESET}"
    if tar --warning=no-file-changed -czf "$COMPILED_DIR/aegisum_wallet.tar.gz" -C "$COMPILED_DIR" .; then
        echo -e "${GREEN}✔ .tar.gz created at $COMPILED_DIR/aegisum_wallet.tar.gz${RESET}"
    else
        echo -e "${RED}✖ Failed to create .tar.gz archive${RESET}"
    fi
fi


# --------------------------
# Qt Wallet Launcher .deb with Icons
# --------------------------
if [[ "$QT_LAUNCHER_DEB" =~ ^[Yy]$ && -f "$COMPILED_DIR/aegisum-qt" ]]; then
    echo -e "${GREEN}>>> Creating full Qt Wallet launcher .deb with icons...${RESET}"

    wget -O aegs_icon.png https://raw.githubusercontent.com/CryptoDevelopmentServices/Logos/main/aegs.png

    mkdir -p qt-launcher-deb/DEBIAN
    mkdir -p qt-launcher-deb/usr/local/bin
    mkdir -p qt-launcher-deb/usr/share/applications

    for size in 16 32 48 64 128 256 512; do
        mkdir -p qt-launcher-deb/usr/share/icons/hicolor/${size}x${size}/apps
        convert aegs_icon.png -resize ${size}x${size} qt-launcher-deb/usr/share/icons/hicolor/${size}x${size}/apps/aegisum.png
    done

    cat <<EOF > qt-launcher-deb/usr/share/applications/aegisum-qt.desktop
[Desktop Entry]
Name=Aegisum Wallet
Comment=Launch the Aegisum Qt Wallet
Exec=/usr/local/bin/aegisum-qt
Icon=aegisum
Terminal=false
Type=Application
Categories=Finance;
EOF

    cat <<EOF > qt-launcher-deb/DEBIAN/control
Package: aegisum-qt
Version: 1.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Crypto Development Services
Description: Aegisum Qt Wallet launcher with full desktop integration and icons.
EOF

    cp "$COMPILED_DIR/aegisum-qt" qt-launcher-deb/usr/local/bin/

    dpkg-deb --build qt-launcher-deb
    mv qt-launcher-deb.deb "$COMPILED_DIR/aegisum-qt-launcher.deb"
    rm -rf qt-launcher-deb aegs_icon.png

    echo -e "${GREEN}✔ Full Qt launcher .deb created at $COMPILED_DIR/aegisum-qt-launcher.deb${RESET}"
fi

echo -e "\n${CYAN}Build complete! Binaries located in: ${COMPILED_DIR}${RESET}"
