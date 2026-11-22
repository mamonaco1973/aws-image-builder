# ==============================================================================
# SECURITY GROUPS FOR THE LAB
# ==============================================================================
#
# The HTTP, HTTPS, SSH and RDP groups are used by the 03-deploy test servers;
# the last group is the egress-only group for Image Builder build instances.
#
# Notes:
# - Ingress rules are intentionally permissive for demo convenience.
# - These rules are NOT suitable for production workloads.
# - Restrict CIDR ranges or remove rules entirely in hardened environments.
# ==============================================================================

# ==============================================================================
# SECURITY GROUP: HTTP (PORT 80)
# ==============================================================================

resource "aws_security_group" "builder_sg_http" {
  # Security group allowing inbound HTTP traffic.
  name        = "builder-sg-http"
  description = "Allow inbound HTTP and unrestricted outbound traffic"
  vpc_id      = aws_vpc.builder-vpc.id

  # Allow inbound HTTP traffic from any IPv4 address.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic for package installs and updates.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "builder-sg-http"
  }
}

# ==============================================================================
# SECURITY GROUP: HTTPS (PORT 443)
# ==============================================================================

resource "aws_security_group" "builder_sg_https" {
  # Security group allowing inbound HTTPS traffic.
  name        = "builder-sg-https"
  description = "Allow inbound HTTPS and unrestricted outbound traffic"
  vpc_id      = aws_vpc.builder-vpc.id

  # Allow inbound HTTPS traffic from any IPv4 address.
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic for updates and external access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "builder-sg-https"
  }
}

# ==============================================================================
# SECURITY GROUP: SSH (PORT 22)
# ==============================================================================

resource "aws_security_group" "builder_ssh" {
  # Security group allowing inbound SSH access.
  name        = "builder-sg-ssh"
  description = "Allow inbound SSH and unrestricted outbound traffic"
  vpc_id      = aws_vpc.builder-vpc.id

  # Allow inbound SSH traffic from any IPv4 address.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic for provisioning and downloads.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "builder-sg-ssh"
  }
}

# ==============================================================================
# SECURITY GROUP: RDP (PORT 3389)
# ==============================================================================

resource "aws_security_group" "builder_sg_rdp" {
  # Security group allowing inbound RDP access.
  name        = "builder-sg-rdp"
  description = "Allow inbound RDP and unrestricted outbound traffic"
  vpc_id      = aws_vpc.builder-vpc.id

  # Allow inbound RDP traffic from any IPv4 address.
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic for provisioning and system updates.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "builder-sg-rdp"
  }
}

# ==============================================================================
# SECURITY GROUP: IMAGE BUILDER BUILD INSTANCES (EGRESS ONLY)
# ==============================================================================
#
# Image Builder drives the build instance through SSM, which the agent
# reaches outbound over 443. Nothing ever connects in, so this group has no
# ingress rules at all: no SSH, no WinRM.
# ==============================================================================

resource "aws_security_group" "image_builder_sg" {
  name        = "image-builder-sg"
  description = "Image Builder build instances: outbound only"
  vpc_id      = aws_vpc.builder-vpc.id

  # Outbound for SSM, S3, Secrets Manager, package mirrors and installers.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "image-builder-sg"
  }
}
