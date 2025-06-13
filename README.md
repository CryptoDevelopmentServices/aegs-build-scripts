## 🚀 AdventureCoin Build Scripts
This interactive Bash script automates building AdventureCoin's daemon and Qt wallet on Ubuntu-based systems. It includes full support for advanced packaging, launcher creation, and Berkeley DB patching. Perfect for developers and users who want to build or distribute AdventureCoin with minimal effort.# advc-build-scripts

🛠️ Features
✅ Interactive Menu – Choose between:

* Daemon-only build

* Qt Wallet-only build

* Full build (Daemon + Qt Wallet)

✅ Optional Steps (ubuntu) (toggleable):

* Strip compiled binaries for smaller size

* Create `.tar.gz` package

* Create `.deb` installer

* Create `.desktop` launcher shortcut

* Generate full desktop-integrated Qt Wallet `.deb`, including multi-size icons

✅ Automatic Berkeley DB 4.8 Setup:

* Downloads, configures, and compiles Berkeley DB 4.8

* Includes a patch to support newer GCC versions (__atomic_compare_exchange fix)

✅ Source Handling:

* Clones the latest AdventureCoin repo (or updates if already cloned)

* Fully automates autogen and configure steps

✅ Qt Wallet Launcher Integration (Optional):

* Downloads a PNG icon and auto-resizes it to standard resolutions (16x16 to 512x512)

* Embeds icon and `.desktop` file into a proper `.deb` package for desktop launchers

## 📦 Output
After running, all binaries and generated packages are located in:

```
compiled_wallets/
```
> Possible files include:

* `adventurecoind`, `adventurecoin-cli`, `adventurecoin-tx`, `adventurecoin-qt`

* `adventurecoin_wallet.tar.gz` (if selected)

* `adventurecoin_wallet.deb` (CLI+Daemon wallet)

* `adventurecoin-qt-launcher.deb` (Full desktop `.deb` for Qt wallet)

## 🔧 Requirements
Ubuntu 20.04, 22.04 or 24.04 recommended. Script auto-installs all required dependencies including:

* Qt5 libraries

* Berkeley DB 4.8

* Boost

* Protobuf

* libevent, libssl, miniupnpc, etc.

## 💡 Usage
```bash
chmod +x build-adventurecoin.sh
./build-adventurecoin.sh
```
Just follow the prompts to customize your build. The script handles everything else!

