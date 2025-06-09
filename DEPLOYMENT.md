# Deployment Guide for Google Cloud Run

This guide will help you set up continuous deployment from your repository to Google Cloud Run.

## Prerequisites

- Google Cloud Project with billing enabled
- gcloud CLI installed and authenticated
- Repository connected to GitHub/GitLab/Bitbucket

## Step 1: Set up Google Cloud Infrastructure

Run the setup script to create all necessary cloud resources:

```bash
chmod +x setup-infrastructure.sh
./setup-infrastructure.sh
```

This script will:
- Enable required Google Cloud APIs
- Create Cloud SQL PostgreSQL instance
- Create Redis instance
- Set up secrets in Secret Manager
- Configure IAM permissions

## Step 2: Connect Repository to Cloud Build

1. Go to the [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to Cloud Build > Triggers
3. Click "Connect Repository"
4. Select your source provider (GitHub, GitLab, etc.)
5. Authenticate and select your repository
6. Choose "Create a trigger"

## Step 3: Create Build Trigger

Configure your trigger with these settings:

### Basic Configuration
- **Name**: `gemini-fullstack-langgraph-deploy`
- **Event**: Push to a branch
- **Source**: Your connected repository
- **Branch**: `^main$` (or your preferred branch)

### Build Configuration
- **Type**: Cloud Build configuration file
- **Location**: Repository
- **Cloud Build configuration file location**: `cloudbuild.yaml`

### Substitution Variables
Add these substitution variables (get the values from the setup script output):

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `_GEMINI_API_KEY` | Your Gemini API Key | `your-gemini-api-key` |
| `_LANGSMITH_API_KEY` | Your LangSmith API Key (optional) | `your-langsmith-key` |
| `_POSTGRES_URI` | PostgreSQL connection string | From setup script |
| `_REDIS_URI` | Redis connection string | From setup script |

### Advanced Configuration (Optional)
- **Service account**: Use the default Cloud Build service account
- **Machine type**: e2-highcpu-8 (for faster builds)

## Step 4: Test the Deployment

1. Push a commit to your configured branch
2. Go to Cloud Build > History to monitor the build
3. Once complete, check Cloud Run > Services to see your deployed app

## Step 5: Access Your Application

After successful deployment:
1. Go to Cloud Run > Services
2. Click on your `gemini-fullstack-langgraph` service
3. Copy the service URL
4. Access your app at: `https://your-service-url/app`

## Environment Variables

Your application uses these environment variables (automatically configured):

- `GEMINI_API_KEY`: Your Gemini API key for AI functionality
- `LANGSMITH_API_KEY`: LangSmith API key for monitoring (optional)
- `POSTGRES_URI`: PostgreSQL database connection string
- `REDIS_URI`: Redis connection string for caching

## Troubleshooting

### Build Failures
- Check Cloud Build logs for detailed error messages
- Ensure all substitution variables are correctly set
- Verify your API keys are valid

### Runtime Errors
- Check Cloud Run logs for application errors
- Verify database connections are working
- Ensure all secrets are properly configured

### Permission Issues
- Verify Cloud Build service account has necessary permissions
- Check that Secret Manager secrets are accessible
- Ensure Cloud SQL and Redis instances are in the same region

## Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Build and tag the image
docker build -t gcr.io/YOUR_PROJECT_ID/gemini-fullstack-langgraph:latest .

# Push to Container Registry
docker push gcr.io/YOUR_PROJECT_ID/gemini-fullstack-langgraph:latest

# Deploy to Cloud Run
gcloud run deploy gemini-fullstack-langgraph \
  --image gcr.io/YOUR_PROJECT_ID/gemini-fullstack-langgraph:latest \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8000 \
  --memory 2Gi \
  --cpu 2
```

## Cost Optimization

- **Cloud SQL**: Start with db-g1-small tier, scale as needed
- **Redis**: Basic tier is sufficient for development
- **Cloud Run**: Uses pay-per-use pricing, scales to zero when idle
- **Cloud Build**: 120 free build minutes per day

## Security Considerations

- API keys are stored securely in Secret Manager
- Cloud Run service uses least-privilege IAM
- Database connections use Cloud SQL Proxy for security
- All traffic uses HTTPS

## Next Steps

- Set up monitoring with Cloud Monitoring
- Configure custom domains
- Set up staging environments
- Implement health checks
- Add automated testing to the CI/CD pipeline 