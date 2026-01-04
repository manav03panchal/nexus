#!/usr/bin/env bash
set -eo pipefail

# Nexus Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/manav03panchal/nexus/main/scripts/install.sh | bash

REPO_URL="https://github.com/manav03panchal/nexus.git"
INSTALL_DIR="${NEXUS_INSTALL_DIR:-/usr/local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

# Run a command silently, showing output only on failure
run() {
    local output
    if ! output=$(eval "$*" 2>&1); then
        echo ""
        echo -e "${RED}Command failed:${NC} $*"
        echo -e "${DIM}${output}${NC}" | tail -20
        return 1
    fi
}

check_dependencies() {
    if ! command -v elixir &> /dev/null; then
        error "Elixir is not installed. Install from: https://elixir-lang.org/install.html"
    fi

    if ! command -v mix &> /dev/null; then
        error "Mix is not available. Ensure Elixir is properly installed."
    fi

    if ! command -v git &> /dev/null; then
        error "Git is not installed."
    fi

    info "Elixir $(elixir --version | grep Elixir | awk '{print $2}')"
}

install_nexus() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    info "Cloning repository..."
    run git clone --depth 1 "$REPO_URL" "$tmp_dir" || error "Failed to clone repository"

    cd "$tmp_dir"

    info "Fetching dependencies..."
    run mix local.hex --force || error "Failed to install Hex"
    run mix deps.get --only prod || error "Failed to fetch dependencies"

    info "Building assets..."
    run MIX_ENV=prod mix assets.build || error "Asset build failed"

    info "Building escript..."
    run MIX_ENV=prod mix escript.build || error "Build failed"

    info "Installing to ${INSTALL_DIR}..."
    if [[ -w "$INSTALL_DIR" ]]; then
        mv nexus "$INSTALL_DIR/nexus"
    else
        sudo mv nexus "$INSTALL_DIR/nexus"
    fi

    chmod +x "$INSTALL_DIR/nexus"

    success "Installed: $("$INSTALL_DIR/nexus" --version)"
}

main() {
    echo ""
    cat << 'EOF'
 ________   _______      ___    ___  ___  ___  ________
|\   ___  \|\  ___ \    |\  \  /  /|\  \|\  \|\   ____\
\ \  \\ \  \ \   __/|   \ \  \/  / | \  \\\  \ \  \___|_
 \ \  \\ \  \ \  \_|/__  \ \    / / \ \  \\\  \ \_____  \
  \ \  \\ \  \ \  \_|\ \  /     \/   \ \  \\\  \|____|\  \
   \ \__\\ \__\ \_______\/  /\   \    \ \_______\____\_\  \
    \|__| \|__|\|_______/__/ /\ __\    \|_______|\_________\
                        |__|/ \|__|             \|_________|
EOF
    echo ""

    check_dependencies
    install_nexus

    echo ""
    success "Nexus installed successfully!"
    echo ""
    echo "Get started:"
    echo "  nexus init        # Create a config file"
    echo "  nexus --help      # Show help"
    echo ""
}

main "$@"
