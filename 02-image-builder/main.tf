# ==============================================================================
# EC2 IMAGE BUILDER: GAMES (UBUNTU) AND DESKTOP (WINDOWS) AMIS
# ==============================================================================
#
# This phase replaces the Packer templates. Terraform defines the Image
# Builder pieces (components, recipes, infrastructure and distribution
# configurations) and one aws_imagebuilder_image per AMI. Creating an image
# resource starts a build and blocks until the AMI exists, so `terraform
# apply` here does what `packer build` did.
#
# Image Builder drives the build instance through SSM: there is no SSH or
# WinRM communicator, no inbound port, and no Packer binary.
#
# The scripts in linux/ and windows/ stay the source of truth. They are
# uploaded to an S3 bucket created here, and the components pull them with
# S3Download before running them.
# ==============================================================================

provider "aws" {
  # AWS region where the builds run and the AMIs are registered.
  region = "us-east-2"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region = data.aws_region.current.region

  # --------------------------------------------------------------------------
  # Versions
  # --------------------------------------------------------------------------
  # Image Builder components and recipes are immutable: a name and version
  # pair can only ever hold one definition. Any change to a component's YAML
  # or a recipe (including a new base AMI) needs this version bumped, or the
  # create fails with "already exists". Script changes in linux/ or windows/
  # do NOT need a bump: the scripts live in S3, and changing one rebuilds the
  # image (see replace_triggered_by on the image resources).
  # --------------------------------------------------------------------------
  build_version = "1.0.0"

  # AWS-managed components, resolved to their newest version at build time.
  aws_component = "arn:aws:imagebuilder:${local.region}:aws:component"

  secret_name = data.aws_secretsmanager_secret.builder_credentials.name
}

# ==============================================================================
# LOOKUPS: NETWORKING AND SECRET FROM 01-INFRASTRUCTURE
# ==============================================================================

data "aws_subnet" "build_subnet" {
  # Public subnet: map_public_ip_on_launch gives the build instance a public
  # IP, its only route to SSM, S3 and Secrets Manager (no VPC endpoints).
  filter {
    name   = "tag:Name"
    values = ["packer-subnet-1"]
  }
}

data "aws_security_group" "build_sg" {
  # Egress-only group: Image Builder needs no inbound access.
  filter {
    name   = "tag:Name"
    values = ["image-builder-sg"]
  }

  vpc_id = data.aws_subnet.build_subnet.vpc_id
}

data "aws_secretsmanager_secret" "builder_credentials" {
  # Read on the build instance to create the local builder account.
  name = "builder-credentials"
}

# ==============================================================================
# BASE IMAGES: SAME FILTERS AS THE PACKER TEMPLATES
# ==============================================================================

data "aws_ami" "ubuntu" {
  # Newest Canonical Ubuntu 24.04 (Noble) AMD64 image.
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["*ubuntu-noble-24.04-amd64-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "windows" {
  # Newest Windows Server 2025 English Full Base image from Amazon.
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
