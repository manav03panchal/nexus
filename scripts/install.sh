#!/usr/bin/env bash
set -euo pipefail

# Nexus Installer
#
# For private repos, requires GITHUB_TOKEN environment variable:
#   GITHUB_TOKEN=ghp_xxx ./install.sh
#
# Or for local builds:
#   ./scripts/build.sh

REPO="manav03panchal/nexus"
INSTALL_DIR="${NEXUS_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${NEXUS_VERSION:-latest}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

# Detect OS and architecture
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="darwin" ;;
        *)       error "Unsupported OS: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        arm64|aarch64) arch="aarch64" ;;
        *)             error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}-${arch}"
}

# Build auth header if token provided
auth_header() {
    if [[ -n "$GITHUB_TOKEN" ]]; then
        echo "Authorization: token ${GITHUB_TOKEN}"
    else
        echo ""
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local header
    header=$(auth_header)

    if [[ -n "$header" ]]; then
        curl -fsSL -H "$header" "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name":' \
            | sed -E 's/.*"([^"]+)".*/\1/'
    else
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name":' \
            | sed -E 's/.*"([^"]+)".*/\1/'
    fi
}

# Download and install
install_nexus() {
    local platform version download_url tmp_dir

    platform=$(detect_platform)
    info "Detected platform: ${platform}"

    # Get version
    if [[ "$VERSION" == "latest" ]]; then
        info "Fetching latest version..."
        version=$(get_latest_version)
        if [[ -z "$version" ]]; then
            error "Could not determine latest version. Please specify NEXUS_VERSION."
        fi
    else
        version="$VERSION"
    fi
    info "Installing version: ${version}"

    # Construct download URL
    download_url="https://github.com/${REPO}/releases/download/${version}/nexus-${platform}"
    info "Downloading from: ${download_url}"

    # Create temp directory
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Download (with auth for private repos)
    local header
    header=$(auth_header)

    if [[ -n "$header" ]]; then
        if ! curl -fsSL -H "$header" -H "Accept: application/octet-stream" -o "${tmp_dir}/nexus" "$download_url"; then
            error "Download failed. Check that version ${version} exists and has binaries for ${platform}."
        fi
    else
        if ! curl -fsSL -o "${tmp_dir}/nexus" "$download_url"; then
            error "Download failed. For private repos, set GITHUB_TOKEN environment variable."
        fi
    fi

    # Make executable
    chmod +x "${tmp_dir}/nexus"

    # Create install directory if needed
    mkdir -p "$INSTALL_DIR"

    # Install
    mv "${tmp_dir}/nexus" "${INSTALL_DIR}/nexus"
    success "Installed nexus to ${INSTALL_DIR}/nexus"

    # Verify installation
    if "${INSTALL_DIR}/nexus" --version &>/dev/null; then
        success "Installation verified: $(${INSTALL_DIR}/nexus --version)"
    else
        warn "Installation complete but verification failed"
    fi

    # Check if in PATH
    if ! command -v nexus &>/dev/null; then
        echo ""
        warn "nexus is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
        echo ""
        echo "Then restart your shell or run:"
        echo ""
        echo "  source ~/.bashrc  # or ~/.zshrc"
        echo ""
    fi

    echo ""
    success "Nexus installed successfully!"
    echo ""
    echo "Get started:"
    echo "  nexus init        # Create a nexus.exs config"
    echo "  nexus --help      # Show help"
    echo ""
}

# Main
main() {
    echo ""
    echo "  _   _                    "
    echo " | \ | | _____  ___   _ ___ "
    echo " |  \| |/ _ \ \/ / | | / __|"
    echo " | |\  |  __/>  <| |_| \__ \\"
    echo " |_| \_|\___/_/\_\\\\__,_|___/"
    echo ""
    echo " Distributed Task Runner"
    echo ""

    install_nexus
}

main "$@"
