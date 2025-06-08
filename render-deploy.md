# PTEX Render Deployment Guide

## Quick Deployment Steps

### 1. Connect Repository
1. Go to [render.com](https://render.com) and sign up/login
2. Click "New +" → "Web Service"
3. Connect your GitHub account and select the `PTEX-RoR` repository

### 2. Configure Service
**Basic Settings:**
- **Name**: `ptex-lms` (or your preferred name)
- **Environment**: `Ruby`
- **Region**: Choose closest to your users
- **Branch**: `main`

**Build & Deploy:**
- **Build Command**: 
  ```bash
  bundle install && rails assets:precompile && rails db:migrate
  ```
- **Start Command**: 
  ```bash
  bundle exec puma -C config/puma.rb
  ```

### 3. Environment Variables
Add these in the "Environment" section:

```
RAILS_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true
RAILS_MASTER_KEY=<your-master-key-from-config/master.key>
```

### 4. Database Setup
1. After creating the web service, go to "New +" → "PostgreSQL"
2. **Name**: `ptex-database`
3. **Database Name**: `ptex_production`
4. **User**: `ptex_user`
5. Click "Create Database"

### 5. Connect Database
1. Go back to your web service
2. In "Environment" section, add:
   ```
   DATABASE_URL=<internal-database-url-from-render>
   ```
   (Render will provide this URL in your PostgreSQL service dashboard)

### 6. Deploy
1. Click "Create Web Service"
2. Render will automatically deploy your application
3. Monitor the build logs for any issues

### 7. Post-Deployment
After successful deployment:

1. **Run Database Seeds** (if you have them):
   - Go to your web service dashboard
   - Click "Shell" tab
   - Run: `rails db:seed`

2. **Create Admin User** (if needed):
   ```ruby
   rails console
   User.create!(
     email: 'admin@example.com',
     password: 'secure_password',
     first_name: 'Admin',
     last_name: 'User',
     role: 'admin'
   )
   ```

## Troubleshooting

### Common Issues:
1. **Build fails**: Check that all gems are in Gemfile
2. **Database connection**: Verify DATABASE_URL is correct
3. **Assets not loading**: Ensure RAILS_SERVE_STATIC_FILES=true
4. **Master key error**: Check RAILS_MASTER_KEY is set correctly

### Useful Commands in Render Shell:
```bash
# Check database connection
rails db:version

# View logs
tail -f log/production.log

# Check environment
env | grep RAILS

# Run console
rails console
```

## Benefits of Render for Rails:
- ✅ Free tier available
- ✅ Automatic SSL certificates
- ✅ Built-in PostgreSQL
- ✅ Easy environment variable management
- ✅ Automatic deployments from Git
- ✅ Built-in monitoring and logs
