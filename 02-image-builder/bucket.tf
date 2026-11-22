# ==============================================================================
# S3 BUCKET: BUILD SCRIPTS AND HTML
# ==============================================================================
#
# Components download their scripts from here with the S3Download action.
# force_destroy lets `terraform destroy` remove the bucket with its objects.
# ==============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "scripts" {
  bucket        = "image-builder-scripts-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Objects: one per file, keyed by its path under 02-image-builder/
# ------------------------------------------------------------------------------
# The etag makes Terraform re-upload a file when it changes, and the image
# resources rebuild when any of these objects is replaced or updated.
# ------------------------------------------------------------------------------

resource "aws_s3_object" "linux" {
  for_each = fileset(path.module, "linux/**")

  bucket = aws_s3_bucket.scripts.id
  key    = each.value
  source = "${path.module}/${each.value}"
  etag   = filemd5("${path.module}/${each.value}")
}

resource "aws_s3_object" "windows" {
  for_each = fileset(path.module, "windows/*.ps1")

  bucket = aws_s3_bucket.scripts.id
  key    = each.value
  source = "${path.module}/${each.value}"
  etag   = filemd5("${path.module}/${each.value}")
}
