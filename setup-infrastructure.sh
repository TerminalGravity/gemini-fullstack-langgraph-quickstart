#!/bin/bash

# Setup script for Google Cloud infrastructure
# Run this script to set up the necessary services for your app

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    print_error "No project ID found. Please set it with: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

print_status "Using project: $PROJECT_ID"

# Enable required APIs
print_status "Enabling required Google Cloud APIs..."
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    sqladmin.googleapis.com \
    redis.googleapis.com \
    secretmanager.googleapis.com \
    containerregistry.googleapis.com \
    --project=$PROJECT_ID

# Create Cloud SQL PostgreSQL instance
print_status "Creating Cloud SQL PostgreSQL instance..."
POSTGRES_INSTANCE_NAME="gemini-postgres-instance"
if ! gcloud sql instances describe $POSTGRES_INSTANCE_NAME --project=$PROJECT_ID &>/dev/null; then
    gcloud sql instances create $POSTGRES_INSTANCE_NAME \
        --database-version=POSTGRES_15 \
        --tier=db-g1-small \
        --region=us-central1 \
        --storage-type=SSD \
        --storage-size=20GB \
        --storage-auto-increase \
        --backup-start-time=03:00 \
        --project=$PROJECT_ID
    
    print_status "Setting up PostgreSQL database and user..."
    # Database 'postgres' already exists by default, so we'll skip creating it
    # Create the postgres user if it doesn't exist
    if ! gcloud sql users describe postgres --instance=$POSTGRES_INSTANCE_NAME --project=$PROJECT_ID &>/dev/null; then
        gcloud sql users create postgres --instance=$POSTGRES_INSTANCE_NAME --password=postgres --project=$PROJECT_ID
    else
        print_warning "PostgreSQL user 'postgres' already exists"
    fi
else
    print_warning "PostgreSQL instance already exists"
fi

# Create Redis instance
print_status "Creating Redis instance..."
REDIS_INSTANCE_NAME="gemini-redis-instance"
if ! gcloud redis instances describe $REDIS_INSTANCE_NAME --region=us-central1 --project=$PROJECT_ID &>/dev/null; then
    gcloud redis instances create $REDIS_INSTANCE_NAME \
        --size=1 \
        --region=us-central1 \
        --redis-version=redis_6_x \
        --tier=basic \
        --project=$PROJECT_ID
else
    print_warning "Redis instance already exists"
fi

# Wait for instances to be ready
print_status "Waiting for instances to be ready..."
gcloud sql instances describe $POSTGRES_INSTANCE_NAME --project=$PROJECT_ID --format="value(state)" | grep -q "RUNNABLE" || {
    print_status "Waiting for PostgreSQL instance to be ready..."
    while [ "$(gcloud sql instances describe $POSTGRES_INSTANCE_NAME --project=$PROJECT_ID --format='value(state)')" != "RUNNABLE" ]; do
        sleep 10
    done
}

gcloud redis instances describe $REDIS_INSTANCE_NAME --region=us-central1 --project=$PROJECT_ID --format="value(state)" | grep -q "READY" || {
    print_status "Waiting for Redis instance to be ready..."
    while [ "$(gcloud redis instances describe $REDIS_INSTANCE_NAME --region=us-central1 --project=$PROJECT_ID --format='value(state)')" != "READY" ]; do
        sleep 10
    done
}

# Get connection strings
print_status "Getting connection strings..."
POSTGRES_CONNECTION_NAME=$(gcloud sql instances describe $POSTGRES_INSTANCE_NAME --project=$PROJECT_ID --format="value(connectionName)")
REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE_NAME --region=us-central1 --project=$PROJECT_ID --format="value(host)")
REDIS_PORT=$(gcloud redis instances describe $REDIS_INSTANCE_NAME --region=us-central1 --project=$PROJECT_ID --format="value(port)")

# Construct URIs
POSTGRES_URI="postgresql://postgres:postgres@/$POSTGRES_CONNECTION_NAME/postgres?host=/cloudsql"
REDIS_URI="redis://$REDIS_HOST:$REDIS_PORT"

print_status "Connection strings:"
echo "PostgreSQL: $POSTGRES_URI"
echo "Redis: $REDIS_URI"

# Create secrets
print_status "Creating secrets..."

# Function to create or update secret
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    
    if gcloud secrets describe $secret_name --project=$PROJECT_ID &>/dev/null; then
        echo "$secret_value" | gcloud secrets versions add $secret_name --data-file=- --project=$PROJECT_ID
        print_status "Updated secret: $secret_name"
    else
        echo "$secret_value" | gcloud secrets create $secret_name --data-file=- --project=$PROJECT_ID
        print_status "Created secret: $secret_name"
    fi
}

# Create database connection secrets
create_or_update_secret "postgres-uri" "$POSTGRES_URI"
create_or_update_secret "redis-uri" "$REDIS_URI"

# Prompt for API keys
print_warning "Please enter your API keys (they will be stored securely in Google Secret Manager):"

read -p "Enter your Gemini API Key: " GEMINI_API_KEY
if [ ! -z "$GEMINI_API_KEY" ]; then
    create_or_update_secret "gemini-api-key" "$GEMINI_API_KEY"
fi

read -p "Enter your LangSmith API Key (optional, press enter to skip): " LANGSMITH_API_KEY
if [ ! -z "$LANGSMITH_API_KEY" ]; then
    create_or_update_secret "langsmith-api-key" "$LANGSMITH_API_KEY"
fi

# Grant Cloud Run access to secrets
print_status "Setting up IAM permissions..."

# Get the Cloud Build service account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_BUILD_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"

# Grant Cloud Build service account necessary permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CLOUD_BUILD_SA" \
    --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CLOUD_BUILD_SA" \
    --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CLOUD_BUILD_SA" \
    --role="roles/run.admin"

# Also grant the default compute service account (used by Cloud Run)
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/cloudsql.client"

print_status "Infrastructure setup complete!"
print_status "You can now set up Cloud Build triggers to deploy your application."

echo ""
print_status "Next steps:"
echo "1. Connect your repository to Cloud Build"
echo "2. Create a trigger that uses the cloudbuild.yaml file"
echo "3. Set the following substitution variables in your trigger:"
echo "   - _GEMINI_API_KEY: your-gemini-api-key"
echo "   - _LANGSMITH_API_KEY: your-langsmith-api-key (optional)"
echo "   - _POSTGRES_URI: $POSTGRES_URI"
echo "   - _REDIS_URI: $REDIS_URI" 