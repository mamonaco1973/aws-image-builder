# ==============================================================================
# LINUX GAMES AMI: COMPONENT, RECIPE, DISTRIBUTION, IMAGE
# ==============================================================================
#
# Same result as linux_ami.pkr.hcl: Ubuntu 24.04 with Apache serving the
# HTML games and a local builder account with a password and sudo.
#
# Recipe order:
#   1. update-linux             (AWS-managed: apt upgrade)
#   2. aws-cli-version-2-linux  (AWS-managed: lets the next step read the
#                                secret; Ubuntu ships without the AWS CLI)
#   3. games-setup              (ours: install.sh, then config_ssh.sh)
# ==============================================================================

resource "aws_imagebuilder_component" "games_setup" {
  name     = "games-setup"
  platform = "Linux"
  version  = local.build_version

  data = yamlencode({
    name          = "games-setup"
    description   = "Apache, the HTML games and the builder account"
    schemaVersion = 1.0
    phases = [{
      name = "build"
      steps = [
        {
          # Same staging paths the Packer file provisioners used.
          name   = "DownloadFiles"
          action = "S3Download"
          inputs = [
            {
              source      = "s3://${aws_s3_bucket.scripts.id}/linux/html/*"
              destination = "/tmp/html/"
            },
            {
              source      = "s3://${aws_s3_bucket.scripts.id}/linux/install.sh"
              destination = "/tmp/builder/install.sh"
            },
            {
              source = join("", [
                "s3://${aws_s3_bucket.scripts.id}",
                "/linux/config_ssh.sh"
              ])
              destination = "/tmp/builder/config_ssh.sh"
            }
          ]
        },
        {
          name   = "InstallApacheAndGames"
          action = "ExecuteBash"
          inputs = {
            commands = ["bash /tmp/builder/install.sh"]
          }
        },
        {
          # The password is read here, on the instance, with the instance
          # profile. It is never a component parameter, so it never shows
          # in the console or the component definition.
          name   = "CreateBuilderUser"
          action = "ExecuteBash"
          inputs = {
            commands = [<<-EOT
              set -euo pipefail
              secret=$(aws secretsmanager get-secret-value \
                --region ${local.region} \
                --secret-id ${local.secret_name} \
                --query SecretString --output text)
              field='import json,sys; print(json.load(sys.stdin)["password"])'
              BUILDER_PASSWORD=$(printf '%s' "$secret" | python3 -c "$field")
              export BUILDER_PASSWORD
              bash /tmp/builder/config_ssh.sh
            EOT
            ]
          }
        },
        {
          name   = "RemoveBuildScripts"
          action = "ExecuteBash"
          inputs = {
            commands = ["rm -rf /tmp/builder"]
          }
        }
      ]
    }]
  })

  # Immutable: a changed definition needs a new version (local.build_version).
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_imagebuilder_image_recipe" "games" {
  name    = "games-recipe"
  version = local.build_version

  parent_image      = data.aws_ami.ubuntu.id
  working_directory = "/tmp"

  component {
    component_arn = "${local.aws_component}/update-linux/x.x.x"
  }

  component {
    component_arn = "${local.aws_component}/aws-cli-version-2-linux/x.x.x"
  }

  component {
    component_arn = aws_imagebuilder_component.games_setup.arn
  }

  block_device_mapping {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 16
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  # Immutable: a new base AMI or component list needs a version bump. Until
  # then a newer Ubuntu release is ignored, so re-running apply on a live lab
  # stays a no-op instead of failing on an existing name and version.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [parent_image]
  }
}

resource "aws_imagebuilder_distribution_configuration" "games" {
  name = "games-distribution"

  distribution {
    region = local.region

    ami_distribution_configuration {
      # 03-deploy finds the newest games_ami* image, as it did with Packer.
      name = "games_ami_{{ imagebuilder:buildDate }}"

      ami_tags = {
        Name = "games_ami"
      }
    }
  }
}

resource "aws_imagebuilder_image" "games" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.games.arn
  infrastructure_configuration_arn = local.infrastructure_arn
  distribution_configuration_arn = (
    aws_imagebuilder_distribution_configuration.games.arn
  )

  # The test phase launches a second instance from the new AMI and runs test
  # components against it. This lab's proof is 03-deploy plus validate.sh,
  # so testing here would only add build time and cost.
  image_tests_configuration {
    image_tests_enabled = false
  }

  timeouts {
    create = "3h"
  }

  # Rebuild when any script or HTML file changes in S3.
  lifecycle {
    replace_triggered_by = [aws_s3_object.linux]
  }
}

output "games_ami_id" {
  value = one(aws_imagebuilder_image.games.output_resources[0].amis).image
}
