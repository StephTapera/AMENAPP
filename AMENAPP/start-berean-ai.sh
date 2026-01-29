#!/bin/bash

# 🚀 Berean AI - Quick Start Script
# This script helps you get Genkit running quickly

echo "🎯 Berean AI - Starting Genkit Server"
echo "======================================"
echo ""

# Check if we're in the right directory
if [ ! -d "genkit" ]; then
    echo "❌ Error: genkit folder not found"
    echo "Please run this script from your project root"
    exit 1
fi

# Navigate to genkit folder
cd genkit

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo "✅ Dependencies installed"
    echo ""
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  Warning: .env file not found"
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo ""
    echo "🔑 Please add your Google AI API key to genkit/.env"
    echo "Get your API key from: https://aistudio.google.com/app/apikey"
    echo ""
    echo "Edit genkit/.env and add:"
    echo "GOOGLE_AI_API_KEY=your_api_key_here"
    echo ""
    read -p "Press Enter when you've added your API key..."
fi

# Start the dev server
echo "🚀 Starting Genkit server..."
echo ""
echo "✅ Developer UI will be at: http://localhost:4000"
echo "✅ API endpoint will be at: http://localhost:3400"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

npm run dev
