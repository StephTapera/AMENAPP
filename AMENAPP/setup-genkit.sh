#!/bin/bash

# Berean AI Genkit - Quick Setup Script
# This script automates the setup process for Genkit integration

set -e  # Exit on error

echo "🙏 Berean AI Genkit Setup"
echo "=========================="
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed"
    echo "Please install Node.js 20+ from https://nodejs.org"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo "❌ Node.js version must be 20 or higher"
    echo "Current version: $(node -v)"
    echo "Please upgrade from https://nodejs.org"
    exit 1
fi

echo "✅ Node.js $(node -v) detected"
echo ""

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed"
    exit 1
fi

echo "✅ npm $(npm -v) detected"
echo ""

# Install Genkit CLI if not already installed
if ! command -v genkit &> /dev/null; then
    echo "📦 Installing Genkit CLI globally..."
    npm install -g genkit
    echo "✅ Genkit CLI installed"
else
    echo "✅ Genkit CLI already installed"
fi

echo ""

# Navigate to genkit directory
if [ ! -d "genkit" ]; then
    echo "❌ genkit directory not found"
    echo "Please run this script from the project root"
    exit 1
fi

cd genkit

# Install dependencies
echo "📦 Installing dependencies..."
npm install

echo "✅ Dependencies installed"
echo ""

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo "📝 Creating .env file..."
    cp .env.example .env
    echo "✅ .env file created"
    echo ""
    echo "⚠️  IMPORTANT: You need to add your Google AI API key to the .env file"
    echo ""
    echo "Steps:"
    echo "1. Go to https://makersuite.google.com/app/apikey"
    echo "2. Create a new API key"
    echo "3. Edit genkit/.env and replace 'your_google_ai_api_key_here' with your key"
    echo ""
    read -p "Press Enter when you've added your API key..."
else
    echo "✅ .env file already exists"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. Start the Genkit development server:"
echo "   cd genkit && npm run dev"
echo ""
echo "2. Open the Genkit Developer UI:"
echo "   http://localhost:4000"
echo ""
echo "3. Configure your iOS app (Info.plist):"
echo "   <key>GENKIT_ENDPOINT</key>"
echo "   <string>http://localhost:3400</string>"
echo ""
echo "4. Test the integration in your iOS app!"
echo ""
echo "📖 Full documentation: GENKIT_INTEGRATION_GUIDE.md"
echo ""
