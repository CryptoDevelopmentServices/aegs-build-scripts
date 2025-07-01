## 🚀 Aegisum Build Scripts
 
This interactive Bash script automates building Aegisum's daemon and Qt wallet on **Ubuntu-based systems** and **macOS**. It includes full support for advanced packaging, launcher creation, and Berkeley DB patching. Perfect for developers and users who want to build or distribute Aegisum with minimal effort.

# aegs-build-scripts

🛠️ Features
✅ Interactive Menu – Choose between:

* Daemon-only build
* Qt Wallet-only build
* Full build (Daemon + Qt Wallet)

✅ Optional Steps (Ubuntu only, toggleable):

* Strip compiled binaries for smaller size
* Create `.tar.gz` package
* Create `.deb` installer
* Create `.desktop` launcher shortcut
* Generate full desktop-integrated Qt Wallet `.deb`, including multi-size icons

✅ macOS Support:

* Native `.app` bundle generation
* Signed `.dmg` disk image creation
* Auto-patches deprecated Boost and Qt methods
* Installs Protobuf 3.6.1 locally for compatibility
* Works on Apple Silicon and Intel Macs

✅ Automatic Berkeley DB 4.8 Setup:

* Downloads, configures, and compiles Berkeley DB 4.8
* Includes a patch to support newer GCC/Clang versions (`__atomic_compare_exchange` fix)

✅ Source Handling:

* Clones the latest Aegisum repo (or updates if already cloned)
* Fully automates autogen and configure steps

✅ Qt Wallet Launcher Integration (Ubuntu Only):

* Downloads a PNG icon and auto-resizes it to standard resolutions (16x16 to 512x512)
* Embeds icon and `.desktop` file into a proper `.deb` package for desktop launchers

---

## 📦 Output

After running, all binaries and generated packages are located in:

```bash
compiled_wallets/           # Ubuntu
compiled_wallets_macos/     # macOS
```

> Possible files include:

* `aegisumd`, `aegisum-cli`, `aegisum-tx`, `aegisum-qt`
* `aegisum_wallet.tar.gz` (if selected)
* `aegisum_wallet.deb` (CLI+Daemon wallet)
* `aegisum-qt-launcher.deb` (Full desktop `.deb` for Qt wallet)
* `Aegisum-Qt.dmg` (Full macOS drag-and-drop installer)
* `Aegisum-Qt.app` (Native macOS app bundle)

---

## 🔧 Requirements

### ✅ Ubuntu (20.04, 22.04, 24.04 recommended)

Script auto-installs all required dependencies, including:

* Qt5 libraries
* Berkeley DB 4.8
* Boost
* Protobuf
* libevent, libssl, miniupnpc, etc.

### 🍏 macOS (12 Monterey and above)

* Xcode + Command Line Tools
* Homebrew (for dependency management)
* Supports both Intel and Apple Silicon chips
* Installs Protobuf 3.6.1 locally to avoid incompatibility

---

## 💡 Usage

### Ubuntu:

```bash
chmod +x build_aegisum_ubuntu.sh
./build_aegisum_ubuntu.sh
```

### macOS:

```bash
chmod +x build_aegisum_mac.sh
./build_aegisum_mac.sh
```

Just follow the prompts to customize your build. The script handles everything else!
