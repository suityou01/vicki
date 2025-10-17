FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables that would normally come from Terraform
ENV admin_password=testpassword123
ENV s3_bucket=test-bucket
ENV aws_region=eu-west-2

# Copy the setup script
COPY mediawiki-setup.sh /tmp/mediawiki-setup.sh

# Make it executable
RUN chmod +x /tmp/mediawiki-setup.sh

# Expose port 80
EXPOSE 80

# Run the setup script and start Apache in foreground
CMD ["/bin/bash", "-c", "/tmp/mediawiki-setup.sh && apachectl -D FOREGROUND"]
