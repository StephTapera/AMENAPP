#!/bin/bash

# 🚀 Genkit Quick Start Script
# Run this to start your Genkit backend in one command!

set -e  # Exit on error

echo "🙏 Starting Genkit Backend for Berean AI"
echo "========================================"
echo ""

# Color codes for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Check if we're in the right directory
if [ ! -d "genkit" ]; then
    echo -e "${RED}❌ Error: genkit directory not found${NC}"
    echo "Please run this script from your AMENAPP project root"
    echo ""
    echo "Example:"
    echo "  cd /path/to/AMENAPP"
    echo "  ./start-genkit.sh"
    exit 1
fi

# Step 2: Navigate to genkit directory
echo -e "${BLUE}📂 Navigating to genkit directory...${NC}"
cd genkit

# Step 3: Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed${NC}"
    echo "Please install Node.js 20+ from https://nodejs.org"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo -e "${RED}❌ Node.js version must be 20 or higher${NC}"
    echo "Current version: $(node -v)"
    echo "Please upgrade from https://nodejs.org"
    exit 1
fi

echo -e "${GREEN}✅ Node.js $(node -v) detected${NC}"

# Step 4: Check if dependencies are installed
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}⚠️  Dependencies not found. Installing...${NC}"
    npm install
    echo -e "${GREEN}✅ Dependencies installed${NC}"
else
    echo -e "${GREEN}✅ Dependencies already installed${NC}"
fi

# Step 5: Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env file not found${NC}"
    
    if [ -f ".env.example" ]; then
        echo -e "${BLUE}📝 Creating .env from template...${NC}"
        cp .env.example .env
        echo -e "${GREEN}✅ .env file created${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT: Add your Google AI API key to .env${NC}"
        echo ""
        echo "Steps:"
        echo "1. Get key: https://makersuite.google.com/app/apikey"
        echo "2. Edit: nano .env"
        echo "3. Replace: GOOGLE_AI_API_KEY=your_actual_key"
        echo ""
        read -p "Press Enter when ready to continue..."
    else
        echo -e "${RED}❌ .env.example not found. Cannot create .env${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ .env file exists${NC}"
fi

# Step 6: Verify API key is set
if grep -q "your_google_ai_api_key_here" .env 2>/dev/null || grep -q "your_actual_api_key" .env 2>/dev/null; then
    echo -e "${RED}❌ API key not configured in .env${NC}"
    echo ""
    echo "Please edit .env and add your Google AI API key:"
    echo "  nano .env"
    echo ""
    echo "Get your key: https://makersuite.google.com/app/apikey"
    exit 1
fi

echo -e "${GREEN}✅ API key configured${NC}"

# Step 7: Check if Genkit CLI is installed
if ! command -v genkit &> /dev/null; then
    echo -e "${YELLOW}⚠️  Genkit CLI not found. Installing globally...${NC}"
    npm install -g genkit
    echo -e "${GREEN}✅ Genkit CLI installed${NC}"
else
    echo -e "${GREEN}✅ Genkit CLI already installed${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🚀 Starting Genkit Development Server${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Server will be available at:${NC}"
echo -e "  📡 API: ${GREEN}http://localhost:3400${NC}"
echo -e "  🎨 UI:  ${GREEN}http://localhost:4000${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""

# Step 8: Start the server
npm run dev

# If server stops
echo ""
echo -e "${BLUE}👋 Genkit server stopped${NC}"
