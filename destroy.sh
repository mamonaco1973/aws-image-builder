#!/bin/bash

# ==============================================================================
# DESTROY PIPELINE: TEARDOWN AND CLEANUP
# ==============================================================================
#
# This script performs a full teardown of resources created by the apply
# pipeline: the test servers, the AMIs and their snapshots, the Image Builder
# resources and script bucket, the build logs, the builder secret and the
# networking.
#
# WARNING:
# - This script is destructive and irreversible.
# - All matching AMIs, snapshots, and infrastructure will be removed.
# - Use only in non-production or controlled environments.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SET DEFAULT AWS REGION
# ==============================================================================
#
# Export the AWS region to ensure all AWS CLI commands run in the intended
# account and regional context.
# ==============================================================================

export AWS_DEFAULT_REGION="us-east-2"
# AWS_REGION, if set in the caller's shell, overrides AWS_DEFAULT_REGION.
export AWS_REGION="us-east-2"

# ==============================================================================
# STEP 1: DESTROY EC2 DEPLOYMENT (03-deploy)
# ==============================================================================
#
# Tear down the test servers launched from the AMIs.
# ==============================================================================

cd 03-deploy
terraform init
terraform destroy -auto-approve
cd ..

# ==============================================================================
# STEP 2: DEREGISTER THE AMIS AND DELETE THEIR SNAPSHOTS
# ==============================================================================
#
# Deleting an aws_imagebuilder_image removes the Image Builder record only;
# the AMI and its EBS snapshots stay behind. So deregister every games_ami*
# and desktop_ami* image here, then delete the snapshots it pointed at.
# ==============================================================================

for pattern in "games_ami*" "desktop_ami*"; do
  for ami_id in $(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=${pattern}" \
    --query "Images[].ImageId" \
    --output text); do

    # Read the snapshot IDs before the AMI is gone.
    snapshot_ids=$(aws ec2 describe-images \
      --image-ids "${ami_id}" \
      --query "Images[].BlockDeviceMappings[].Ebs.SnapshotId" \
      --output text)

    echo "NOTE: Deregistering AMI: ${ami_id}"
    aws ec2 deregister-image --image-id "${ami_id}"

    for snapshot_id in ${snapshot_ids}; do
      echo "NOTE: Deleting snapshot: ${snapshot_id}"
      aws ec2 delete-snapshot --snapshot-id "${snapshot_id}"
    done
  done
done

# ==============================================================================
# STEP 3: DESTROY IMAGE BUILDER RESOURCES (02-image-builder)
# ==============================================================================
#
# Removes the images, recipes, components, configurations, IAM role and the
# script bucket (force_destroy empties it first).
# ==============================================================================

cd 02-image-builder
terraform init
terraform destroy -auto-approve
cd ..

# ------------------------------------------------------------------------------
# Leftover Image Builder image versions
# ------------------------------------------------------------------------------
# A build that failed or was interrupted can leave an image version that
# Terraform no longer tracks. Delete any build of the lab's two recipes.
# ------------------------------------------------------------------------------

for recipe in games-recipe desktop-recipe; do
  for image_arn in $(aws imagebuilder list-images \
    --owner Self \
    --filters "name=name,values=${recipe}" \
    --query "imageVersionList[].arn" \
    --output text); do

    for build_arn in $(aws imagebuilder list-image-build-versions \
      --image-version-arn "${image_arn}" \
      --query "imageSummaryList[].arn" \
      --output text); do
      echo "NOTE: Deleting Image Builder image: ${build_arn}"
      aws imagebuilder delete-image --image-build-version-arn "${build_arn}" \
        > /dev/null
    done
  done

  # ----------------------------------------------------------------------------
  # Build logs
  # ----------------------------------------------------------------------------
  # Build instances write to /aws/imagebuilder/<recipe name>, a log group
  # Image Builder creates on the first build and never deletes.
  # ----------------------------------------------------------------------------

  log_group="/aws/imagebuilder/${recipe}"
  if aws logs describe-log-groups --log-group-name-prefix "${log_group}" \
      --query "logGroups[?logGroupName=='${log_group}'].logGroupName" \
      --output text | grep -q .; then
    echo "NOTE: Deleting log group: ${log_group}"
    aws logs delete-log-group --log-group-name "${log_group}"
  fi
done

# ==============================================================================
# STEP 4: DELETE THE BUILDER CREDENTIAL SECRET
# ==============================================================================
#
# Deleted here without a recovery window, so the next apply can create a
# secret with the same name straight away. Terraform's own delete in step 5
# would keep the name reserved for seven or more days.
# ==============================================================================

if aws secretsmanager describe-secret --secret-id "builder-credentials" \
    > /dev/null 2>&1; then
  aws secretsmanager delete-secret \
    --secret-id "builder-credentials" \
    --force-delete-without-recovery > /dev/null
  echo "NOTE: Deleted secret: builder-credentials"
fi

# ==============================================================================
# STEP 5: DESTROY NETWORKING INFRASTRUCTURE (01-infrastructure)
# ==============================================================================
#
# Tear down the VPC, subnets, route table and security groups.
# ==============================================================================

cd 01-infrastructure
terraform init
terraform destroy -auto-approve
cd ..
