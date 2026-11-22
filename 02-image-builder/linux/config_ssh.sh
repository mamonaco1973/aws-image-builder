#!/bin/bash

# ------------------ Sanity Check: Ensure BUILDER_PASSWORD is set ------------------

# Exit immediately if BUILDER_PASSWORD is empty or unset
if [[ -z "${BUILDER_PASSWORD}" ]]; then
  echo "ERROR: BUILDER_PASSWORD is not set. Aborting user creation." >&2
  exit 1
fi

# ------------------ User Creation: 'builder' Setup ------------------

# Create the 'builder' user with:
# -m : create a home directory under /home/builder
# -s : set default shell to /bin/bash
# If the user already exists, this will fail — no retry logic included
sudo useradd -m -s /bin/bash builder

# ------------------ Password Assignment: Secure Access ------------------

# Use chpasswd to set the user's password securely
# Injecting the password via stdin (secure and script-friendly)
# Note: BUILDER_PASSWORD is assumed to be set in the environment (e.g., via export or passed in)
echo "builder:$BUILDER_PASSWORD" | sudo chpasswd

# ------------------ Sudo Privileges: Grant Passwordless Access ------------------

# Append sudoer config line to a dedicated file for the user
# This enables 'builder' to run ANY command as ANY user WITHOUT a password prompt
echo "builder ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/builder

# Secure the sudoers file with strict permissions
# Must be 0440 or sudo will reject it (and potentially break sudo access)
sudo chmod 440 /etc/sudoers.d/builder
