#!/bin/bash
# Vaakya Doctor — Preflight Checks
# Validates developer environment readiness.

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

errors=0
warnings=0

check_binary() {
    local cmd=$1
    local name=$2
    local required=${3:-required}  # "required" or "optional"
    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" --version 2>&1 | head -n 1 || echo "")
        echo -e "${GREEN}✅ $name${NC}  ${version}"
    else
        if [ "$required" = "optional" ]; then
            echo -e "${YELLOW}⚠️  $name missing (optional)${NC}"
            warnings=$((warnings+1))
        else
            echo -e "${RED}❌ $name missing${NC}"
            errors=$((errors+1))
        fi
    fi
}

check_port() {
    local port=$1
    local name=$2
    if lsof -i :"$port" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Port $port ($name) already in use${NC}"
        warnings=$((warnings+1))
    else
        echo -e "${GREEN}✅ Port $port available ($name)${NC}"
    fi
}

echo -e "${BLUE}🧪 Vaakya Doctor — Environment Check${NC}"
echo ""

# 1. Toolchain
echo -e "${BLUE}1. Toolchain${NC}"
check_binary brew     "Homebrew"
check_binary xcodegen "xcodegen"
check_binary uv       "uv (Python)"
check_binary aws      "AWS CLI"           optional
check_binary terraform "Terraform"        optional
check_binary docker   "Docker"            optional

# 2. Xcode Command Line Tools
echo ""
echo -e "${BLUE}2. Xcode${NC}"
if xcode-select -p &>/dev/null; then
    echo -e "${GREEN}✅ Xcode CLT${NC}  ($(xcode-select -p))"
else
    echo -e "${RED}❌ Xcode Command Line Tools missing${NC}"
    echo "   👉 Fix: xcode-select --install"
    errors=$((errors+1))
fi
if command -v xcodebuild &>/dev/null; then
    echo -e "${GREEN}✅ xcodebuild${NC}  $(xcodebuild -version 2>/dev/null | head -n1)"
else
    echo -e "${RED}❌ xcodebuild missing${NC}"
    errors=$((errors+1))
fi

# 3. Docker daemon (only if Docker is installed)
echo ""
echo -e "${BLUE}3. Docker${NC}"
if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
        echo -e "${GREEN}✅ Docker daemon running${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker installed but daemon not running${NC}"
        echo "   👉 Fix: open -a Docker (only needed for backend-deploy-*)"
        warnings=$((warnings+1))
    fi
else
    echo -e "${YELLOW}⚠️  Docker not installed (only needed for backend-deploy-*)${NC}"
fi

# 4. AWS (only if AWS CLI is installed)
echo ""
echo -e "${BLUE}4. AWS${NC}"
if command -v aws &>/dev/null; then
    PROFILE=${AWS_PROFILE:-vaakya-dev}
    if aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
        echo -e "${GREEN}✅ AWS profile '$PROFILE' configured${NC}"
    else
        echo -e "${YELLOW}⚠️  AWS profile '$PROFILE' not configured${NC}"
        echo "   👉 Fix: aws configure sso --profile $PROFILE  (only needed for stg/prod)"
        warnings=$((warnings+1))
    fi
else
    echo -e "${YELLOW}⚠️  AWS CLI not installed (only needed for stg/prod)${NC}"
fi

# 5. Ports
echo ""
echo -e "${BLUE}5. Ports${NC}"
check_port 8002 "Backend (local FastAPI)"

# Summary
echo ""
echo -e "${BLUE}Summary${NC}"
echo "  Errors:   $errors"
echo "  Warnings: $warnings"
echo ""
if [ "$errors" -gt 0 ]; then
    echo -e "${RED}❌ Doctor found issues. Run 'make setup' to install missing tools.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Environment ready.${NC}"
fi
