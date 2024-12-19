provider "aws" {
  region = var.aws_region
}

# Generate a random string for a unique bucket name
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create an S3 bucket with a random name
resource "aws_s3_bucket" "my_bucket" {
  bucket = "r0845037-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "MyAppFileStorage"
    Environment = "Dev"
  }
}

# Create an IAM policy for S3 access
resource "aws_iam_policy" "s3_sync_policy" {
  name        = "S3SyncPolicy"
  description = "Allow EC2 to sync files from S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:Sync"
        ]
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Generate a new SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a new SSH key pair
resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Create IAM role for EC2 with permissions to assume the role
resource "aws_iam_role" "ec2_role" {
  name = "EC2RoleWithS3Access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_sync_policy.arn
}

# Create IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfileWithS3Access"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance with MySQL and attached IAM role
resource "aws_instance" "my_ec2" {
  ami                         = var.instance_ami
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated_key.key_name  # Use the generated key pair
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = <<-EOF
            #!/bin/bash
            apt update -y
            apt install -y apache2 mysql-server cron curl unzip

            # Install AWS CLI
            curl "https://d1vvhvl2y92vvt.cloudfront.net/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            rm awscliv2.zip

            systemctl start apache2
            systemctl enable apache2
            systemctl start mysql
            systemctl enable mysql

            # Modify the MySQL bind address to 0.0.0.0 to allow remote connections
            sed -i 's/^bind-address\s*=.*$/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
            systemctl restart mysql

            # Wait for MySQL to be ready
            while ! mysqladmin ping -h localhost --silent; do
              sleep 2
            done

            # Set up MySQL user and database
            mysql -e "CREATE DATABASE IF NOT EXISTS ${var.db_name};"
            mysql -e "CREATE USER IF NOT EXISTS '${var.db_username}'@'%' IDENTIFIED BY '${var.db_password}';"
            mysql -e "GRANT ALL PRIVILEGES ON ${var.db_name}.* TO '${var.db_username}'@'%';"
            mysql -e "FLUSH PRIVILEGES;"

            # Create 'files' table in the database
            mysql -e "USE ${var.db_name}; CREATE TABLE IF NOT EXISTS files (
              id INT AUTO_INCREMENT PRIMARY KEY,
              filename VARCHAR(255) NOT NULL,
              uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );"

            sudo chown -R www-data:www-data /var/www/html
            sudo chmod -R 755 /var/www/html

            # Ensure the web directory is clean
            rm -rf /var/www/html/*

            # Wait until the instance metadata service confirms the IAM role is attached
            until curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/; do
              sleep 5
            done

            sleep 30

            echo "* * * * * root export PATH=$PATH:/usr/local/bin && AWS_REGION=${var.aws_region} /usr/local/bin/aws s3 sync s3://${aws_s3_bucket.my_bucket.bucket}/ /var/www/html/ --exact-timestamps >> /var/log/s3-sync.log 2>&1" > /etc/cron.d/s3-sync

            # Set permissions for the cron job
            chmod 644 /etc/cron.d/s3-sync

            # Restart cron service to ensure the cron job runs
            systemctl restart cron

            # Ensure Apache service is started
            systemctl start apache2
            systemctl enable apache2
            EOF

  tags = {
    Name        = "MyWebServer"
    Environment = "Dev"
  }
}

# Security Group for EC2 (allow MySQL and HTTP access)
resource "aws_security_group" "ec2_mysql_sg" {
  name        = "ec2_mysql_sg"
  description = "Allow all traffic"

  # Ingress rule to allow all incoming traffic (ALL ALL)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0", "::/0"]  # Allow all sources (IPv4 and IPv6)
  }

  # Egress rule to allow all outgoing traffic (ALL ALL)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0", "::/0"]  # Allow all destinations (IPv4 and IPv6)
  }
}
