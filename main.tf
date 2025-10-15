terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_id" {
  description = "VPC ID where MediaWiki will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Private subnet IDs for EC2 instance"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EC2 instance"
  type        = list(string)
}

variable "vpn_cidr_blocks" {
  description = "CIDR blocks for VPN access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "mediawiki_admin_password" {
  description = "MediaWiki admin password"
  type        = string
  sensitive   = true
}

resouce "aws_s3_bucket" "mediawiki_backups" {
  bucket = "mediawiki-backups-${data.aws_caller_identity.current.account_id}"
  tags = {
    Name        = "MediaWiki Backups"
    Environment = "production"
  }
}

resource "aws_s3_bucket_versioning" "mediawiki_backups" {
  bucket = aws_s3_bucket.mediawiki_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mediawiki_backups" {
  bucket = aws_s3_bucket.mediawiki_backups.id

  rule {
    id     = "backup-retention"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      dats = 90
    }
  }
}

resouce "aws_route53_zone" "private" {
  name = "squad4.wiki"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "squad4.wiki private zone"
  }
}

# Security group for ALB
resource "aws_securuity_group" "alb" {
  name_description = "Security group for MedialWiki ALB"
  vpc_id           = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = tcp
    cidr_blocks = var.vpn_cidr_blocks
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.vpn_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mediawiki-alb-sg"
  }
}


resource "aws_security_group" "mediawiki" {
  name_description = "Security group for MediaWiki EC2 instance"
  vpc_id           = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws.security_group.alb.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "mediawiki-ec2-sg"
  }

}

resource "aws_iam_role" "mediawiki" {
  Version = "2012-10-17"
  Statement = [
    {
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }
  ]
}

resource "aws_iam_role_policy" "mediawiki_s3" {
  name = "mediawiki-s3-backup-policy"
  role = aws_iam_role.mediawiki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mediawiki_backups.arn,
          "${aws_s3_bucket.mediawiki_backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "mediawiki" {
  name = "mediawiki-instance-profile"
  role = aws_iam_role.mediawiki.name
}

# Application Load Balancer
resource "aws_lb" "mediawiki" {
  name               = "mediawiki-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "mediawiki-alb"
  }
}

resource "aws_lb_target_group" "mediawiki1" {
  name     = "mediawiki-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,301,302"
    path                = "/index.php/Main_Page"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "mediawiki_https" {
  load_balancer_arn = aws_lb.mediawiki.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certification_arn = aws_acm_certificate.mediawiki.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mediawiki.arn
  }
}

resource "aws_lb_listener" "mediawiki_http" {
  load_balancer_arn = aws_lb.mediawiki.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_acm_certificate" "mediawiki" {
  domain_name       = "squad4.wiki"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "squad4.wiki"
  }
}

# Route53 Record for ALB
resource "aws_route_53_record" "mediawiki" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "squad4.wiki"
  type    = "A"

  alias {
    name                   = aws_lb.mediawiki.dns_name
    zone_id                = aws_lb.mediawiki.zone_id
    evaluate_target_health = true
  }
}


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization_type"
    values = ["hvm"]
  }
}

resource "aws_instance" "mediawiki" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name               = var.key.name
  vpc_security_group_ids = [aws_security_group.mediawiki.id]
  subnet_id              = var.private_subnet_ids[0]
  iam_instance_profile   = aws_iam_instance_profile.mediawiki.name

  user_data = base64encode(templatefile("${path.module}/mediawiki-setup.sh", {
    admin_password = var.mediawiki1_admin_password
    s3_bucket      = aws_s3_bucket.mediawiki_backups-id
    aws_region     = var.aws_region
  }))

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "mediawiki-server"
  }
}

resource "aws_lb_target_group_attachment" "mediawiki" {
  target_group_arn = aws_lb_target_group.mediawiki.arn
  target_id        = aws_instance.mediawiki.id
  port             = 80
}

# Cloudwatch Log Group for backup logs
resource "aws_cloudwatch_log_group" "mediawiki_backups" {
  name              = "/mediawiki/backups"
  retention_in_days = 30
}

data "aws_caller_identity" "current" {}

# Outputs
output "mediawiki_url" {
  value       = "https://squad4.wiki"
  description = "MediaWiki URL"
}

output "s3_backup_bucket" {
  value       = aws_s3_bucket.mediawiki_backups.id
  description = "S3 bucket for backups"
}

output "ec2_instance_id" {
  value       = aws_instance.mediawiki.id
  description = "EC2 instance ID"
}

output "alb_dns_name" {
  value       = aws_lb.mediawiki.dns_name
  description = "ALB DNS name"
}


