# 🚀 PTEX Railway Deployment Guide

## Why Railway?
- **Generous Free Tier**: $5/month in credits (enough for small-medium apps)
- **Excellent Rails Support**: Built-in Ruby/Rails detection
- **Free PostgreSQL**: Included database with generous limits
- **Zero Configuration**: Automatic deployments from GitHub
- **Easy Environment Management**: Simple variable configuration

## Quick Deployment Steps

### 1. Login to Railway
✅ **Already opened for you**: https://railway.app/login
- Sign up with GitHub (recommended)
- Verify your email if needed

### 2. Create New Project
1. Click **"New Project"**
2. Select **"Deploy from GitHub repo"**
3. Choose **"PTEX-RoR"** repository
4. Click **"Deploy Now"**

### 3. Add PostgreSQL Database
1. In your project dashboard, click **"+ New"**
2. Select **"Database"** → **"Add PostgreSQL"**
3. Railway will automatically create and connect the database

### 4. Configure Environment Variables
Click on your web service, then go to **"Variables"** tab:

**Required Variables:**
```
RAILS_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true
```

**Master Key (Important!):**
```
RAILS_MASTER_KEY=<copy from config/master.key file>
```

### 5. Wait for Deployment
- Railway will automatically build and deploy
- Watch the build logs for any issues
- First deployment takes 3-5 minutes

### 6. Run Database Setup
After successful deployment:
1. Go to your web service
2. Click **"Settings"** → **"Deploy"**
3. In the **"Custom Start Command"** section, temporarily set:
   ```
   ./bin/railway-setup && bundle exec puma -C config/puma.rb
   ```
4. Redeploy to run the setup script
5. After setup completes, remove the setup script from start command:
   ```
   bundle exec puma -C config/puma.rb
   ```

## Default Admin Access
After setup, you can login with:
- **Email**: `admin@ptex.local`
- **Password**: `admin123`

⚠️ **Change this password immediately after first login!**

## Railway Free Tier Limits
- **$5/month in credits** (resets monthly)
- **PostgreSQL**: 1GB storage, 1GB RAM
- **Web Service**: 512MB RAM, shared CPU
- **Bandwidth**: 100GB/month
- **Build Time**: 500 hours/month

## Monitoring Your Usage
- Check usage in Railway dashboard
- Set up billing alerts
- Monitor in **"Usage"** tab

## Troubleshooting

### Build Fails
- Check build logs in Railway dashboard
- Ensure all gems are in Gemfile
- Verify Ruby version compatibility

### Database Connection Issues
- Verify PostgreSQL service is running
- Check DATABASE_URL is automatically set
- Ensure migrations ran successfully

### Application Errors
- Check application logs in Railway
- Verify RAILS_MASTER_KEY is set correctly
- Ensure all environment variables are configured

## Useful Railway Commands (if using CLI)
```bash
# View logs
railway logs

# Open shell
railway shell

# Check variables
railway variables

# Connect to database
railway connect postgresql
```

## Next Steps After Deployment
1. **Change admin password**
2. **Configure email settings** (if needed)
3. **Set up custom domain** (optional)
4. **Configure SSL** (automatic with custom domain)
5. **Set up monitoring** (Railway provides basic monitoring)

## Benefits of This Setup
✅ **Zero cost** (within free tier limits)
✅ **Automatic deployments** from GitHub
✅ **Built-in database** with backups
✅ **SSL certificates** included
✅ **Easy scaling** when needed
✅ **Professional infrastructure**

Your PTEX Learning Management System will be production-ready and accessible worldwide!
