# ==============================================================================
# WINDOWS DESKTOP AMI: COMPONENT, RECIPE, DISTRIBUTION, IMAGE
# ==============================================================================
#
# Same result as windows_ami.pkr.hcl: Windows Server 2025, fully updated,
# with the builder account, Chrome, Firefox, a clean desktop and boot.ps1
# in C:\mcloud\ for userdata to run on each new instance.
#
# Recipe order:
#   1. update-windows  (AWS-managed: installs updates, reboots as needed;
#                       replaces the windows-update and windows-restart
#                       Packer provisioners)
#   2. desktop-setup   (ours: security, boot.ps1, Chrome, Firefox, desktop)
#
# bootstrap_win.ps1 is gone: it only existed to set up WinRM for Packer.
# ==============================================================================

locals {
  win_scripts = "C:\\mcloud-build"

  # Run one of our scripts in its own PowerShell and fail the step if the
  # script fails. Our scripts signal failure with `exit 1`.
  win_run = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File"
}

resource "aws_imagebuilder_component" "desktop_setup" {
  name     = "desktop-setup"
  platform = "Windows"
  version  = local.build_version

  data = yamlencode({
    name          = "desktop-setup"
    description   = "Builder account, browsers, desktop and boot.ps1"
    schemaVersion = 1.0
    phases = [{
      name = "build"
      steps = [
        {
          name   = "DownloadScripts"
          action = "S3Download"
          inputs = [
            {
              source      = "s3://${aws_s3_bucket.scripts.id}/windows/*"
              destination = "${local.win_scripts}\\"
            },
            {
              # boot.ps1 stays in the image; 03-deploy's userdata runs it.
              source      = "s3://${aws_s3_bucket.scripts.id}/windows/boot.ps1"
              destination = "C:\\mcloud\\boot.ps1"
            }
          ]
        },
        {
          # The password is read here, on the instance, with the instance
          # profile (AWS Tools for PowerShell ship with the AMI). It is never
          # a component parameter, so it never shows in the console.
          name   = "CreateBuilderUser"
          action = "ExecutePowerShell"
          inputs = {
            commands = [<<-EOT
              $ErrorActionPreference = "Stop"
              $secret = Get-SECSecretValue `
                -SecretId ${local.secret_name} `
                -Region ${local.region}
              $env:BUILDER_PASSWORD = ($secret.SecretString |
                ConvertFrom-Json).password
              ${local.win_run} ${local.win_scripts}\security.ps1
              if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            EOT
            ]
          }
        },
        {
          name   = "InstallChrome"
          action = "ExecutePowerShell"
          inputs = {
            commands = [
              "${local.win_run} ${local.win_scripts}\\chrome.ps1",
              "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"
            ]
          }
        },
        {
          name   = "InstallFirefox"
          action = "ExecutePowerShell"
          inputs = {
            commands = [
              "${local.win_run} ${local.win_scripts}\\firefox.ps1",
              "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"
            ]
          }
        },
        {
          name   = "CleanDesktop"
          action = "ExecutePowerShell"
          inputs = {
            commands = [
              "${local.win_run} ${local.win_scripts}\\desktop.ps1",
              "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"
            ]
          }
        },
        {
          name   = "RemoveBuildScripts"
          action = "ExecutePowerShell"
          inputs = {
            commands = [
              "Remove-Item -Recurse -Force ${local.win_scripts}"
            ]
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

resource "aws_imagebuilder_image_recipe" "desktop" {
  name    = "desktop-recipe"
  version = local.build_version

  parent_image      = data.aws_ami.windows.id
  working_directory = "C:\\"

  component {
    component_arn = "${local.aws_component}/update-windows/x.x.x"
  }

  component {
    component_arn = aws_imagebuilder_component.desktop_setup.arn
  }

  block_device_mapping {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 64
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  # Immutable: a new base AMI or component list needs a version bump. Until
  # then a newer Windows release is ignored, so re-running apply on a live
  # lab stays a no-op instead of failing on an existing name and version.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [parent_image]
  }
}

resource "aws_imagebuilder_distribution_configuration" "desktop" {
  name = "desktop-distribution"

  distribution {
    region = local.region

    ami_distribution_configuration {
      # 03-deploy finds the newest desktop_ami* image, as it did with Packer.
      name = "desktop_ami_{{ imagebuilder:buildDate }}"

      ami_tags = {
        Name = "desktop_ami"
      }
    }
  }
}

resource "aws_imagebuilder_image" "desktop" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.desktop.arn
  infrastructure_configuration_arn = local.infrastructure_arn
  distribution_configuration_arn = (
    aws_imagebuilder_distribution_configuration.desktop.arn
  )

  # See the games image: the lab tests the AMI by deploying it in 03-deploy.
  image_tests_configuration {
    image_tests_enabled = false
  }

  # Windows Update alone can take well over an hour.
  timeouts {
    create = "3h"
  }

  # Rebuild when any Windows script changes in S3.
  lifecycle {
    replace_triggered_by = [aws_s3_object.windows]
  }
}

output "desktop_ami_id" {
  value = one(aws_imagebuilder_image.desktop.output_resources[0].amis).image
}
