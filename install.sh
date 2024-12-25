#!/bin/bash

set -e

# Define variables
GITHUB_REPO="ryvn-technologies/ryvn-cli-release"
BINARY_NAME="ryvn"
INSTALL_DIR="/usr/local/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print step description
step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Error handling
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Get the latest release version from GitHub
get_latest_version() {
    curl --silent "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | 
    grep '"tag_name":' | 
    sed -E 's/.*"([^"]+)".*/\1/'
}

# Detect OS and architecture
detect_platform() {
    local OS
    local ARCH
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Convert architecture names
    case "$ARCH" in
        x86_64)
            ARCH="x86_64"
            ;;
        amd64)
            ARCH="x86_64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
    
    # Convert OS names
    case "$OS" in
        linux)
            OS="Linux"
            ;;
        darwin)
            OS="Darwin"
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac
    
    echo "${OS}_${ARCH}"
}

main() {
    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then
        error "Please run with sudo"
    }
    
    step "Detecting platform..."
    PLATFORM=$(detect_platform)
    echo "Detected platform: $PLATFORM"
    
    step "Getting latest version..."
    VERSION=$(get_latest_version)
    if [ -z "$VERSION" ]; then
        error "Failed to get latest version"
    fi
    echo "Latest version: $VERSION"
    
    # Construct download URL
    ARCHIVE_EXT=".tar.gz"
    if [[ "$PLATFORM" == *"windows"* ]]; then
        ARCHIVE_EXT=".zip"
    fi
    
    DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/ryvn_${PLATFORM}${ARCHIVE_EXT}"
    
    step "Downloading $BINARY_NAME..."
    TMP_DIR=$(mktemp -d)
    curl -L --silent "$DOWNLOAD_URL" -o "$TMP_DIR/ryvn${ARCHIVE_EXT}"
    
    step "Installing $BINARY_NAME..."
    cd "$TMP_DIR"
    if [[ "$ARCHIVE_EXT" == ".tar.gz" ]]; then
        tar xzf "ryvn${ARCHIVE_EXT}"
    else
        unzip "ryvn${ARCHIVE_EXT}"
    fi
    
    # Install binary
    mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # Cleanup
    rm -rf "$TMP_DIR"
    
    echo -e "${GREEN}Successfully installed $BINARY_NAME to $INSTALL_DIR/$BINARY_NAME${NC}"
    echo -e "Run '${BLUE}ryvn --help${NC}' to get started"
}

main
