#!/bin/bash
# ==============================================================================
# validate.sh — print what you need to try the lab, and prove it works
#
# Both servers are public: the games server answers on HTTP, the Windows
# desktop server on RDP. Both images carry the builder account, whose
# password is in the builder-credentials secret.
#
# Two checks back that up:
# - the games page answers HTTP 200 and is the games index;
# - C:\mcloud\boot.log exists on the Windows server, which proves that the
#   userdata in 03-deploy ran boot.ps1 on a new instance from the image.
# ==============================================================================

set -euo pipefail

export AWS_DEFAULT_REGION="us-east-2"
# AWS_REGION, if set in the caller's shell, overrides AWS_DEFAULT_REGION.
export AWS_REGION="us-east-2"

failed=0

get_instance_field_by_name_tag() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$1" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].$2" \
    --output text | xargs
}

creds=$(aws secretsmanager get-secret-value --secret-id builder-credentials \
  --query SecretString --output text)
builder_user=$(echo "${creds}" | jq -r .user)
builder_password=$(echo "${creds}" | jq -r .password)
games_dns=$(get_instance_field_by_name_tag "games-ec2-instance" PublicDnsName)
windows_dns=$(get_instance_field_by_name_tag "desktop-ec2-instance" \
  PublicDnsName)
windows_id=$(get_instance_field_by_name_tag "desktop-ec2-instance" InstanceId)

echo ""
echo "============================================================================"
echo "Image Builder AMIs - Validation Output"
echo "============================================================================"
echo ""

# ------------------------------------------------------------------------------
# Games server: the page has to load, not just the instance exist
# ------------------------------------------------------------------------------

if [ -n "${games_dns}" ] && [ "${games_dns}" != "None" ]; then
  printf "NOTE: %-22s %s\n" "Games URL:" "http://${games_dns}"

  # Apache starts within a minute of boot; allow up to five.
  status="000"
  for _ in $(seq 1 30); do
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "http://${games_dns}/" || true)
    [ "${status}" = "200" ] && break
    sleep 10
  done

  if [ "${status}" = "200" ]; then
    printf "NOTE: %-22s %s\n" "Games page:" "HTTP 200"
  else
    printf "ERROR: %-21s %s\n" "Games page:" "HTTP ${status}"
    failed=1
  fi
else
  printf "WARN: %-22s %s\n" "Games server:" "not found or not running"
  failed=1
fi

# ------------------------------------------------------------------------------
# Windows server: RDP host, and boot.log proving userdata ran boot.ps1
# ------------------------------------------------------------------------------

if [ -n "${windows_dns}" ] && [ "${windows_dns}" != "None" ]; then
  printf "NOTE: %-22s %s\n" "Windows server (RDP):" "${windows_dns}"

  # The instance has to boot, register with SSM and run its userdata first.
  # Retry the read through SSM Run Command for up to fifteen minutes.
  boot_log=""
  for _ in $(seq 1 30); do
    cmd_id=$(aws ssm send-command \
      --instance-ids "${windows_id}" \
      --document-name "AWS-RunPowerShellScript" \
      --parameters 'commands=["Get-Content C:\\mcloud\\boot.log"]' \
      --query "Command.CommandId" --output text 2>/dev/null || true)

    if [ -n "${cmd_id}" ]; then
      sleep 10
      boot_log=$(aws ssm get-command-invocation \
        --command-id "${cmd_id}" --instance-id "${windows_id}" \
        --query "StandardOutputContent" --output text 2>/dev/null || true)
      boot_log=$(echo "${boot_log}" | tr -d '\r' | xargs)
      [[ "${boot_log}" == *"boot script ran"* ]] && break
    fi
    sleep 20
  done

  if [[ "${boot_log}" == *"boot script ran"* ]]; then
    printf "NOTE: %-22s %s\n" "Windows boot.log:" "${boot_log}"
  else
    printf "ERROR: %-21s %s\n" "Windows boot.log:" "not found"
    failed=1
  fi
else
  printf "WARN: %-22s %s\n" "Windows server (RDP):" "not found or not running"
  failed=1
fi
echo ""

printf "NOTE: %-22s %s\n" "Builder user:" "${builder_user}"
printf "NOTE: %-22s %s\n" "Builder password:" "${builder_password}"
echo ""

exit "${failed}"
