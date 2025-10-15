##!/usr/bin/env bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
		apache2 \
		mysql-server \
		php \
		php-mysql \
		php-xml \
		php-mbstring \
		php-intl \
		php-apcu \
		php-curl \
		php-gd \
		libapache2-mod-php \
		wget \
		unzip \
		git \
		python3-pip \
		graphviz \
		imagemagick \
		awscli

# Install Pygments for syntax highlighting
pip3 install Pygments

# Install Node.js for Mermaid CLI
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
npm install -g @mermaid-js/mermaid-cli

# Configure MySQL
mysql -e "CREATE DATABASE mediawiki;"
mysql -e "CREATE USER 'mediawiki'@'localhost' IDENTIFIED BY '$(openssl rand -base64 32)';"
mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO 'mediawiki'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download and install MediaWiki
cd /tmp
wget https://releases.wikimedia.org/mediawiki/1.41/mediawiki-1.41.0.tar.gz
tar -xzf mediawiki-1.41.0.tar.gz
mv mediawiki-1.41.0 /var/www/html/mediawiki
chown -R www-data:www-data /var/html/www/mediawiki

# Configure Apache
cat > etc/apache2/sites-available/mediawiki.conf <<'EOF'
<VirtualHost *:80>
  ServerName squad4.wiki
  DocumentRoot /var/www/html/mediawiki

  <Directory /var/www/html/mediawiki>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>

  ErrorLog /var/log/apache2/mediawiki-error.log
  CustomLog /var/log/apache2/media-wiki-access.log combined
</VirtualHost>
EOF

a2ensite mediawiki.conf
a2dissite 000-default.conf
a2enmod rewrite
systemctl restart apache2

# Run MediaWiki installation
cd /var/www/html/mediawiki
php maintenance/install.php \
	--dbname=mediawiki \
	--dbserver=localhost \
	--dbuser=mediawiki \
	--dbpass="$(mysql -e "SELECT authentication_string FROM mysql.user WHERE user='mediawiki' AND host='localhost';" -sN)" \
	--scriptpath="" \
	--lang=en \
	--pass="${admin_password}" \
	"Squad4 Wiki" \
	"admin"

# Download and install extensions
cd /var/www/html/mediawiki/extensions

# SyntaxHighlight_GeSHi extension
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/SyntaxHighlight_GeSHi
cd SyntaxHighlight_GeSHi
composer install --no-dev
cd ..

# Mermaid extension
git clone https://github.com/SemanticMediaWiki/Mermaid.git
cd Mermaid
composer install --no-dev
cd ..

# GraphViz extension
git clone https://gerrit.wikimedia.org/r/wikimedia/extensions/GraphViz
cd GraphViz
composer install --no-dev
cd ..

# VisualEditor
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/VisualEditor
cd VisualEditor
composer install --no-dev
cd ..

# Configure LocalSettings.php
cat >> /var/www/html/mediawiki/LocalSettings.php <<'EOF'

# Enable file uploads
$wgEnableUploads = true;
$wgUseImageMagickConvertCommand = "/usr/bin/convert";

# SyntaxHighlight extension
wfLoadExtension( 'SyntaxHighlight_GeSHi' );

# Mermaid extension
wfLoadExtenion( 'Mermaid' );
$wgMermaidCli = '/usr/bin/mmdc';

# GraphViz extension
wfLoadExtension( 'GraphViz' );
$wgGraphVizSettings->execPath = '/usr/bin';

# VisualEditor
wfLoadExtension( 'VisualEditor' );
$wgDefaultUserOptions['visualeditor-enable'] = 1;
$wgVirtualRestConfig['modules']['parsoid'] = array (
  'url' => 'http://localhost/rest.php',
);

# Trust proxy headers from ALB
$wgUseCdn = true;
$wgCdnServers = array( '10.0.0.0/8' );

# Set up for authentication via ALB headers
If (isset($_SERVER['HTTP_X_AMZN_OIDC_DATA'])) {
   $wgAuth = new ExternalAuth();
   $wgGroupPermissions['*']['autocreateaccount'] = true;
   $wgGroupPermissiosn['*']['createaccount'] = false;
}

# Performance optimizations
$wgMainCacheType = CACHE_ACCEL;
$wgMemCachedServers = [];
$wgCacheDirector = "/var/cache/mediawiki";

# Permissions
$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['user']['edit'] = true;
EOF

# Create cache directory
mkdir -p /var/cache/mediawiki
chown www-data:www-data /var/cache/mediawiki

# Set proper permissions
chown -R www-data:www-data /var/www/html/mediawiki

# Create backup script
cat > /usr/local/bin/backup-mediawiki.sh <<'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mediawiki-backup-$TIMESTAMP"
S3_BUCKET="${s3_bucket}"
AWS_REGION="${aws_region}"

mkdir -p "$BACKUP_DIR"

# Backup files
tar -czf "$BACKUP_DIR/images.tar.gz" -c /var/www/html/mediawiki/images .
cp /var/www/html/mediawiki/LocalSettings.php "$BACKUP_DIR/"

# Create archive
cd /tmp
tar -czf "mediawiki-backup-$TIMESTAMP.tar.gz" "mediawiki-backup-$TIMESTAMP"

# Upload to S3
aws s3 cp "mediawiki-backup-$TIMESTAMP.tar.gz" "s3://$S3_BUCKET/backups/" --region "$AWS_REGION"

# Clean up
rm -rf "$BACKUP_DIR"
rm "mediawiki-backup-$TIMESTAMP.tar.gz"

# Log to CloudWatch (options, requires CloudWatch agent)
echo "Backup completed successfully: mediawiki-backup-$TIMESTAMP.tar.gz:
BACKUP_SCRIPT

chmod +x /usr/local/bin/backup-mediawiki.sh

# Schedule daily backups at 2AM
cat > /etc/cron.d/mediawiki-backup <<'CRON'
0 2 * * * root /usr/local/bin/backup-mediawiki.sh >> /var/log/mediawiki-backlog.log 2>&1
CRON

# Install Cloudwatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configure Cloudwatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collected_list": [
          {
            "file_path": "/var/log/media-wiki-backup.log",
            "log_group_name": "/mediawiki/apache-error",
            "log-stream-name": "{instance_id}"
          }
        }
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
	-a fetch-config \
	-m ec2 \
	-s \
	-c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Run initial backup
/usr/local/bin/backup-mediawiki.sh

echo "MediaWiki installation complete!"


