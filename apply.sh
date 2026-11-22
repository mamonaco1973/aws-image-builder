#!/bin/bash

# ==============================================================================
# APPLY PIPELINE: BUILD AND DEPLOY ENVIRONMENT
# ==============================================================================
#
# This script performs an apply-only workflow to:
# - Validate the local execution environment
# - Provision networking infrastructure with Terraform
# - Build Linux and Windows AMIs with EC2 Image Builder
# - Deploy EC2 instances from the generated AMIs
# - Output public access details for deployed instances
#
# The script is intentionally one-directional and does not perform teardown.
# Execution stops immediately if any step fails.
# ==============================================================================

# ------------------------------------------------------------------------------
# Strict shell behavior
# ------------------------------------------------------------------------------
# -e         Exit immediately if any command fails
# -u         Treat unset variables as errors
# -o pipefail  Fail if any command in a pipeline fails
# ------------------------------------------------------------------------------
set -euo pipefail

# ==============================================================================
# STEP 0: ENVIRONMENT VALIDATION
# ==============================================================================
#
# Verify that required tools, credentials, and prerequisites are available
# before continuing with infrastructure changes.
# ==============================================================================

./check_env.sh

# ==============================================================================
# STEP 1: SET AWS DEFAULT REGION
# ==============================================================================
#
# Define the AWS region used by all subsequent AWS CLI and Terraform
# operations executed by this script.
# ==============================================================================

export AWS_DEFAULT_REGION="us-east-2"
# AWS_REGION, if set in the caller's shell, overrides AWS_DEFAULT_REGION.
export AWS_REGION="us-east-2"

# ==============================================================================
# STEP 2: TERRAFORM APPLY - NETWORKING INFRASTRUCTURE
# ==============================================================================
#
# Provision base networking resources required for Image Builder builds and
# EC2 deployments: VPC, subnets, security groups and the builder secret.
# ==============================================================================

echo "NOTE: Applying networking infrastructure"

cd 01-infrastructure
terraform init
terraform apply -auto-approve
cd ..

# ==============================================================================
# STEP 3: BUILD AMIS WITH EC2 IMAGE BUILDER
# ==============================================================================
#
# One terraform apply builds both AMIs in parallel. Each
# aws_imagebuilder_image resource starts a build and blocks until its AMI is
# available, so this step takes as long as the slower (Windows) build.
# The build instances read the builder password from Secrets Manager
# themselves; nothing is passed in from here.
# ==============================================================================

echo "NOTE: Building AMIs with EC2 Image Builder"

cd 02-image-builder
terraform init
terraform apply -auto-approve
cd ..

# ==============================================================================
# STEP 4: TERRAFORM APPLY - EC2 DEPLOYMENT
# ==============================================================================
#
# Deploy EC2 instances using the most recently built AMIs.
# ==============================================================================

echo "NOTE: Deploying EC2 instances"

cd 03-deploy
terraform init
terraform apply -auto-approve
cd ..

# ==============================================================================
# STEP 5: VALIDATE THE BUILD.
# ==============================================================================

./validate.sh