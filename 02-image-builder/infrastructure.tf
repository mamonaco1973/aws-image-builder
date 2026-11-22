# ==============================================================================
# INFRASTRUCTURE CONFIGURATION: WHERE AND HOW BUILD INSTANCES RUN
# ==============================================================================
#
# Shared by both images. The build instance launches in builder-subnet-1
# (public, auto-assigned public IP) with the egress-only image-builder-sg.
# ==============================================================================

resource "aws_imagebuilder_infrastructure_configuration" "build" {
  name                  = "image-builder-lab-infrastructure"
  description           = "Build instances for the games and desktop AMIs"
  instance_profile_name = aws_iam_instance_profile.image_builder.name
  instance_types        = ["m5.large"]
  subnet_id             = data.aws_subnet.build_subnet.id
  security_group_ids    = [data.aws_security_group.build_sg.id]

  # Clean up a failed build instead of leaving it running for debugging.
  terminate_instance_on_failure = true

  # The role's policies must exist before a build can use the profile.
  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy_attachment.image_builder,
    aws_iam_role_policy.build_inputs,
  ]
}

locals {
  infrastructure_arn = aws_imagebuilder_infrastructure_configuration.build.arn
}
