#!/bin/bash
# ==============================================================================
# check_env.sh — confirm the tools and AWS credentials the lab needs
#
# No Packer here: Image Builder runs the builds inside AWS, so Terraform and
# the AWS CLI are all that has to be installed locally.
# ==============================================================================

set -euo pipefail

echo "NOTE: Validating that required commands are found in your PATH."
# List of required commands
commands=("aws" "terraform" "jq" "curl")

# Flag to track if all commands are found
all_found=true

# Iterate through each command and check if it's available
for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is not found in the current PATH."
    all_found=false
  else
    echo "NOTE: $cmd is found in the current PATH."
  fi
done

# Final status
if [ "$all_found" = true ]; then
  echo "NOTE: All required commands are available."
else
  echo "ERROR: One or more commands are missing."
  exit 1
fi

echo "NOTE: Checking AWS cli connection."

if ! aws sts get-caller-identity --query "Account" --output text \
    > /dev/null; then
  echo "ERROR: Failed to connect to AWS. Please check your credentials" \
       "and environment variables."
  exit 1
fi
echo "NOTE: Successfully logged into AWS."
