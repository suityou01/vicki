FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV admin_password=testpassword123
ENV s3_bucket=test-bucket
ENV aws_region=eu-west-2
ENV NVM_DIR=/usr/local/nvm
ENV NODE_VERSION=22.14.0

# Install base packages (but don't configure MySQL yet)
RUN apt-get update \
    && apt-get install -y curl apache2 mysql-server \
    && apt-get -y autoclean

# Setup MySQL user and directories
RUN id mysql || useradd -r -s /bin/false mysql \
    && mkdir -p /var/run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /var/run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql \
    && chmod 777 /var/run/mysqld

# Replace shell with bash
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Setup NVM and Node.js
RUN mkdir /usr/local/nvm -p \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Add node and npm to path
ENV NODE_PATH=$NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# Confirm installation
RUN node -v && npm -v

# Copy the setup script (but don't run it yet)
COPY mediawiki-docker-setup.sh /tmp/mediawiki-setup.sh
RUN chmod +x /tmp/mediawiki-setup.sh

# Expose port 80
EXPOSE 80

# Create a startup script
RUN cat > /start.sh << 'EOF'
#!/bin/bash
set -e

# Initialize MySQL data directory if needed
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
fi

# Start MySQL
echo "Starting MySQL..."
mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld
/usr/sbin/mysqld --user=mysql --daemonize --skip-networking=0

# Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready!"
        break
    fi
    echo "Waiting for MySQL... ($i/30)"
    sleep 2
done

# Check if MediaWiki is already installed
if [ ! -f "/var/www/html/mediawiki/LocalSettings.php" ]; then
    echo "Running MediaWiki setup..."
    /tmp/mediawiki-setup.sh
else
    echo "MediaWiki already installed, skipping setup..."
fi

# Stop Apache if it's running (from the setup script)
echo "Stopping any existing Apache processes..."
service apache2 stop || true
sleep 2

echo "Starting Apache in foreground..."
apachectl -D FOREGROUND
EOF

RUN chmod +x /start.sh

# Run the startup script
CMD ["/start.sh"]
