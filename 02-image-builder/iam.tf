# ==============================================================================
# IAM: BUILD INSTANCE ROLE AND INSTANCE PROFILE
# ==============================================================================
#
# The build instance needs:
# - AmazonSSMManagedInstanceCore: Image Builder runs every step through SSM.
# - EC2InstanceProfileForImageBuilder: fetch components, write build logs.
# - Read access to the scripts bucket (GetObject, plus ListBucket for the
#   wildcard S3Download of linux/html/*).
# - GetSecretValue on the one builder-credentials secret.
# ==============================================================================

resource "aws_iam_role" "image_builder" {
  name = "image-builder-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.image_builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "image_builder" {
  role       = aws_iam_role.image_builder.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy" "build_inputs" {
  name = "image-builder-build-inputs"
  role = aws_iam_role.image_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.scripts.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.scripts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = data.aws_secretsmanager_secret.builder_credentials.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "image_builder" {
  name = "image-builder-instance-profile"
  role = aws_iam_role.image_builder.name
}
