#!/usr/bin/env bash
# Zet tijdelijke AWS Academy Learner Lab-credentials in ~/.aws/credentials
# en test meteen de verbinding. Nodig omdat een lab-sessie na een paar uur
# verloopt en je dan nieuwe credentials uit "AWS Details" moet plakken.
#
# Dit script is identiek aan setup/lab-login.sh in Stensel8/Cloud-Security
# (ander vak, zelfde AWS Academy Learner Lab). Zelfde omgeving, dus één
# scriptje voor allebei in plaats van het steeds opnieuw uittypen.
set -euo pipefail

DEFAULT_PROFILE="${AWS_LAB_PROFILE:-}"

if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI niet gevonden. Installeer eerst de aws-cli." >&2
    exit 1
fi

read -rp "AWS Account ID (= profielnaam, zie AWS Details)${DEFAULT_PROFILE:+ [$DEFAULT_PROFILE]}: " PROFILE
PROFILE="${PROFILE:-$DEFAULT_PROFILE}"
[ -n "$PROFILE" ] || { echo "Account ID is verplicht." >&2; exit 1; }

read -rp "AWS Access Key ID: " ACCESS_KEY_ID
read -rsp "AWS Secret Access Key (invoer niet zichtbaar): " SECRET_ACCESS_KEY
echo
read -rsp "AWS Session Token (invoer niet zichtbaar): " SESSION_TOKEN
echo
read -rp "Regio [us-east-1]: " REGION
REGION="${REGION:-us-east-1}"

aws configure set aws_access_key_id "$ACCESS_KEY_ID" --profile "$PROFILE"
aws configure set aws_secret_access_key "$SECRET_ACCESS_KEY" --profile "$PROFILE"
aws configure set aws_session_token "$SESSION_TOKEN" --profile "$PROFILE"
aws configure set region "$REGION" --profile "$PROFILE"

echo
echo "Verbinding testen..."
if IDENTITY="$(aws sts get-caller-identity --profile "$PROFILE" --output json 2>&1)"; then
    echo "OK, credentials werken:"
    echo "$IDENTITY"
else
    echo "FOUT - credentials werken niet:" >&2
    echo "$IDENTITY" >&2
    exit 1
fi
