#!/bin/bash

set -e

# Colors for better output
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}>>> Updating system and installing dependencies...${RESET}"
sudo apt-get update
sudo apt-get install -y build-essential libtool autotools-dev automake pkg-config libssl-dev \
libevent-dev bsdmainutils python3 libminiupnpc-dev libzmq3-dev \
libqt5gui5 libqt5core5a libqt5dbus5 qttools5-dev qttools5-dev-tools \
libprotobuf-dev protobuf-compiler libqrencode-dev git curl

# Berkeley DB 4.8 installation
echo -e "${GREEN}>>> Installing Berkeley DB 4.8...${RESET}"
BDB_PREFIX="$(pwd)/db4"
mkdir -p "$BDB_PREFIX"

if [ ! -d "db-4.8.30.NC" ]; then
    curl -O 'http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz'
    tar -xzvf db-4.8.30.NC.tar.gz
fi

cd db-4.8.30.NC/build_unix
../dist/configure --prefix="$BDB_PREFIX" --enable-cxx --disable-shared --with-pic
make -j"$(nproc)"
make install
cd ../../

# Clone AdventureCoin if not already
if [ ! -d "AdventureCoin" ]; then
    echo -e "${GREEN}>>> Cloning AdventureCoin source...${RESET}"
    git clone https://github.com/AdventureCoin-ADVC/AdventureCoin.git
fi

cd AdventureCoin

echo -e "${GREEN}>>> Running build system setup...${RESET}"
./autogen.sh
./configure LDFLAGS="-L${BDB_PREFIX}/lib/" CPPFLAGS="-I${BDB_PREFIX}/include/" --with-gui=qt5
make -j"$(nproc)"

# Create directory for compiled wallets
echo -e "${GREEN}>>> Moving compiled binaries to compiled_wallets/...${RESET}"
mkdir -p ../compiled_wallets
cp src/adventurecoind ../compiled_wallets/
cp src/adventurecoin-cli ../compiled_wallets/
cp src/adventurecoin-tx ../compiled_wallets/
cp src/qt/adventurecoin-qt ../compiled_wallets/

echo -e "${GREEN}>>> Build completed successfully. Binaries are in compiled_wallets/.${RESET}"
