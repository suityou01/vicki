#!/usr/bin/env bash
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

# Install Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# Generate a random password for MySQL
DB_PASSWORD=$(openssl rand -base64 32)

# Configure MySQL - connect via socket as root (script is run as root in Docker)
mysql -e "CREATE DATABASE IF NOT EXISTS mediawiki;"
mysql -e "CREATE USER IF NOT EXISTS 'mediawiki'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "CREATE USER IF NOT EXISTS 'mediawiki'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO 'mediawiki'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO 'mediawiki'@'127.0.0.1';"
mysql -e "FLUSH PRIVILEGES;"

# Download and install MediaWiki
if [ ! -d "/var/www/html/mediawiki" ]; then
    cd /tmp
    wget https://releases.wikimedia.org/mediawiki/1.41/mediawiki-1.41.0.tar.gz
    tar -xzf mediawiki-1.41.0.tar.gz
    mv mediawiki-1.41.0 /var/www/html/mediawiki
    chown -R www-data:www-data /var/www/html/mediawiki
fi

# Configure Apache
cat > /etc/apache2/sites-available/mediawiki.conf <<'EOF'
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
service apache2 restart

# Run MediaWiki installation
if [ ! -f "/var/www/html/mediawiki/LocalSettings.php" ]; then
    cd /var/www/html/mediawiki
    php maintenance/install.php \
        --dbname=mediawiki \
        --dbserver=localhost \
        --dbuser=mediawiki \
        --dbpass="${DB_PASSWORD}" \
        --scriptpath="" \
        --lang=en \
        --pass="${admin_password}" \
        "Squad4 Wiki" \
        "admin"
fi

# Download and install extensions
cd /var/www/html/mediawiki/extensions

# SyntaxHighlight_GeSHi extension
if [ ! -d "SyntaxHighlight_GeSHi" ]; then
    git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/SyntaxHighlight_GeSHi
    cd SyntaxHighlight_GeSHi
    composer install --no-dev
    cd ..
fi

# Mermaid extension
if [ ! -d "Mermaid" ]; then
    git clone https://github.com/SemanticMediaWiki/Mermaid.git
    cd Mermaid
    composer install --no-dev
    cd ..
fi

# GraphViz extension - skip for now, older extension format
# if [ ! -d "GraphViz" ]; then
#     git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/GraphViz
# fi

# VisualEditor
if [ ! -d "VisualEditor" ]; then
    git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/VisualEditor
    cd VisualEditor
    composer install --no-dev
    cd ..
fi

# Configure LocalSettings.php
cat >> /var/www/html/mediawiki/LocalSettings.php <<'EOF'

# Set the server URL (important for Docker port mapping)
$wgServer = "http://localhost:8080";

# Enable file uploads
$wgEnableUploads = true;
$wgUseImageMagickConvertCommand = "/usr/bin/convert";

# SyntaxHighlight extension
wfLoadExtension( 'SyntaxHighlight_GeSHi' );

# Mermaid extension
wfLoadExtension( 'Mermaid' );
$wgMermaidCli = '/usr/bin/mmdc';

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
if (isset($_SERVER['HTTP_X_AMZN_OIDC_DATA'])) {
   $wgAuth = new ExternalAuth();
   $wgGroupPermissions['*']['autocreateaccount'] = true;
   $wgGroupPermissions['*']['createaccount'] = false;
}

# Performance optimizations
$wgMainCacheType = CACHE_ACCEL;
$wgMemCachedServers = [];
$wgCacheDirectory = "/var/cache/mediawiki";

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

mkdir -p "$BACKUP_DIR"

# Backup files
tar -czf "$BACKUP_DIR/images.tar.gz" -C /var/www/html/mediawiki/images .
cp /var/www/html/mediawiki/LocalSettings.php "$BACKUP_DIR/"

# Create archive
cd /tmp
tar -czf "mediawiki-backup-$TIMESTAMP.tar.gz" "mediawiki-backup-$TIMESTAMP"

echo "Backup completed successfully: mediawiki-backup-$TIMESTAMP.tar.gz"

# Clean up
rm -rf "$BACKUP_DIR"
BACKUP_SCRIPT

chmod +x /usr/local/bin/backup-mediawiki.sh

echo "MediaWiki installation complete!"
