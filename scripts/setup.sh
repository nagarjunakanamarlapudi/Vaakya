#!/bin/bash
# Vaakya Setup — Install project dependencies.
# Idempotent: skips anything already installed.

set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📦 Vaakya Setup — Installing dependencies${NC}"
echo ""

# 1. Homebrew (prerequisite)
if ! command -v brew &>/dev/null; then
    echo -e "${RED}❌ Homebrew not installed.${NC}"
    echo "   Install it first: https://brew.sh"
    echo "   Then re-run 'make setup'."
    exit 1
fi
echo -e "${GREEN}✅ Homebrew found${NC}"

# 2. Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo -e "${YELLOW}⚙️  Installing Xcode Command Line Tools (a GUI prompt will appear)…${NC}"
    xcode-select --install || true
    echo -e "${YELLOW}   Re-run 'make setup' once the install completes.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Xcode Command Line Tools${NC}"

# 3. Brew packages — only install what's missing
install_brew_pkg() {
    local pkg=$1
    local bin=${2:-$1}
    if command -v "$bin" &>/dev/null; then
        echo -e "${GREEN}✅ $pkg already installed${NC}"
    else
        echo -e "${YELLOW}⚙️  Installing ${pkg}…${NC}"
        brew install "$pkg"
    fi
}

echo ""
echo -e "${BLUE}Brew packages${NC}"
install_brew_pkg xcodegen
install_brew_pkg uv
install_brew_pkg awscli aws

# Terraform — HashiCorp relicensed under BSL (Aug 2023), removed from Homebrew Core.
# Install via the official HashiCorp tap.
if command -v terraform &>/dev/null; then
    echo -e "${GREEN}✅ terraform already installed${NC}"
else
    echo -e "${YELLOW}⚙️  Installing terraform (via hashicorp/tap)…${NC}"
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
fi

# 4. Docker — heavyweight cask, ask before installing
echo ""
echo -e "${BLUE}Docker${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}✅ Docker already installed${NC}"
else
    echo -e "${YELLOW}⚠️  Docker not installed.${NC}"
    echo "   Needed only for: backend-deploy-stg / backend-deploy-prod."
    read -r -p "   Install Docker Desktop now via Homebrew Cask? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        brew install --cask docker
        echo -e "${YELLOW}   Launch Docker Desktop once to finish setup.${NC}"
    else
        echo "   Skipped. Install later: brew install --cask docker"
    fi
fi

# 5. Python deps (backend)
echo ""
echo -e "${BLUE}Python dependencies (uv sync)${NC}"
if [ -f "pyproject.toml" ]; then
    uv sync
    echo -e "${GREEN}✅ Python deps installed${NC}"
else
    echo -e "${YELLOW}⚠️  pyproject.toml not found — skipping uv sync${NC}"
fi

# 6. Run doctor
echo ""
echo -e "${BLUE}Running doctor to verify…${NC}"
echo ""
./scripts/doctor.sh || true

echo ""
echo -e "${GREEN}✅ Setup complete.${NC}"
echo ""
echo "Next steps:"
echo "  ▶ Run app:     make app-run"
echo "  ▶ Run backend: make backend-run"
echo "  ▶ See all:     make help"
