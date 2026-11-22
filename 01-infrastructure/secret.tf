# ==============================================================================
# SECURELY GENERATE AND STORE BUILDER CREDENTIALS
# ==============================================================================
#
# This module generates a strong random password and stores the resulting
# username/password pair in AWS Secrets Manager.
#
# Notes:
# - The secret value is versioned automatically via Secrets Manager.
# - The password is generated at apply time and should not be hardcoded.
# - Consider enabling automatic rotation if this secret is long-lived.
# - Image Builder components read this secret on the build instance (via its
#   instance profile) to create the local builder account. The password is
#   never a component parameter, so it never shows in the console.
# ==============================================================================

resource "random_password" "generated" {
  # Generate a random password for the builder user.
  length = 24

  # Use an alphanumeric-only password for broad compatibility.
  special = false
}

resource "aws_secretsmanager_secret" "builder_credentials" {
  # Create the Secrets Manager secret container (metadata + IAM target).
  name = "builder-credentials"
}

resource "aws_secretsmanager_secret_version" "builder_credentials_version" {
  # Store the secret value as a new version on the secret container.
  secret_id = aws_secretsmanager_secret.builder_credentials.id

  # Persist credentials as JSON for easy consumption by scripts and tooling.
  secret_string = jsonencode({
    user     = "builder"
    password = random_password.generated.result
  })
}

output "builder_secret_arn" {
  # 02-image-builder grants the build instance read access to this one ARN.
  value = aws_secretsmanager_secret.builder_credentials.arn
}
