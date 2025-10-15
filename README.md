# MediaWiki on AWS - Complete Deployment Guide

This Terraform configuration deploys a private MediaWiki instance with syntax highlighting, Mermaid diagrams, GraphViz support, and automated S3 backups.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Authentication Options](#authentication-options)
4. [Deployment Steps](#deployment-steps)
5. [Post-Deployment Configuration](#post-deployment-configuration)
6. [Using MediaWiki Features](#using-mediawiki-features)
7. [Backups](#backups)
8. [Maintenance](#maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Security Hardening](#security-hardening)
11. [Cost Optimization](#cost-optimization)
12. [Cleanup](#cleanup)

---

## Architecture Overview

**Components:**
- **EC2 Instance**: Ubuntu 22.04 running MediaWiki with Apache and MySQL
- **Route53**: Private hosted zone for `squad4.wiki`
- **S3**: Automated daily backups with lifecycle policies
- **Security Groups**: VPN-only access control
- **Optional ALB**: Application Load Balancer with HTTPS termination
- **IAM Roles**: For S3 backup access

**Network Flow:**
```
VPN Users → Route53 (squad4.wiki) → EC2 Instance (or ALB → EC2)
EC2 Instance → S3 (backups)
```

---

## Prerequisites

### 1. AWS Account and CLI Setup

You need an AWS account with appropriate permissions.

**Install AWS CLI:**

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows - Download from:
# https://awscli.amazonaws.com/AWSCLIV2.msi
```

**Configure AWS CLI:**

```bash
aws configure
```

You'll be prompted for:
- **AWS Access Key ID**: From IAM user credentials
- **AWS Secret Access Key**: From IAM user credentials
- **Default region**: e.g., `us-east-1`
- **Output format**: `json` (recommended)

**Verify it works:**
```bash
aws sts get-caller-identity
```

### 2. Terraform Installation

Install Terraform version 1.0 or higher:

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Windows - Download from:
# https://www.terraform.io/downloads

# Verify installation
terraform --version
```

### 3. VPC with Subnets

You need an existing VPC with at least private subnets.

**Find your VPC and subnet IDs:**

```bash
# List all VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table

# Example output:
# |  vpc-0abc123def456  |  my-vpc  |  10.0.0.0/16  |

# List subnets in your VPC (replace with your VPC ID)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0abc123def456" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# Example output:
# |  subnet-111  |  us-east-1a  |  10.0.1.0/24  |  private-subnet-1a  |
# |  subnet-222  |  us-east-1b  |  10.0.2.0/24  |  private-subnet-1b  |
```

**Don't have a VPC?**

Create one via AWS Console:
1. Go to **VPC Dashboard** → **Create VPC**
2. Choose **VPC and more** (creates subnets automatically)
3. Name: `mediawiki-vpc`
4. IPv4 CIDR: `10.0.0.0/16`
5. Number of AZs: `2`
6. Public subnets: `2` (optional, only if using ALB)
7. Private subnets: `2`
8. Click **Create VPC**

### 4. EC2 Key Pair for SSH Access

**What is an EC2 Key Pair?**
A key pair allows SSH access to your EC2 instance. It consists of:
- **Public key**: Stored in AWS
- **Private key**: Downloaded to your computer (keep safe!)

**Important:** You do NOT manually create the EC2 instance - Terraform does that! You only need to create the key pair first.

**Create a key pair:**

**Option A - AWS Console:**
1. Go to **EC2 Console** → **Key Pairs** (under Network & Security)
2. Click **Create key pair**
3. Name: `mediawiki-key`
4. Key pair type: `RSA`
5. Private key format: `.pem` (Mac/Linux) or `.ppk` (Windows/PuTTY)
6. Click **Create key pair** - downloads immediately
7. **Save this file!** You cannot download it again

**Set permissions (Mac/Linux):**
```bash
chmod 400 ~/Downloads/mediawiki-key.pem
mv ~/Downloads/mediawiki-key.pem ~/.ssh/
```

**Option B - AWS CLI:**
```bash
# Create and save key pair
aws ec2 create-key-pair --key-name mediawiki-key \
  --query 'KeyMaterial' --output text > ~/.ssh/mediawiki-key.pem

# Set permissions
chmod 400 ~/.ssh/mediawiki-key.pem

# Verify it was created
aws ec2 describe-key-pairs --key-names mediawiki-key
```

**In terraform.tfvars, use only the NAME:** `key_name = "mediawiki-key"` (not the filename!)

### 5. VPN Connection to Your VPC

For private wiki access, you need VPN connectivity to your VPC.

**Options:**

**A. AWS Client VPN** (Recommended for teams)
- Managed VPN service
- Users install OpenVPN client
- Good for 5+ users

**B. AWS Site-to-Site VPN**
- Connects office network to AWS
- Good for office-based teams

**C. AWS Systems Manager Session Manager**
- No VPN needed
- Browser-based access
- Good for admins/testing

**Testing without VPN:**

If you don't have VPN set up yet, you can temporarily whitelist your IP:

```bash
# Get your current public IP
curl ifconfig.me
# Example output: 203.0.113.42

# Add to terraform.tfvars:
allowed_ips = ["203.0.113.42/32"]
```

⚠️ **Remove this after setting up VPN for security!**

### 6. Required IAM Permissions

Your AWS IAM user/role needs these permissions:
- **EC2**: Full (instances, security groups, key pairs)
- **S3**: Full (bucket creation and management)
- **Route53**: Full (hosted zones and records)
- **IAM**: Create/manage roles and policies
- **VPC**: Read (describe VPCs and subnets)
- **ACM**: Certificate management (if using ALB)

**Quick option for testing:** Attach `PowerUserAccess` policy to your IAM user.

### Pre-Deployment Checklist

Before proceeding, verify you have:

- [ ] AWS CLI installed and configured (`aws sts get-caller-identity` works)
- [ ] Terraform installed (`terraform --version` shows 1.0+)
- [ ] VPC ID identified (format: `vpc-xxxxxxxxx`)
- [ ] At least 2 private subnet IDs identified
- [ ] EC2 key pair created (you have the `.pem` file saved)
- [ ] VPN configured OR temporary IP whitelist ready
- [ ] Decided: use ALB? (`use_alb = true` or `false`)

---

## Authentication Options

### Default Setup (Recommended for Getting Started)

**No ALB, No Cognito** - Simple VPN-based access:
- Users connect via VPN
- Access MediaWiki at `http://squad4.wiki` or `http://<PRIVATE_IP>`
- Log in with MediaWiki username/password
- Simplest configuration

Set in `terraform.tfvars`:
```hcl
use_alb = false
```

### Optional: Application Load Balancer

Add an ALB for:
- HTTPS termination with SSL certificate
- Better health checking
- Foundation for future SSO integration

Set in `terraform.tfvars`:
```hcl
use_alb = true
```

**Note:** Requires public subnets and ACM certificate validation.

### Optional: AWS Cognito SSO (Advanced)

For enterprise SSO with AWS IAM Identity Center:
1. Create Cognito User Pool
2. Integrate with IAM Identity Center
3. Modify Terraform configuration
4. *Contact me if you need this setup*

---

## Deployment Steps

### Step 1: Prepare Configuration Files

Create a project directory:

```bash
mkdir mediawiki-terraform
cd mediawiki-terraform
```

Create three files in this directory:
1. **main.tf** - Main Terraform configuration (from artifact)
2. **mediawiki-setup.sh** - EC2 bootstrap script (from artifact)
3. **terraform.tfvars** - Your configuration values

### Step 2: Create terraform.tfvars

Create `terraform.tfvars` with your actual values:

```hcl
# AWS Configuration
aws_region = "us-east-1"

# Network Configuration
vpc_id             = "vpc-0abc123def456"                    # ← YOUR VPC ID
private_subnet_ids = ["subnet-111aaa", "subnet-222bbb"]    # ← YOUR PRIVATE SUBNETS
public_subnet_ids  = ["subnet-333ccc", "subnet-444ddd"]    # ← Only if use_alb = true

# VPN CIDR blocks that can access the wiki
vpn_cidr_blocks = ["10.0.0.0/8"]                            # ← YOUR VPN RANGE

# Optional: Temporarily allow your IP if no VPN yet
# allowed_ips = ["203.0.113.42/32"]                         # ← YOUR PUBLIC IP

# EC2 Configuration  
key_name = "mediawiki-key"                                  # ← YOUR KEY PAIR NAME

# MediaWiki Configuration
mediawiki_admin_password = "ChangeMeToSomethingSecure123!" # ← CHANGE THIS!

# ALB Configuration
use_alb = false                                             # ← true for ALB, false for direct access
```

**Finding your values:**

```bash
# VPC ID
aws ec2 describe-vpcs --output table

# Subnet IDs (replace vpc-xxx with your VPC ID)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
  --output table
# MapPublicIpOnLaunch: true = public subnet, false = private subnet

# Your public IP (if no VPN)
curl ifconfig.me

# Your key pairs
aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table
```

### Step 3: Initialize Terraform

```bash
# Initialize Terraform (downloads AWS provider)
terraform init

# You should see: "Terraform has been successfully initialized!"
```

### Step 4: Review the Plan

```bash
# See what Terraform will create
terraform plan

# Review the output carefully
# You should see it will create:
# - aws_instance.mediawiki
# - aws_s3_bucket.mediawiki_backups
# - aws_route53_zone.private
# - aws_security_group.mediawiki
# - And more...
```

### Step 5: Deploy!

```bash
# Apply the configuration
terraform apply

# Review the plan again
# Type 'yes' when prompted

# Deployment takes 15-20 minutes
# - Terraform creates resources: ~2 minutes
# - EC2 user_data script runs: ~15 minutes (installing packages, MediaWiki, extensions)
```

**What's happening:**
1. Terraform creates S3 bucket, security groups, Route53 zone
2. Terraform launches EC2 instance
3. EC2 runs `mediawiki-setup.sh` script which:
   - Installs Apache, MySQL, PHP
   - Downloads and configures MediaWiki
   - Installs syntax highlighting (Pygments)
   - Installs Mermaid CLI
   - Installs GraphViz
   - Sets up backup scripts and cron jobs
   - Configures CloudWatch logging

### Step 6: Save Terraform Outputs

```bash
# After apply completes, note the outputs:
terraform output

# Example output:
# mediawiki_url = "https://squad4.wiki"
# mediawiki_private_ip = "10.0.1.123"
# ec2_instance_id = "i-0abc123def456"
# s3_backup_bucket = "mediawiki-backups-123456789012"
# ssh_command = "ssh -i your-key.pem ubuntu@10.0.1.123"
```

---

## Post-Deployment Configuration

### 1. Wait for Installation to Complete

The user_data script takes ~15 minutes. Monitor progress:

```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Check if instance is running
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name'

# SSH into instance (replace with your actual IP and key)
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@10.0.1.123

# Once connected, watch the installation
sudo tail -f /var/log/cloud-init-output.log

# Look for: "MediaWiki installation complete!"
# Press Ctrl+C to exit
```

### 2. Verify DNS Resolution

```bash
# From a machine connected to VPN:
nslookup squad4.wiki

# Should return the private IP of your EC2 instance
# If using ALB, it returns the ALB DNS name
```

### 3. Access MediaWiki

**If connected to VPN:**
```
http://squad4.wiki
```

**If using temporary IP whitelist:**
```
http://<PRIVATE_IP>    # From Terraform output
```

### 4. First Login

**Default credentials:**
- Username: `admin`
- Password: `<what you set in mediawiki_admin_password>`

**First steps:**
1. Log in as admin
2. Go to **Special:Version** to verify extensions are loaded
3. Create your first page: **Main Page** → Edit
4. Configure additional settings in **Special:Preferences**

### 5. Create Additional Users

**Method 1 - Web UI:**
1. Go to **Special:CreateAccount**
2. Fill in username, password, email
3. Click Create Account

**Method 2 - Command Line:**
```bash
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

cd /var/www/html/mediawiki

# Create user
sudo -u www-data php maintenance/createAndPromote.php \
  --bureaucrat \
  --sysop \
  john.doe \
  password123

# john.doe is now an admin
```

---

## Using MediaWiki Features

### Syntax Highlighting

MediaWiki includes SyntaxHighlight extension with support for 200+ languages.

**Usage:**
```
<syntaxhighlight lang="python">
def hello_world():
    print("Hello, World!")
    return True
</syntaxhighlight>
```

**Supported languages:** python, java, javascript, bash, sql, json, xml, yaml, and many more.

**With line numbers:**
```
<syntaxhighlight lang="python" line>
def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n-1)
</syntaxhighlight>
```

### Mermaid Diagrams

Create flowcharts, sequence diagrams, and more.

**Flowchart:**
```
<mermaid>
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Great!]
    B -->|No| D[Debug]
    D --> B
    C --> E[End]
</mermaid>
```

**Sequence Diagram:**
```
<mermaid>
sequenceDiagram
    Alice->>Bob: Hello Bob!
    Bob->>Alice: Hello Alice!
    Alice->>Bob: How are you?
    Bob->>Alice: I'm good, thanks!
</mermaid>
```

**Gantt Chart:**
```
<mermaid>
gantt
    title Project Schedule
    dateFormat  YYYY-MM-DD
    section Phase 1
    Design           :a1, 2024-01-01, 30d
    Development      :a2, after a1, 60d
    section Phase 2
    Testing          :a3, after a2, 20d
    Deployment       :a4, after a3, 10d
</mermaid>
```

### GraphViz Diagrams

Create directed graphs, network diagrams, and organizational charts.

**Simple Graph:**
```
<graphviz>
digraph G {
    A -> B;
    B -> C;
    C -> A;
    B -> D;
}
</graphviz>
```

**Network Architecture:**
```
<graphviz>
digraph network {
    rankdir=LR;
    node [shape=box];
    
    Internet [shape=cloud];
    LoadBalancer [label="Load Balancer"];
    WebServer1 [label="Web Server 1"];
    WebServer2 [label="Web Server 2"];
    Database [label="Database", shape=cylinder];
    
    Internet -> LoadBalancer;
    LoadBalancer -> WebServer1;
    LoadBalancer -> WebServer2;
    WebServer1 -> Database;
    WebServer2 -> Database;
}
</graphviz>
```

### Uploading Files/Images

Enable file uploads (already configured):

1. Go to any page and click **Edit**
2. Click **Insert** → **Media**
3. Upload your image/file
4. Insert into page

**Allowed file types:** png, gif, jpg, jpeg, pdf (configured in LocalSettings.php)

---

## Backups

### Automated Backups

Backups run automatically **every day at 2:00 AM UTC**.

**What's backed up:**
- MySQL database dump
- Uploaded images and files
- LocalSettings.php configuration

**Backup location:** S3 bucket `mediawiki-backups-<ACCOUNT_ID>/backups/`

**Retention policy:**
- Standard storage: 30 days
- Glacier storage: 30-90 days
- Deleted after: 90 days

### Viewing Backups

```bash
# List all backups
aws s3 ls s3://mediawiki-backups-<ACCOUNT_ID>/backups/ --recursive --human-readable

# Example output:
# 2024-10-15  123.4 MiB  backups/mediawiki-backup-20241015_020001.tar.gz
# 2024-10-14  120.1 MiB  backups/mediawiki-backup-20241014_020001.tar.gz
```

### Manual Backup

```bash
# SSH into the instance
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

# Run backup manually
sudo /usr/local/bin/backup-mediawiki.sh

# Check backup log
sudo tail -50 /var/log/mediawiki-backup.log
```

### Restore from Backup

```bash
# 1. Download backup from S3
aws s3 cp s3://mediawiki-backups-ACCOUNT_ID/backups/mediawiki-backup-20241015_020001.tar.gz .

# 2. SSH into instance
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

# 3. Upload and extract backup
scp -i ~/.ssh/mediawiki-key.pem mediawiki-backup-20241015_020001.tar.gz ubuntu@<PRIVATE_IP>:~
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

tar -xzf mediawiki-backup-20241015_020001.tar.gz
cd mediawiki-backup-20241015_020001

# 4. Restore database
mysql mediawiki < database.sql

# 5. Restore images
sudo tar -xzf images.tar.gz -C /var/www/html/mediawiki/images/

# 6. Restore configuration (optional)
sudo cp LocalSettings.php /var/www/html/mediawiki/

# 7. Fix permissions
sudo chown -R www-data:www-data /var/www/html/mediawiki

# 8. Restart Apache
sudo systemctl restart apache2
```

### Backup Monitoring

Check CloudWatch Logs:

```bash
# View backup logs
aws logs tail /mediawiki/backups --follow --region us-east-1

# Or via AWS Console:
# CloudWatch → Log groups → /mediawiki/backups
```

---

## Maintenance

### SSH Access

```bash
# Use the key you created earlier
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>
```

### View Logs

```bash
# Apache error log
sudo tail -f /var/log/apache2/mediawiki-error.log

# Apache access log
sudo tail -f /var/log/apache2/mediawiki-access.log

# Backup log
sudo tail -f /var/log/mediawiki-backup.log

# System log
sudo journalctl -f
```

### Update MediaWiki

```bash
# SSH into instance
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

# 1. Backup first!
sudo /usr/local/bin/backup-mediawiki.sh

# 2. Download new version
cd /tmp
wget https://releases.wikimedia.org/mediawiki/1.41/mediawiki-1.41.1.tar.gz
tar -xzf mediawiki-1.41.1.tar.gz

# 3. Backup current LocalSettings.php
sudo cp /var/www/html/mediawiki/LocalSettings.php /tmp/

# 4. Replace installation
sudo rm -rf /var/www/html/mediawiki
sudo mv mediawiki-1.41.1 /var/www/html/mediawiki
sudo cp /tmp/LocalSettings.php /var/www/html/mediawiki/

# 5. Run update script
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php

# 6. Fix permissions
sudo chown -R www-data:www-data /var/www/html/mediawiki

# 7. Test the wiki
```

### Update Extensions

```bash
cd /var/www/html/mediawiki/extensions/<ExtensionName>
sudo git pull
sudo composer update --no-dev

# Run MediaWiki update
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php
```

### Restart Services

```bash
# Restart Apache
sudo systemctl restart apache2

# Restart MySQL
sudo systemctl restart mysql

# Check service status
sudo systemctl status apache2
sudo systemctl status mysql
```

---

## Troubleshooting

### Cannot Access Wiki

**Problem:** Cannot load `squad4.wiki` or `http://<PRIVATE_IP>`

**Checks:**

1. **Verify VPN connection:**
   ```bash
   # Check if you can reach private IPs
   ping <PRIVATE_IP>
   ```

2. **Check DNS resolution:**
   ```bash
   nslookup squad4.wiki
   # Should return the private IP
   ```

3. **Verify instance is running:**
   ```bash
   aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
     --query 'Reservations[0].Instances[0].State.Name'
   # Should return: "running"
   ```

4. **Check security group rules:**
   ```bash
   aws ec2 describe-security-groups --group-ids <SG_ID>
   # Verify your VPN CIDR or IP is allowed on port 80/443
   ```

5. **SSH and check Apache:**
   ```bash
   ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>
   sudo systemctl status apache2
   # Should be "active (running)"
   ```

### MediaWiki Shows Errors

**Problem:** 500 errors, blank pages, or PHP errors

**Check Apache error log:**
```bash
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>
sudo tail -100 /var/log/apache2/mediawiki-error.log
```

**Common issues:**

1. **Database connection failed:**
   ```bash
   # Check MySQL is running
   sudo systemctl status mysql
   
   # Test database connection
   mysql -u mediawiki -p mediawiki
   # Enter password when prompted
   ```

2. **Permissions issues:**
   ```bash
   # Fix MediaWiki permissions
   sudo chown -R www-data:www-data /var/www/html/mediawiki
   sudo chmod -R 755 /var/www/html/mediawiki
   ```

3. **PHP errors:**
   ```bash
   # Check PHP version
   php --version
   
   # Test PHP syntax
   php -l /var/www/html/mediawiki/index.php
   ```

### Extensions Not Working

**Problem:** Mermaid diagrams, syntax highlighting, or GraphViz not rendering

**Check extensions are loaded:**
```bash
# Via web: Go to Special:Version
# Lists all installed extensions

# Via CLI:
cd /var/www/html/mediawiki
php maintenance/showJobs.php
```

**Reinstall extension:**
```bash
cd /var/www/html/mediawiki/extensions/<ExtensionName>
sudo git pull
sudo composer install --no-dev

# Update MediaWiki database
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php
```

**Check required binaries:**
```bash
# Pygments for syntax highlighting
which pygmentize
# Should return: /usr/local/bin/pygmentize

# Mermaid CLI
which mmdc
# Should return: /usr/bin/mmdc

# GraphViz
which dot
# Should return: /usr/bin/dot
```

### Backup Failures

**Problem:** Backups not running or failing

**Check backup log:**
```bash
sudo tail -100 /var/log/mediawiki-backup.log
```

**Common issues:**

1. **S3 permissions:**
   ```bash
   # Test S3 access
   aws s3 ls s3://mediawiki-backups-<ACCOUNT_ID>/ --region us-east-1
   
   # Check IAM role
   aws sts get-caller-identity
   ```

2. **Disk space:**
   ```bash
   df -h
   # Ensure / has > 5GB free
   ```

3. **MySQL access:**
   ```bash
   # Test mysqldump
   mysqldump mediawiki > /tmp/test.sql
   # Should complete without errors
   ```

**Run backup manually with debug:**
```bash
sudo bash -x /usr/local/bin/backup-mediawiki.sh
```

### SSH Connection Refused

**Problem:** Cannot SSH into instance

**Checks:**

1. **Security group allows SSH:**
   ```bash
   aws ec2 describe-security-groups --group-ids <SG_ID> \
     --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
   ```

2. **Using correct key:**
   ```bash
   # Verify key permissions
   ls -l ~/.ssh/mediawiki-key.pem
   # Should show: -r-------- (400)
   
   # Verify key name matches
   aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
     --query 'Reservations[0].Instances[0].KeyName'
   ```

3. **Instance has public IP (if no VPN):**
   ```bash
   # Check if instance is in private subnet
   aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
     --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp'
   ```

---

## Security Hardening

### 1. Disable Password Authentication for SSH

```bash
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 2. Enable Automatic Security Updates

```bash
sudo apt update
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
# Select "Yes"
```

### 3. Configure Fail2Ban

```bash
sudo apt install fail2ban -y

# Create custom config
sudo tee /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/mediawiki-error.log
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status
```

### 4. Restrict File Uploads

Edit MediaWiki configuration:

```bash
sudo nano /var/www/html/mediawiki/LocalSettings.php

# Add or modify:
$wgFileExtensions = array('png', 'gif', 'jpg', 'jpeg', 'pdf', 'svg');
$wgStrictFileExtensions = true;
$wgCheckFileExtensions = true;
$wgVerifyMimeType = true;
$wgUploadSizeWarning = 10485760; # 10MB

# Save and exit (Ctrl+X, Y, Enter)
```

### 5. Enable HTTPS with Let's Encrypt (if not using ALB)

```bash
# Install Certbot
sudo apt install certbot python3-certbot-apache -y

# This requires a public domain name pointing to your instance
# For internal-only wiki, use self-signed certificate instead:

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt

# Update Apache config
sudo nano /etc/apache2/sites-available/mediawiki.conf

# Add SSL configuration (not showing full config here)
sudo a2enmod ssl
sudo systemctl restart apache2
```

### 6. Configure Audit Logging

Enable CloudTrail for API calls and VPC Flow Logs for network traffic analysis.

---

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Resource | Cost |
|----------|------|
| EC2 t3.medium (730 hrs) | ~$30 |
| EBS gp3 30GB | ~$2.50 |
| S3 storage (50GB) | ~$1.15 |
| S3 requests | ~$0.10 |
| Route53 Hosted Zone | ~$0.50 |
| Data transfer (5GB) | ~$0.45 |
| ALB (if enabled) | ~$20 |
| CloudWatch Logs | ~$0.50 |
| **Total (no ALB)** | **~$37/month** |
| **Total (with ALB)** | **~$57/month** |

### Ways to Reduce Costs

**1. Use Reserved Instances (30-50% savings)**

```bash
# 1-year commitment, pay upfront
aws ec2 purchase-reserved-instances-offering \
  --instance-count 1 \
  --reserved-instances-offering-id <offering-id>

# Savings: ~$10-15/month
```

**2. Downsize Instance (if low usage)**

If your team is small (<10 users), try `t3.small`:

```hcl
# In main.tf, change:
instance_type = "t3.small"  # Was t3.medium

# Savings: ~$15/month
# Re-apply: terraform apply
```

**3. Stop Instance During Off-Hours**

If wiki isn't needed 24/7:

```bash
# Create stop/start schedule with Lambda or Systems Manager

# Stop at 6 PM weekdays
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Start at 8 AM weekdays  
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Savings: ~$10-15/month (if stopped 12hrs/day)
```

**4. Optimize S3 Storage**

Already configured, but verify:
- Lifecycle transitions to Glacier after 30 days
- Deletion after 90 days
- Enable S3 Intelligent-Tiering for uploaded files

**5. Skip the ALB**

If you don't need HTTPS/SSL termination:
```hcl
use_alb = false  # Saves ~$20/month
```

**6. Use Spot Instances (Advanced)**

Not recommended for wiki but possible:
- 70% cost savings
- Risk of interruption
- Better for dev/test environments

### Cost Monitoring

**Set up billing alerts:**

```bash
# Create SNS topic for alerts
aws sns create-topic --name billing-alerts

# Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:billing-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com

# Create CloudWatch alarm for $50 threshold
aws cloudwatch put-metric-alarm \
  --alarm-name mediawiki-cost-alert \
  --alarm-description "Alert when estimated charges exceed $50" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT_ID:billing-alerts
```

**Track costs:**

```bash
# View current month costs
aws ce get-cost-and-usage \
  --time-period Start=2024-10-01,End=2024-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Or use AWS Cost Explorer in console
```

---

## Advanced Configuration

### High Availability Setup

For production environments requiring 99.9%+ uptime:

**1. Multi-AZ Database with RDS**

Replace local MySQL with Amazon RDS Multi-AZ:

```hcl
# Add to main.tf
resource "aws_db_instance" "mediawiki" {
  identifier           = "mediawiki-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.small"
  allocated_storage    = 20
  storage_type         = "gp3"
  
  db_name  = "mediawiki"
  username = "mediawiki"
  password = var.db_password
  
  multi_az               = true
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.mediawiki.name
  
  backup_retention_period = 7
  skip_final_snapshot     = false
  final_snapshot_identifier = "mediawiki-final-snapshot"
}
```

**2. Auto Scaling Group**

Replace single EC2 with ASG for automatic failover:

```hcl
resource "aws_launch_template" "mediawiki" {
  name_prefix   = "mediawiki-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  
  user_data = base64encode(templatefile("${path.module}/mediawiki-setup.sh", {
    admin_password = var.mediawiki_admin_password
    s3_bucket      = aws_s3_bucket.mediawiki_backups.id
    aws_region     = var.aws_region
  }))
}

resource "aws_autoscaling_group" "mediawiki" {
  name                = "mediawiki-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.mediawiki[0].arn]
  health_check_type   = "ELB"
  
  min_size         = 2
  max_size         = 4
  desired_capacity = 2
  
  launch_template {
    id      = aws_launch_template.mediawiki.id
    version = "$Latest"
  }
}
```

**3. Shared Storage with EFS**

For shared images across instances:

```hcl
resource "aws_efs_file_system" "mediawiki" {
  creation_token = "mediawiki-images"
  encrypted      = true
}

resource "aws_efs_mount_target" "mediawiki" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.mediawiki.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
```

**4. ElastiCache for Caching**

Add Redis for performance:

```hcl
resource "aws_elasticache_cluster" "mediawiki" {
  cluster_id           = "mediawiki-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis.id]
  subnet_group_name    = aws_elasticache_subnet_group.mediawiki.name
}
```

### Monitoring with Grafana

Set up Grafana dashboard for visualizations:

```bash
# Install Grafana on separate instance or use managed Grafana
# Configure CloudWatch data source
# Create dashboard with metrics:
# - CPU utilization
# - Memory usage
# - Page load times
# - Edit frequency
# - User sessions
# - Backup success rate
```

### Integration with Slack/Teams

Add webhooks for notifications:

```bash
# Edit /usr/local/bin/backup-mediawiki.sh

# Add at the end:
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

if [ $? -eq 0 ]; then
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"✅ MediaWiki backup completed successfully"}' \
    $SLACK_WEBHOOK
else
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"❌ MediaWiki backup FAILED - check logs"}' \
    $SLACK_WEBHOOK
fi
```

### Custom Domain with Route53

Use a real domain instead of squad4.wiki:

```hcl
# If you own example.com and want wiki.example.com

resource "aws_route53_zone" "public" {
  name = "example.com"
}

resource "aws_route53_record" "wiki" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "wiki.example.com"
  type    = "A"
  
  alias {
    name                   = aws_lb.mediawiki[0].dns_name
    zone_id                = aws_lb.mediawiki[0].zone_id
    evaluate_target_health = true
  }
}

# Update ACM certificate domain
resource "aws_acm_certificate" "mediawiki" {
  domain_name       = "wiki.example.com"
  validation_method = "DNS"
}
```

---

## Cleanup

### Backup Before Destroying

**CRITICAL: Backup your data before destroying infrastructure!**

```bash
# 1. Run final backup
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>
sudo /usr/local/bin/backup-mediawiki.sh
exit

# 2. Download all backups locally
aws s3 sync s3://mediawiki-backups-ACCOUNT_ID/backups/ ./mediawiki-backups/

# 3. Verify downloads
ls -lh ./mediawiki-backups/
```

### Destroy Infrastructure

```bash
# Navigate to your Terraform directory
cd mediawiki-terraform

# Preview what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Review the plan carefully
# Type 'yes' when prompted

# This will delete:
# - EC2 instance
# - Security groups
# - Route53 hosted zone
# - S3 bucket (if empty)
# - IAM roles and policies
```

**Note:** If S3 bucket has objects, you must empty it first:

```bash
# Empty S3 bucket before destroy
aws s3 rm s3://mediawiki-backups-ACCOUNT_ID/ --recursive

# Then run terraform destroy again
terraform destroy
```

### Manual Cleanup (if needed)

If Terraform destroy fails, manually delete:

```bash
# Delete EC2 instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# Delete security groups (after instance terminates)
aws ec2 delete-security-group --group-id <SG_ID>

# Delete S3 bucket
aws s3 rb s3://mediawiki-backups-ACCOUNT_ID --force

# Delete Route53 hosted zone
aws route53 delete-hosted-zone --id <HOSTED_ZONE_ID>

# Delete IAM role
aws iam delete-role --role-name mediawiki-ec2-role

# Delete key pair (if you want)
aws ec2 delete-key-pair --key-name mediawiki-key
```

---

## Frequently Asked Questions

### Q: Can I use this for a public wiki?

**A:** Yes, but you'll need to:
1. Change security groups to allow public access (carefully!)
2. Enable public subnets and internet gateway
3. Use ALB with WAF for DDoS protection
4. Implement rate limiting
5. Consider Cognito or other auth for user management

### Q: How do I migrate from an existing MediaWiki?

**A:** 
1. Deploy this stack
2. Export old wiki: `mysqldump old_db > old_wiki.sql`
3. Copy images: `tar -czf images.tar.gz /path/to/old/images`
4. Import to new wiki:
   ```bash
   mysql mediawiki < old_wiki.sql
   tar -xzf images.tar.gz -C /var/www/html/mediawiki/images/
   ```
5. Update LocalSettings.php if needed
6. Run `php maintenance/update.php`

### Q: Can I use a different database (PostgreSQL)?

**A:** Yes, MediaWiki supports PostgreSQL. Modify the setup script:
- Install `postgresql` instead of `mysql-server`
- Install `php-pgsql` instead of `php-mysql`
- Update database connection in installation command

### Q: How do I add custom extensions?

**A:**
```bash
cd /var/www/html/mediawiki/extensions
git clone <EXTENSION_REPO_URL>
cd <ExtensionName>
composer install --no-dev

# Add to LocalSettings.php:
wfLoadExtension( 'ExtensionName' );

# Run update
php maintenance/update.php
```

### Q: Can I use this with AWS Organizations/Multiple accounts?

**A:** Yes! Options:
1. Deploy in each account separately
2. Use cross-account S3 backups
3. Use AWS Resource Access Manager for shared resources
4. Centralize backups in a separate backup account

### Q: How do I enable debugging?

**A:**
```bash
# Edit LocalSettings.php
sudo nano /var/www/html/mediawiki/LocalSettings.php

# Add at the end:
$wgDebugLogFile = "/tmp/mediawiki-debug.log";
$wgShowExceptionDetails = true;
$wgShowDBErrorBacktrace = true;
$wgShowSQLErrors = true;

# Save and check logs
tail -f /tmp/mediawiki-debug.log
```

### Q: Can I schedule maintenance windows?

**A:** Yes, use AWS Systems Manager Maintenance Windows:
```bash
# Create maintenance window (Sundays 2-4 AM)
aws ssm create-maintenance-window \
  --name "MediaWiki-Maintenance" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 2 \
  --cutoff 0 \
  --allow-unassociated-targets
```

---

## Additional Resources

### Documentation

- **MediaWiki**: https://www.mediawiki.org/wiki/Documentation
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **AWS EC2**: https://docs.aws.amazon.com/ec2/
- **SyntaxHighlight Extension**: https://www.mediawiki.org/wiki/Extension:SyntaxHighlight
- **Mermaid**: https://mermaid.js.org/
- **GraphViz**: https://graphviz.org/documentation/

### Community Support

- **MediaWiki Support**: https://www.mediawiki.org/wiki/Project:Support_desk
- **Terraform Community**: https://discuss.hashicorp.com/
- **AWS Forums**: https://forums.aws.amazon.com/

### Extensions Library

Browse MediaWiki extensions:
- **Extension Matrix**: https://www.mediawiki.org/wiki/Extension_Matrix
- **Popular Extensions**: https://www.mediawiki.org/wiki/Category:Extensions

### Security Resources

- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **MediaWiki Security**: https://www.mediawiki.org/wiki/Manual:Security
- **AWS Security Best Practices**: https://aws.amazon.com/architecture/security-identity-compliance/

---

## Quick Reference Commands

### Common Operations

```bash
# SSH into instance
ssh -i ~/.ssh/mediawiki-key.pem ubuntu@<PRIVATE_IP>

# Restart Apache
sudo systemctl restart apache2

# Restart MySQL
sudo systemctl restart mysql

# Run backup manually
sudo /usr/local/bin/backup-mediawiki.sh

# View logs
sudo tail -f /var/log/apache2/mediawiki-error.log

# Update MediaWiki
cd /var/www/html/mediawiki
sudo -u www-data php maintenance/update.php

# Create user
sudo -u www-data php maintenance/createAndPromote.php username password

# Clear cache
sudo -u www-data php maintenance/rebuildall.php

# Check extension status
php maintenance/showJobs.php
```

### Terraform Commands

```bash
# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show outputs
terraform output

# Show state
terraform show

# Destroy everything
terraform destroy

# Format code
terraform fmt

# Validate configuration
terraform validate
```

### AWS CLI Commands

```bash
# Check instance status
aws ec2 describe-instances --instance-ids <ID> \
  --query 'Reservations[0].Instances[0].State.Name'

# List S3 backups
aws s3 ls s3://mediawiki-backups-ACCOUNT_ID/backups/

# View CloudWatch logs
aws logs tail /mediawiki/backups --follow

# Stop instance
aws ec2 stop-instances --instance-ids <ID>

# Start instance
aws ec2 start-instances --instance-ids <ID>

# Reboot instance
aws ec2 reboot-instances --instance-ids <ID>
```

---

## Support

If you encounter issues:

1. **Check this guide's Troubleshooting section**
2. **Review logs** (Apache, MySQL, system)
3. **Search MediaWiki forums** for extension-specific issues
4. **Check AWS Service Health Dashboard** for outages
5. **Review Terraform state** for configuration issues

---

## License

This deployment guide and Terraform configuration are provided as-is under the MIT License.

MediaWiki is licensed under GPL v2+.

---

**Last Updated:** October 2024  
**Terraform Version:** 1.5+  
**MediaWiki Version:** 1.41.0  
**Tested On:** Ubuntu 22.04 LTS

---

## Changelog

**v1.0 - Initial Release**
- Complete Terraform configuration
- MediaWiki 1.41 with extensions
- Automated S3 backups
- VPN-based access
- Optional ALB support
- Comprehensive documentation

