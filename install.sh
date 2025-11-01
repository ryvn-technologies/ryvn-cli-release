#!/bin/bash

set -euo pipefail

# Define variables
GITHUB_REPO="ryvn-technologies/ryvn-cli-release"
BINARY_NAME="ryvn"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=""
VERSION="v0.67.0" # This will be automatically updated by GitHub workflow

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print step description
step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Warning message
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Error handling
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# Set up trap to clean up on exit
trap cleanup EXIT

# Get the latest release version
get_latest_version() {
    echo "$VERSION"
}

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

# Check for existing installation
check_existing_installation() {
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        warn "Found existing installation"
        
        # Check if running in non-interactive environment (CI)
        if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
            echo "Running in non-interactive environment, proceeding with installation..."
            return 0
        fi
        
        read -p "Do you want to proceed with installation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# Verify installation
verify_installation() {
    local binary_path="$INSTALL_DIR/$BINARY_NAME"
    
    # Check if binary exists
    if [ ! -f "$binary_path" ]; then
        error "Installation verification failed: binary not found at $binary_path"
    fi
    
    # Check if binary is executable
    if [ ! -x "$binary_path" ]; then
        error "Installation verification failed: binary is not executable"
    fi
    
    # Check PATH
    if ! command_exists "$BINARY_NAME"; then
        error "Installation verification failed: binary not found in PATH"
    fi
    
    # Try running the binary without arguments to ensure it's working
    if ! "$binary_path" > /dev/null 2>&1; then
        local error_output
        error_output=$("$binary_path" 2>&1)
        # If it returns usage information, that's a success
        if [[ "$error_output" == *"Usage"* ]] || [[ "$error_output" == *"usage"* ]]; then
            return 0
        fi
        # Otherwise show the error
        error "Installation verification failed: binary failed to execute:\n$error_output"
    fi
}

main() {
    # Check for required commands
    command_exists curl || error "curl is required but not installed"
    command_exists tar || error "tar is required but not installed"
    
    # Check if running with sudo (skip for Windows)
    if [[ "$(detect_platform)" != *"Windows"* ]] && [ "$EUID" -ne 0 ]; then
        error "Please run with sudo"
    fi
    
    step "Detecting platform..."
    PLATFORM=$(detect_platform)
    echo "Detected platform: $PLATFORM"
    
    step "Getting latest version..."
    VERSION=$(get_latest_version)
    echo "Latest version: $VERSION"
    
    check_existing_installation
    
    # Construct download URL with proper extension for Windows
    ARCHIVE_EXT=".tar.gz"
    if [[ "$PLATFORM" == *"Windows"* ]]; then
        ARCHIVE_EXT=".zip"
        command_exists unzip || error "unzip is required but not installed"
        # For Windows, adjust the install directory if running in MSYS/MinGW
        if [[ -n "${MSYSTEM:-}" ]]; then
            INSTALL_DIR="/usr/bin"
        fi
    else
        command_exists tar || error "tar is required but not installed"
    fi
    
    DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/ryvn-cli-release_${PLATFORM}${ARCHIVE_EXT}"
    
    step "Downloading $BINARY_NAME..."
    TMP_DIR=$(mktemp -d) || error "Failed to create temporary directory"
    echo "Downloading from: $DOWNLOAD_URL"
    
    # Download with progress bar
    if ! curl -L --fail --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/ryvn${ARCHIVE_EXT}"; then
        error "Failed to download binary"
    fi
    
    step "Installing $BINARY_NAME..."
    cd "$TMP_DIR" || error "Failed to change to temporary directory"
    
    # Extract archive based on platform
    if [[ "$PLATFORM" == *"Windows"* ]]; then
        if ! unzip "ryvn${ARCHIVE_EXT}"; then
            error "Failed to extract archive"
        fi
        BINARY_NAME="${BINARY_NAME}.exe"
    else
        if ! tar xzf "ryvn${ARCHIVE_EXT}"; then
            error "Failed to extract archive"
        fi
    fi
    
    # Ensure install directory exists and is writable
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR" || error "Failed to create installation directory"
    fi
    
    # Install binary
    if ! mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"; then
        error "Failed to move binary to installation directory"
    fi
    
    if ! chmod +x "$INSTALL_DIR/$BINARY_NAME"; then
        error "Failed to make binary executable"
    fi
    
    step "Verifying installation..."
    verify_installation
    
    echo -e "${GREEN}Successfully installed $BINARY_NAME to $INSTALL_DIR/$BINARY_NAME${NC}"
    echo -e "Run '${BLUE}ryvn --help${NC}' to get started"
}

main
