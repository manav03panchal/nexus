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
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }

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
    git clone --depth 1 "$REPO_URL" "$tmp_dir" > /dev/null 2>&1

    cd "$tmp_dir"

    info "Fetching dependencies..."
    mix local.hex --force > /dev/null 2>&1
    mix deps.get --only prod > /dev/null 2>&1

    info "Building..."
    MIX_ENV=prod mix escript.build > /dev/null 2>&1

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
    echo "  _   _                    "
    echo " | \\ | | _____  ___   _ ___ "
    echo " |  \\| |/ _ \\ \\/ / | | / __|"
    echo " | |\\  |  __/>  <| |_| \\__ \\"
    echo " |_| \\_|\\___/_/\\_\\\\__,_|___/"
    echo ""
    echo " Distributed Task Runner"
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
