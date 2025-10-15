### 5. Access Your Wiki

Once deployed:

**If connected to VPN:**
```bash
# Access via DNS
https://squad4.wiki

# Or via direct IP (shown in Terraform output)
http://<PRIVATE_IP>
```

**If using temporary IP whitelist:**
```bash
# Use the private IP from Terraform output
http://<PRIVATE_IP>
```

**Default login:**
- Username: `admin`
- Password: (whatever you set in `mediawiki_admin_password`)

### 6. SSH Into the Instance

```bash
# Use the SSH command from Terraform output, or:
ssh -i ~/.ssh/# MediaWiki on AWS - Deployment Guide

This Terraform configuration deploys a private MediaWiki instance with syntax highlighting, Mermaid diagrams, GraphViz support, and automated S3 backups.

## Architecture Overview

- **EC2 Instance**: Ubuntu 22.04 running MediaWiki with Apache and MySQL
- **Application Load Balancer**: Internal ALB with Cognito authentication
- **Route53**: Private hosted zone for `squad4.wiki`
- **S3**: Automated daily backups with lifecycle policies
- **Security**: VPN-only access, IAM role-based permissions

## Prerequisites

### 1. AWS Account and CLI Setup

You need an AWS account with appropriate permissions. Install and configure the AWS CLI:

```bash
# Install AWS CLI (if not already installed)
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows
# Download from: https://awscli.amazonaws.com/AWSCLIV2.msi

# Configure with your credentials
aws configure
# You'll be prompted for:
# - AWS Access Key ID
# - AWS Secret Access Key  
# - Default region (e.g., us-east-1)
# - Output format (json recommended)
```

### 2. Terraform Installation

Install Terraform (version 1.0+):

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Windows
# Download from: https://www.terraform.io/downloads

# Verify installation
terraform --version
```

### 3. VPC with Subnets

You need an existing VPC with:
- **Private subnets** (where the EC2 instance will run)
- **Public subnets** (only if using ALB - optional)

**To find your VPC and subnet IDs:**

```bash
# List your VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table

# List subnets in a specific VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
```

**Don't have a VPC?** You can create one:
- Go to AWS Console → VPC → "Create VPC"
- Choose "VPC and more" for automatic subnet creation
- Or use the AWS VPC wizard

### 4. EC2 Key Pair for SSH Access

**What is an EC2 Key Pair?**
An EC2 key pair is like a password for SSH access to your instance. It consists of:
- A **public key** (stored in AWS)
- A **private key** (downloaded to your computer - keep this safe!)

**NO, you don't create the EC2 instance manually!** Terraform does that for you. You just need to create the key pair first so you can SSH in later.

**To create a key pair:**

**Option A: Using AWS Console**
1. Go to AWS Console → EC2 → Key Pairs (under Network & Security)
2. Click "Create key pair"
3. Name it (e.g., "mediawiki-key")
4. Choose format: ".pem" for Mac/Linux or ".ppk" for Windows
5. Click "Create key pair" - it will download immediately
6. **IMPORTANT**: Save this file securely! You can't download it again
7. Set proper permissions (Mac/Linux only):
   ```bash
   chmod 400 ~/Downloads/mediawiki-key.pem
   ```

**Option B: Using AWS CLI**
```bash
# Create key pair and save to file
aws ec2 create-key-pair --key-name mediawiki-key \
  --query 'KeyMaterial' --output text > mediawiki-key.pem

# Set proper permissions
chmod 400 mediawiki-key.pem

# Move to a safe location
mv mediawiki-key.pem ~/.ssh/
```

**In terraform.tfvars, you'll use just the key pair NAME** (e.g., "mediawiki-key"), NOT the filename!

### 5. VPN Connection to Your VPC

For the wiki to be private and only accessible on the VPN, you need:

**Option A: AWS Client VPN** (managed service)
- Set up once, users install a VPN client
- Good for team access

**Option B: Site-to-Site VPN**
- Connects your office network to AWS
- Good for office-based teams

**Option C: AWS Systems Manager Session Manager**
- No VPN needed, uses AWS SSM for browser-based access
- Good for individuals or small teams

**Don't have VPN yet?** You can still deploy and test:
1. Temporarily add your current public IP to `allowed_ips` in terraform.tfvars
2. Find your IP: `curl ifconfig.me`
3. Set `allowed_ips = ["YOUR.PUBLIC.IP/32"]`
4. **Remove this after setting up VPN for security!**

### 6. Required IAM Permissions

Your AWS user/role needs these permissions:
- EC2: Create/manage instances, security groups, key pairs
- S3: Create/manage buckets
- Route53: Create/manage hosted zones and records
- IAM: Create/manage roles and policies
- VPC: Read VPC and subnet information

**Easiest approach for testing**: Use an IAM user with `PowerUserAccess` policy

### Summary Checklist

Before running Terraform, ensure you have:
- [ ] AWS CLI installed and configured
- [ ] Terraform installed
- [ ] VPC ID identified
- [ ] Subnet IDs identified (private and optionally public)
- [ ] EC2 key pair created (you have the .pem file)
- [ ] VPN set up OR temporary IP whitelist configured
- [ ] Decided whether to use ALB (set `use_alb = true` or `false`)

**Important**: The EC2 instance is created by Terraform - you don't create it manually!

## Authentication Options

This setup now **defaults to simple VPN-based access** without Cognito. Authentication is handled by MediaWiki itself.

### Default Setup (No ALB, No Cognito)
- Users connect via VPN
- Access MediaWiki directly at `https://squad4.wiki`
- Log in with MediaWiki username/password
- Simplest option, recommended for getting started

### Optional: Add Application Load Balancer
Set `use_alb = true` in terraform.tfvars to add an ALB. This provides:
- Better health checking
- Easier to add SSL termination
- Foundation for adding authentication later

### Optional: Add Cognito SSO (Advanced)
If you want SSO via AWS Cognito in the future, you can:
1. Create a Cognito User Pool
2. Integrate with IAM Identity Center (AWS SSO)
3. Update the Terraform to include authentication
4. Let me know if you want help with this!

## File Structure

```
mediawiki-terraform/
├── main.tf                    # Main Terraform configuration
├── mediawiki-setup.sh         # EC2 user data script
├── terraform.tfvars.example   # Example variables file
└── README.md                  # This file
```

## Deployment Steps

### 1. Clone and Configure

```bash
# Create a directory for your configuration
mkdir mediawiki-terraform
cd mediawiki-terraform

# Copy the Terraform files into this directory
# - main.tf
# - mediawiki-setup.sh

# Copy the example tfvars and customize it
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### 2. Update terraform.tfvars

Edit `terraform.tfvars` with your actual values:

```hcl
aws_region         = "us-east-1"
vpc_id             = "vpc-0123456789abcdef0"          # Your VPC ID
private_subnet_ids = ["subnet-abc123", "subnet-def456"]  # Your private subnets
public_subnet_ids  = ["subnet-ghi789", "subnet-jkl012"]  # Only needed if use_alb = true
vpn_cidr_blocks    = ["10.0.0.0/8"]                    # Your VPN CIDR range
key_name           = "mediawiki-key"                   # Your EC2 key pair NAME (not filename!)
mediawiki_admin_password = "SuperSecurePassword123!"
use_alb            = false                              # Set true if you want ALB

# Optional: Temporarily allow your IP if no VPN yet
# allowed_ips = ["203.0.113.42/32"]  # Your public IP
```

**Finding your values:**
```bash
# Get VPC ID
aws ec2 describe-vpcs --output table

# Get subnet IDs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=YOUR_VPC_ID" --output table

# Get your current public IP (if no VPN yet)
curl ifconfig.me
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. SSL Certificate Validation (if using HTTPS)

If using the ALB with HTTPS, the ACM certificate requires DNS validation:

1. Go to AWS Certificate Manager console
2. Find the certificate for `squad4.wiki`
3. Note the CNAME record name and value
4. The Terraform already creates the private hosted zone, but you may need to add the validation record manually

**For direct EC2 access (default)**, MediaWiki will use HTTP. To add HTTPS:
- Either use a self-signed certificate
- Or set up Let's Encrypt on the instance
- Or enable the ALB with a proper certificate

### 5. Access Your Wiki

Once deployed, connect to your VPN and navigate to:
```
https://squad4.wiki
```

You'll be prompted to authenticate via Cognito before accessing the wiki.

## Features

### Syntax Highlighting

Use the `<syntaxhighlight>` tag:

```
<syntaxhighlight lang="python">
def hello_world():
    print("Hello, World!")
</syntaxhighlight>
```

### Mermaid Diagrams

Use the `<mermaid>` tag:

```
<mermaid>
graph TD
    A[Start] --> B[Process]
    B --> C[End]
</mermaid>
```

### GraphViz

Use the `<graphviz>` tag:

```
<graphviz>
digraph G {
    A -> B;
    B -> C;
    C -> A;
}
</graphviz>
```

## Backups

### Automated Backups

Backups run automatically every day at 2 AM UTC and include:
- MySQL database dump
- Uploaded images
- LocalSettings.php configuration

Backups are stored in S3 with:
- 30 days retention in standard storage
- Transition to Glacier after 30 days
- Deletion after 90 days

### Manual Backup

SSH into the instance and run:

```bash
sudo /usr/local/bin/backup-mediawiki.sh
```

### Restore from Backup

```bash
# Download backup from S3
aws s3 cp s3://mediawiki-backups-ACCOUNT_ID/backups/mediawiki-backup-TIMESTAMP.tar.gz .

# Extract
tar -xzf mediawiki-backup-TIMESTAMP.tar.gz
cd mediawiki-backup-TIMESTAMP

# Restore database
mysql mediawiki < database.sql

# Restore images
tar -xzf images.tar.gz -C /var/www/html/mediawiki/images/

# Restore LocalSettings (if needed)
sudo cp LocalSettings.php /var/www/html/mediawiki/
```

## Maintenance

### SSH Access

```bash
ssh -i your-key.pem ubuntu@<PRIVATE_IP>
```

### View Logs

```bash
# Apache logs
sudo tail -f /var/log/apache2/mediawiki-error.log

# Backup logs
sudo tail -f /var/log/mediawiki-backup.log

# CloudWatch Logs (via AWS Console or CLI)
aws logs tail /mediawiki/backups --follow
```

### Update MediaWiki

```bash
# SSH into the instance
ssh -i your-key.pem ubuntu@<PRIVATE_IP>

# Backup first!
sudo /usr/local/bin/backup-mediawiki.sh

# Download new version
cd /tmp
wget https://releases.wikimedia.org/mediawiki/1.41/mediawiki-1.41.X.tar.gz
tar -xzf mediawiki-1.41.X.tar.gz

# Copy LocalSettings.php
sudo cp /var/www/html/mediawiki/LocalSettings.php /tmp/

# Replace installation
sudo rm -rf /var/www/html/mediawiki
sudo mv mediawiki-1.41.X /var/www/html/mediawiki
sudo cp /tmp/LocalSettings.php /var/www/html/mediawiki/

# Run update script
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php

# Fix permissions
sudo chown -R www-data:www-data /var/www/html/mediawiki
```

### Add Users to Cognito

```bash
# Create a user
aws cognito-idp admin-create-user \
  --user-pool-id <USER_POOL_ID> \
  --username john.doe@example.com \
  --user-attributes Name=email,Value=john.doe@example.com \
  --temporary-password TempPassword123!

# Add user to a group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id <USER_POOL_ID> \
  --username john.doe@example.com \
  --group-name wiki-editors
```

## Monitoring

### CloudWatch Alarms

Consider adding these alarms:

```hcl
# Add to main.tf
resource "aws_cloudwatch_metric_alarm" "mediawiki_cpu" {
  alarm_name          = "mediawiki-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  
  dimensions = {
    InstanceId = aws_instance.mediawiki.id
  }
}

resource "aws_cloudwatch_metric_alarm" "mediawiki_unhealthy" {
  alarm_name          = "mediawiki-unhealthy-target"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  
  dimensions = {
    TargetGroup  = aws_lb_target_group.mediawiki.arn_suffix
    LoadBalancer = aws_lb.mediawiki.arn_suffix
  }
}
```

### Backup Verification

Check recent backups:

```bash
aws s3 ls s3://mediawiki-backups-ACCOUNT_ID/backups/ --recursive --human-readable
```

## Troubleshooting

### Cannot Access Wiki

1. **Check VPN connection**: Ensure you're connected to VPN
2. **Check security groups**: Verify VPN CIDR is allowed
3. **Check ALB health**: 
   ```bash
   aws elbv2 describe-target-health --target-group-arn <TG_ARN>
   ```
4. **Check DNS**: 
   ```bash
   nslookup squad4.wiki
   ```

### Cognito Authentication Issues

1. **Verify callback URL**: Must match `https://squad4.wiki/oauth2/idpresponse`
2. **Check user permissions**: User must exist in Cognito User Pool
3. **Review ALB listener rules**: Ensure authentication is configured
4. **Check CloudWatch logs**: Look for authentication errors

### MediaWiki Extension Issues

If an extension isn't working:

```bash
# Check extension is loaded
cd /var/www/html/mediawiki
php maintenance/run.php showJobs

# Update extension
cd extensions/<ExtensionName>
git pull
composer update

# Run MediaWiki update
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php
```

### Backup Failures

Check backup logs:

```bash
sudo tail -100 /var/log/mediawiki-backup.log
```

Common issues:
- **S3 permissions**: Verify IAM role has s3:PutObject
- **Disk space**: Check with `df -h`
- **MySQL access**: Test with `mysql -u mediawiki -p mediawiki`

## Security Considerations

### Hardening

1. **Disable password authentication for SSH**:
   ```bash
   sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

2. **Enable automatic security updates**:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```

3. **Configure fail2ban**:
   ```bash
   sudo apt install fail2ban
   sudo systemctl enable fail2ban
   sudo systemctl start fail2ban
   ```

4. **Restrict MediaWiki file uploads**:
   Edit LocalSettings.php:
   ```php
   $wgFileExtensions = array('png', 'gif', 'jpg', 'jpeg', 'pdf');
   $wgStrictFileExtensions = true;
   $wgCheckFileExtensions = true;
   ```

### Audit Logging

Enable CloudTrail for API auditing and consider:
- VPC Flow Logs for network traffic
- ALB access logs for HTTP requests
- CloudWatch Log Insights for query analysis

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- EC2 t3.medium: ~$30
- ALB: ~$20
- S3 storage (50GB): ~$1
- Data transfer: ~$5-10
- Route53: ~$0.50
- **Total: ~$55-65/month**

### Optimization Tips

1. **Use Reserved Instances**: Save 30-50% for 1-year commitment
2. **Downsize if possible**: t3.small may suffice for small teams
3. **S3 Lifecycle policies**: Already configured for cost savings
4. **Schedule instance**: Stop during off-hours if 24/7 isn't needed

## Advanced Configuration

### High Availability Setup

For production environments, consider:

1. **Multi-AZ RDS**: Replace local MySQL with RDS Multi-AZ
2. **Auto Scaling Group**: Replace single EC2 with ASG
3. **EFS for shared storage**: Share images across instances
4. **ElastiCache**: Add Redis/Memcached for caching

### Monitoring with Grafana

Deploy Grafana to visualize metrics:
- Page load times
- Edit frequency
- Backup success rates
- User activity

### Integration with Slack/Teams

Add webhooks to notify on:
- Page edits
- Backup completion
- System alerts

## Support and Resources

- **MediaWiki Documentation**: https://www.mediawiki.org/wiki/Documentation
- **AWS Documentation**: https://docs.aws.amazon.com
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

## Cleanup

To destroy all resources:

```bash
# Remove all data from S3 first
aws s3 rm s3://mediawiki-backups-ACCOUNT_ID/backups/ --recursive

# Destroy infrastructure
terraform destroy
```

**Warning**: This will permanently delete your wiki and all backups!

## License

This configuration is provided as-is. MediaWiki is licensed under GPL v2+.

