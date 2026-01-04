#!/usr/bin/env bash
set -euo pipefail

# Nexus Build Script
# Builds the nexus escript binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Building Nexus..."
echo "================"

# Check for Elixir
if ! command -v elixir &> /dev/null; then
    echo "Error: Elixir is not installed"
    echo "Install from: https://elixir-lang.org/install.html"
    exit 1
fi

echo "Elixir version: $(elixir --version | head -1)"

# Get dependencies
echo ""
echo "Fetching dependencies..."
mix deps.get --only prod

# Compile
echo ""
echo "Compiling..."
MIX_ENV=prod mix compile

# Build assets for web dashboard
echo ""
echo "Building web assets..."
MIX_ENV=prod mix assets.build

# Build escript
echo ""
echo "Building escript..."
MIX_ENV=prod mix escript.build

# Make executable
chmod +x nexus

# Show result
echo ""
echo "Build complete!"
echo "Binary: $(pwd)/nexus"
echo "Size: $(du -h nexus | cut -f1)"
echo ""
echo "Run './nexus --help' to get started"
