#!/bin/bash

# PTEX Railway Deployment Script
# This script helps deploy your Rails app to Railway

echo "🚀 PTEX Railway Deployment Helper"
echo "=================================="

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found. Installing..."
    npm install -g @railway/cli
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install Railway CLI. Please install Node.js first:"
        echo "   https://nodejs.org/"
        exit 1
    fi
fi

echo "✅ Railway CLI found"

# Check if user is logged in
if ! railway whoami &> /dev/null; then
    echo "🔐 Please log in to Railway..."
    railway login
    if [ $? -ne 0 ]; then
        echo "❌ Login failed. Please try again."
        exit 1
    fi
fi

echo "✅ Logged in to Railway"

# Initialize Railway project
echo "🏗️  Initializing Railway project..."
railway init

if [ $? -ne 0 ]; then
    echo "❌ Failed to initialize Railway project"
    exit 1
fi

echo "✅ Railway project initialized"

# Set environment variables
echo "🔧 Setting up environment variables..."

# Check if master key exists
if [ -f "config/master.key" ]; then
    MASTER_KEY=$(cat config/master.key)
    railway variables set RAILS_MASTER_KEY="$MASTER_KEY"
    echo "✅ RAILS_MASTER_KEY set"
else
    echo "⚠️  config/master.key not found. You'll need to set RAILS_MASTER_KEY manually"
fi

# Set other required variables
railway variables set RAILS_ENV=production
railway variables set RAILS_SERVE_STATIC_FILES=true
railway variables set RAILS_LOG_TO_STDOUT=true

echo "✅ Environment variables configured"

# Add PostgreSQL database
echo "🗄️  Adding PostgreSQL database..."
railway add postgresql

echo "✅ PostgreSQL database added"

# Deploy the application
echo "🚀 Deploying application..."
railway up

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Deployment successful!"
    echo ""
    echo "Next steps:"
    echo "1. Run database migrations: railway run rails db:migrate"
    echo "2. Create admin user: railway run rails db:seed"
    echo "3. Check your app: railway open"
    echo ""
    echo "Useful commands:"
    echo "- View logs: railway logs"
    echo "- Open shell: railway shell"
    echo "- View variables: railway variables"
else
    echo "❌ Deployment failed. Check the logs with: railway logs"
    exit 1
fi
