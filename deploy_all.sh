#!/bin/bash

CSV_FILE="/mnt/data/sites_config.csv"
REGION="us-east-1"
EXPORT_DIR="/mnt/data/simply-static"
USERNAME="REDACTED"
PASSWORD="REDACTED"
BUCKET_NAME="REDACTED"
LOG_FILE="/mnt/data/deploy_log.txt"

# AWS credentials (replace with actual keys)
AWS_ACCESS_KEY_ID="REDACTED"
AWS_SECRET_ACCESS_KEY="REDACTED"
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# Function to add timestamps to log entries
log() {
  local message="$*"
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

deploy_to_s3() {
  local export_directory=$1
  local s3_path=$2
  local distribution_id=$3

  if [ -z "$s3_path" ]; then
    log "S3 path is missing. Skipping deployment."
    return 1
  fi

  log "Deploying $export_directory to s3://$BUCKET_NAME/$s3_path"
  aws s3 sync "$export_directory" "s3://$BUCKET_NAME/$s3_path" --region "$REGION"

  if [ $? -eq 0 ]; then
    log "Successfully deployed $export_directory to s3://$BUCKET_NAME/$s3_path"
    invalidate_cloudfront "$distribution_id"
  else
    log "Failed to deploy $export_directory to s3://$BUCKET_NAME/$s3_path"
  fi
}

invalidate_cloudfront() {
  local distribution_id=$1

  if [ -z "$distribution_id" ]; then
    log "Distribution ID is missing. Skipping CloudFront invalidation."
    return 1
  fi

  # Check if the CloudFront distribution exists
  log "Checking CloudFront distribution ID $distribution_id"
  distribution_output=$(aws cloudfront get-distribution --id "$distribution_id" 2>&1)
  log "AWS CLI get-distribution output: $distribution_output"
  if [ $? -ne 0 ]; then
    log "CloudFront distribution ID $distribution_id does not exist. Skipping invalidation."
    return 1
  fi

  log "Invalidating CloudFront distribution $distribution_id"
  invalidation_output=$(aws cloudfront create-invalidation --distribution-id "$distribution_id" --paths "/*" 2>&1)
  if [ $? -eq 0 ]; then
    log "Successfully invalidated CloudFront distribution $distribution_id"
  else
    log "Failed to invalidate CloudFront distribution $distribution_id"
    log "AWS CLI Output: $invalidation_output"
  fi
}

# Deactivate Easy Basic Authentication plugin
log "Deactivating Easy Basic Authentication plugin"
sudo wp plugin deactivate easy-basic-authentication --network

# Create the export directory if it doesn't exist
sudo mkdir -p "$EXPORT_DIR"

log "Starting static generation from CSV file: $CSV_FILE"

# Check if CSV file exists and is not empty
if [ ! -s "$CSV_FILE" ]; then
  log "CSV file is empty or does not exist: $CSV_FILE"
  exit 1
fi

# Skip the header row
tail -n +2 "$CSV_FILE" | while IFS=, read -r site_url page_url s3_path cloudfront_distribution_id; do
  site_url=$(echo "$site_url" | tr -d '[:space:]')
  page_url=$(echo "$page_url" | tr -d '[:space:]')
  s3_path=$(echo "$s3_path" | tr -d '[:space:]')
  cloudfront_distribution_id=$(echo "$cloudfront_distribution_id" | tr -d '[:space:]')

  log "Processing site: $site_url"
  log "Using Distribution ID: $cloudfront_distribution_id"

  # Ensure variables are trimmed and logged
  log "Trimmed values - Site URL: $site_url, Page URL: $page_url, S3 Path: $s3_path, Distribution ID: $cloudfront_distribution_id"

  # Check if the site is accessible with Basic Auth
  response=$(curl -u "$USERNAME:$PASSWORD" -k -I "$site_url")
  http_code=$(echo "$response" | grep HTTP | awk '{print $2}')

  if [[ "$http_code" -eq 200 ]]; then
    log "Site is accessible, proceeding with static file generation"

    sudo wp --url="$site_url" simply-static run

    if [ $? -eq 0 ]; then
      log "Successfully generated static files for $site_url"
      log "Contents of export directory:"
      ls -l "$EXPORT_DIR/$s3_path"
      log "S3 Path: $s3_path"
      log "Distribution ID: $cloudfront_distribution_id"
      deploy_to_s3 "$EXPORT_DIR" "$s3_path" "$cloudfront_distribution_id"
    else
      log "Failed to generate static files for $site_url"
    fi
  else
    log "Failed to access $site_url, HTTP response code: $http_code"
  fi

done

# Reactivate Easy Basic Authentication plugin
log "Reactivating Easy Basic Authentication plugin"
sudo wp plugin activate easy-basic-authentication --network
