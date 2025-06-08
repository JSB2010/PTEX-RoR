# PTEX Vercel Deployment Guide

## Current Status
Your Rails application is now configured for Vercel deployment with proper error handling and status pages.

## What's Fixed
1. **Vercel Configuration**: Added `vercel.json` with proper Ruby runtime configuration
2. **Database Error Handling**: Added graceful handling when database is unavailable
3. **Status Pages**: Created status controller and views to show deployment progress
4. **Static Fallback**: Added `public/index.html` as a fallback page
5. **Route Updates**: Modified routes to handle database unavailability

## To Complete the Deployment

### 1. Database Setup
You need to set up a PostgreSQL database. Recommended free options:
- **Supabase** (recommended): https://supabase.com
- **Railway**: https://railway.app
- **Neon**: https://neon.tech
- **ElephantSQL**: https://www.elephantsql.com

### 2. Environment Variables
In your Vercel dashboard, add these environment variables:
```
DATABASE_URL=postgresql://username:password@host:port/database
RAILS_MASTER_KEY=your_master_key_from_config/master.key
REDIS_URL=redis://your-redis-url (optional, for caching)
```

### 3. Deploy
```bash
# Commit your changes
git add .
git commit -m "Add Vercel deployment configuration"
git push origin main

# Vercel will automatically redeploy
```

### 4. Run Migrations
After deployment, you'll need to run migrations. You can do this by:
1. Setting up a one-time deployment script, or
2. Using Vercel's serverless functions to run migrations
3. Running migrations directly on your database provider

## How It Works Now

1. **First Visit**: Users see a status page showing deployment progress
2. **Database Available**: Users are redirected to the normal login flow
3. **Database Unavailable**: Users see helpful information about the deployment status
4. **Error Handling**: All database errors gracefully redirect to status page

## Testing Locally

```bash
# Set environment variable to simulate Vercel
export VERCEL_DEPLOYMENT=true

# Start the server
rails server

# Visit http://localhost:3000 to see the status page
```

## Troubleshooting

- **404 Errors**: Check that `vercel.json` is properly configured
- **Database Errors**: Verify DATABASE_URL is set correctly
- **Static Assets**: Ensure RAILS_SERVE_STATIC_FILES=true is set
- **Logs**: Check Vercel function logs for detailed error information
