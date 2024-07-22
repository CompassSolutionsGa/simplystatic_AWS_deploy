# simplystatic_AWS_deploy
# AWS Lightsail WordPress Multisite Deployment Scripts

This repository contains deployment scripts for AWS Lightsail WordPress Multisite. The scripts help in generating and deploying static versions of your WordPress sites to an S3 bucket and invalidate the CloudFront cache.

## Files

- `deploy.sh`: Script to deploy a single WordPress site to S3 and invalidate the CloudFront cache.
- `deploy_all.sh`: Script to deploy multiple WordPress sites as defined in a CSV file.

## Prerequisites

- AWS CLI configured with the necessary permissions.
- WP-CLI installed on your WordPress server.
- Simply Static plugin installed and configured on your WordPress sites.

## Instructions

### 1. Place the Scripts

Upload the scripts to your AWS Lightsail instance, preferably in a directory where you keep your scripts, e.g., `/home/bitnami/scripts`.

```bash
scp deploy.sh bitnami@<your-lightsail-ip>:/home/bitnami/scripts/
scp deploy_all.sh bitnami@<your-lightsail-ip>:/home/bitnami/scripts/

2. Update the Scripts
Ensure the scripts have the correct AWS credentials and other configurations as per your setup. Open the scripts and modify the variables:

bash
Copy code
AWS_ACCESS_KEY_ID="your-access-key"
AWS_SECRET_ACCESS_KEY="your-secret-key"
3. Run the Scripts
To deploy a single site:

SSH into your AWS Lightsail instance:

bash
Copy code
ssh bitnami@<your-lightsail-ip>
Navigate to the script directory and make the script executable:

bash
Copy code
cd /home/bitnami/scripts
chmod +x deploy.sh
Run the script:

bash
Copy code
./deploy.sh
To deploy multiple sites:

Prepare a CSV file with the configuration for each site (example format in the deploy_all.sh script).

Upload the CSV file to your instance, e.g., /home/bitnami/scripts/sites_config.csv:

bash
Copy code
scp sites_config.csv bitnami@<your-lightsail-ip>:/home/bitnami/scripts/
SSH into your AWS Lightsail instance:

bash
Copy code
ssh bitnami@<your-lightsail-ip>
Navigate to the script directory and make the script executable:

bash
Copy code
cd /home/bitnami/scripts
chmod +x deploy_all.sh
Run the script:

bash
Copy code
./deploy_all.sh
Running in the Background
To run these scripts in the background using nohup so they continue running after you log out:

bash
Copy code
nohup ./deploy.sh > deploy.log 2>&1 &
nohup ./deploy_all.sh > deploy_all.log 2>&1 &
Check the deploy.log and deploy_all.log files for output and errors.
