#!/usr/bin/env bash
#
# Ryvn CLI installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ryvn-technologies/ryvn-cli-release/main/install.sh | bash
#
# Environment variables:
#   INSTALL_DIR   - Custom install directory (default: ~/.ryvn/bin)
#
# Wrap everything in a function to protect against partial download.
# If the connection drops mid-transfer, bash won't execute a truncated script.
main() {

set -euo pipefail

# Define variables
GITHUB_REPO="ryvn-technologies/ryvn-cli-release"
BINARY_NAME="ryvn"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.ryvn/bin}"
TMP_DIR=""
VERSION="v0.214.0" # This will be automatically updated by GitHub workflow

# Colors (only when outputting to a terminal)
RED='' GREEN='' BLUE='' YELLOW='' BOLD='' DIM='' NC=''
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    DIM='\033[0;2m'
    NC='\033[0m'
fi

# Display path with ~ instead of $HOME for readability
tildify() {
    if [[ $1 == "$HOME"/* ]]; then
        echo "~${1#"$HOME"}"
    else
        echo "$1"
    fi
}

error() {
    printf "%b\n" "${RED}error${NC}: $*" >&2
    cleanup
    exit 1
}

warn() {
    printf "%b\n" "${YELLOW}warn${NC}: $*" >&2
}

info() {
    printf "%b\n" "${DIM}$*${NC}"
}

success() {
    printf "%b\n" "${GREEN}$*${NC}"
}

bold() {
    printf "%b\n" "${BOLD}$*${NC}"
}

# Cleanup function
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# Set up trap to clean up on exit
trap cleanup EXIT INT TERM

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect OS and architecture
detect_platform() {
    local OS
    local ARCH

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    # Convert architecture names
    case "$ARCH" in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac

    # Detect Rosetta 2 on macOS — prefer native arm64 binary
    if [[ "$OS" == "darwin" ]] && [[ "$ARCH" == "x86_64" ]]; then
        if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0) == "1" ]]; then
            ARCH="arm64"
            info "  Rosetta 2 detected — installing native arm64 binary"
        fi
    fi

    # Convert OS names
    case "$OS" in
        linux)
            OS="Linux"
            ;;
        darwin)
            OS="Darwin"
            ;;
        msys*|mingw*|cygwin*)
            OS="Windows"
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac

    echo "${OS}_${ARCH}"
}

# Configure PATH in shell config
setup_path() {
    # Check if already on PATH via another location
    if command_exists "$BINARY_NAME"; then
        local existing
        existing=$(command -v "$BINARY_NAME")
        if [[ "$existing" == "$INSTALL_DIR/$BINARY_NAME" ]]; then
            return 0
        else
            warn "another '$BINARY_NAME' was found at $existing"
            info "  The new installation at $(tildify "$INSTALL_DIR/$BINARY_NAME") may be shadowed."
        fi
    fi

    # Check if INSTALL_DIR is already in PATH
    if echo "$PATH" | tr ':' '\n' | grep -qxF "$INSTALL_DIR" 2>/dev/null; then
        return 0
    fi

    # Determine shell config file
    local shell_name config shell_line shell_bin_dir

    shell_name=$(basename "${SHELL:-}")

    # Build a $HOME-relative path for shell config
    if [[ $INSTALL_DIR == "$HOME"/* ]]; then
        shell_bin_dir="\$HOME${INSTALL_DIR#"$HOME"}"
    else
        shell_bin_dir="$INSTALL_DIR"
    fi

    config=""
    shell_line=""

    case $shell_name in
        zsh)
            config="${ZDOTDIR:-$HOME}/.zshrc"
            shell_line="export PATH=\"${shell_bin_dir}:\$PATH\""
            ;;
        bash)
            # macOS bash opens login shells — .bash_profile is loaded, not .bashrc.
            # Linux bash opens non-login interactive shells — .bashrc is preferred.
            if [[ $(uname -s) == "Darwin" ]]; then
                if [[ -f "$HOME/.bash_profile" ]]; then
                    config="$HOME/.bash_profile"
                elif [[ -f "$HOME/.bashrc" ]]; then
                    config="$HOME/.bashrc"
                else
                    config="$HOME/.bash_profile"
                fi
            else
                if [[ -f "$HOME/.bashrc" ]]; then
                    config="$HOME/.bashrc"
                elif [[ -f "$HOME/.bash_profile" ]]; then
                    config="$HOME/.bash_profile"
                else
                    config="$HOME/.bashrc"
                fi
            fi
            shell_line="export PATH=\"${shell_bin_dir}:\$PATH\""
            ;;
        fish)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/ryvn.fish"
            mkdir -p "$(dirname "$config")"
            shell_line="fish_add_path ${shell_bin_dir}"
            ;;
    esac

    if [[ -n $config ]]; then
        # Check if PATH entry already exists
        if [[ -f "$config" ]] && (grep -qF "$(tildify "$INSTALL_DIR")" "$config" 2>/dev/null || grep -qF "$INSTALL_DIR" "$config" 2>/dev/null); then
            info "  PATH already configured in $(tildify "$config")"
        elif [[ -w "${config%/*}" ]] || [[ -w "$config" ]]; then
            {
                echo ""
                echo "# Ryvn CLI"
                echo "$shell_line"
            } >> "$config"
            info "  Added $(tildify "$INSTALL_DIR") to \$PATH in $(tildify "$config")"
            echo ""
            info "  To start using ryvn, run:"
            echo ""
            bold "    source $(tildify "$config")"
            bold "    ryvn --help"
        else
            echo ""
            info "  Manually add to your shell config:"
            echo ""
            bold "    ${shell_line}"
        fi
    else
        echo ""
        info "  Add to your shell config:"
        echo ""
        bold "    export PATH=\"${shell_bin_dir}:\$PATH\""
    fi
}

# Check for required commands
command_exists curl || error "curl is required but not installed"
command_exists tar || error "tar is required but not installed"

echo ""
bold "  Installing Ryvn CLI..."
echo ""

PLATFORM=$(detect_platform)
info "  Platform: $PLATFORM"

# Construct download URL with proper extension for Windows
ARCHIVE_EXT=".tar.gz"
if [[ "$PLATFORM" == *"Windows"* ]]; then
    ARCHIVE_EXT=".zip"
    command_exists unzip || error "unzip is required but not installed"
    # For Windows, adjust the install directory if running in MSYS/MinGW
    if [[ -n "${MSYSTEM:-}" ]]; then
        INSTALL_DIR="/usr/bin"
    fi
fi

DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/ryvn-cli-release_${PLATFORM}${ARCHIVE_EXT}"

TMP_DIR=$(mktemp -d) || error "Failed to create temporary directory"

info "  Downloading from: $DOWNLOAD_URL"
echo ""

# Download with progress bar
if ! curl -L --fail --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/ryvn${ARCHIVE_EXT}"; then
    error "Download failed.

  Possible causes:
    - No internet connection
    - The version does not exist: ${VERSION}
    - GitHub is unreachable

  URL: ${DOWNLOAD_URL}"
fi

cd "$TMP_DIR" || error "Failed to change to temporary directory"

# Extract archive based on platform
if [[ "$PLATFORM" == *"Windows"* ]]; then
    unzip "ryvn${ARCHIVE_EXT}" || error "Failed to extract archive"
    BINARY_NAME="${BINARY_NAME}.exe"
else
    tar xzf "ryvn${ARCHIVE_EXT}" || error "Failed to extract archive. The download may be corrupted — try again."
fi

# Ensure install directory exists
mkdir -p "$INSTALL_DIR" || error "Failed to create installation directory"

# Install binary
mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME" || error "Failed to move binary to installation directory"
chmod +x "$INSTALL_DIR/$BINARY_NAME" || error "Failed to make binary executable"

# Strip macOS Gatekeeper quarantine flag (set automatically on curl downloads)
# Without this, macOS will block the binary with "cannot be opened" dialog
if [[ $(uname -s) == "Darwin" ]]; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null || true
fi

# Verify installation
installed_version=$("$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null || echo "unknown")

echo ""
success "  Ryvn CLI ${installed_version} installed successfully!"
echo ""
info "  Binary:  $(tildify "$INSTALL_DIR/$BINARY_NAME")"

# Set up PATH if needed (skip for Windows)
if [[ "$PLATFORM" != *"Windows"* ]]; then
    setup_path
fi

echo ""

}

# Run the installer — this line MUST be the last line in the file.
# If the download is interrupted, bash will not execute an incomplete function.
main
