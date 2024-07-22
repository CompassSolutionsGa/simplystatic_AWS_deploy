#!/bin/bash

# Variables
wp_path="/opt/bitnami/wordpress"
static_base_path="/mnt/data/simply-static"
csv_file="/mnt/data/sites_config.csv"
log_file="/mnt/data/deploy_log.txt"
s3_bucket="REDACTED"
username="REDACTED"  # Replace with your username
password="REDACTED"  # Replace with your password

# AWS credentials (replace with actual keys)
AWS_ACCESS_KEY_ID="REDACTED"
AWS_SECRET_ACCESS_KEY="REDACTED"
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# Counters for successful and failed deployments
success_count=0
failure_count=0

# Function to add timestamps to log entries
log() {
  local message="$*"
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$log_file"
}

# Function to trim whitespace and carriage return characters
trim() {
  local var="$*"
  var="${var%%[[:space:]]}"
  var="${var%%[$'\r']}"
  echo -n "$var"
}

log "Starting static generation from CSV file: $csv_file"

# Check if CSV file exists and is not empty
if [ ! -s "$csv_file" ]; then
  log "CSV file is empty or does not exist: $csv_file"
  exit 1
fi

# Read the CSV file and process each line
while IFS=, read -r site_url page_url s3_path cloudfront_distribution_id || [ -n "$site_url" ]; do
  site_url=$(trim "$site_url")
  page_url=$(trim "$page_url")
  s3_path=$(trim "$s3_path")
  cloudfront_distribution_id=$(trim "$cloudfront_distribution_id")

  log "Processing site: $site_url, page: $page_url"

  # Fetch the alternate domain from CloudFront if available
  alternate_domain=$(aws cloudfront get-distribution --id "$cloudfront_distribution_id" --query 'Distribution.DistributionConfig.Aliases.Items[0]' --output text 2>>"$log_file")
  log "Alternate domain for distribution ID $cloudfront_distribution_id: $alternate_domain"
  
  if [ -n "$alternate_domain" ]; then
    base_url="https://$alternate_domain"
  else
    base_url="$site_url"
  fi

  # Fetch the page content
  full_page_url="${site_url}${page_url}"
  log "Fetching the page content from $full_page_url"
  page_content=$(curl -v -s -S -L -k --user "$username:$password" "$full_page_url" 2>>"$log_file")

  # Check if the fetch was successful
  if [ -z "$page_content" ]; then
    log "Error fetching page content from $full_page_url"
    failure_count=$((failure_count + 1))
    log "Incremented failure count to $failure_count"
    continue
  fi

  log "Original page content:"
  log "$page_content"

  # Replace all instances of the origin URL with the alternate domain URL in the page content
  if [ -n "$alternate_domain" ]; then
    page_content=$(echo "$page_content" | sed "s|$site_url|$base_url|g")
  fi

  log "Modified page content:"
  log "$page_content"

  # Create the static directory if it doesn't exist
  static_path="$static_base_path/$s3_path"
  mkdir -p "$static_path${page_url}"

  # Save the fetched content to an HTML file
  echo "$page_content" > "$static_path${page_url}/index.html"
  log "Saved the page content to $static_path${page_url}/index.html"

  # Sync the specific directory to S3 with detailed logging and set ACL to public-read
  log "Uploading files to S3 from $static_path${page_url}"
  if aws s3 sync "$static_path${page_url}" "s3://$s3_bucket/$s3_path${page_url}" --acl public-read --delete; then
    log "Files uploaded successfully to S3"
  else
    log "Error uploading files to S3. Check /mnt/data/s3_upload_log.txt for details."
    failure_count=$((failure_count + 1))
    log "Incremented failure count to $failure_count"
    continue
  fi

  # Verify the content in S3
  s3_url="https://$s3_bucket.s3.amazonaws.com/$s3_path${page_url}/index.html"
  s3_url=$(echo "$s3_url" | sed 's|//|/|g')  # Remove double slashes
  log "Verifying content in S3: $s3_url"
  s3_content=$(curl -s -S -L -k "$s3_url" 2>>"$log_file")

  log "Fetched S3 content:"
  log "$s3_content"

  if [ "$s3_content" != "$page_content" ]; then
    log "Content verification failed for $s3_url"
    failure_count=$((failure_count + 1))
    log "Incremented failure count to $failure_count"
    continue
  fi

  # Invalidate CloudFront cache with detailed logging
  log "Invalidating CloudFront cache for distribution ID: $cloudfront_distribution_id"
  invalidation_output=$(aws cloudfront create-invalidation --distribution-id "$cloudfront_distribution_id" --paths "${page_url}" "/*" 2>>"$log_file")
  if [ $? -eq 0 ]; then
    log "CloudFront cache invalidated successfully"
    invalidation_id=$(echo "$invalidation_output" | jq -r '.Invalidation.Id')
    log "Invalidation ID: $invalidation_id"
    
    # Wait for invalidation to complete
    log "Waiting for invalidation to complete..."
    while true; do
      invalidation_status=$(aws cloudfront get-invalidation --distribution-id "$cloudfront_distribution_id" --id "$invalidation_id" --query 'Invalidation.Status' --output text 2>>"$log_file")
      log "Invalidation status: $invalidation_status"
      if [ "$invalidation_status" == "Completed" ]; then
        log "Invalidation completed successfully"
        success_count=$((success_count + 1))
        log "Incremented success count to $success_count"
        break
      fi
      sleep 10
    done
  else
    log "Error invalidating CloudFront cache. Output: $invalidation_output"
    failure_count=$((failure_count + 1))
    log "Incremented failure count to $failure_count"
    continue
  fi

  log "Deployment completed for $full_page_url"
done < <(tail -n +2 "$csv_file")

log "All deployments completed."

# Log the summary of deployments if there are any successful or failed deployments
if [ $success_count -gt 0 ] || [ $failure_count -gt 0 ]; then
  log "Summary: Successful deployments: $success_count, Failed deployments: $failure_count"
fi
