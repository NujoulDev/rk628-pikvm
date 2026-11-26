#!/usr/bin/env bash
set -euo pipefail

output=$1
for board in pi4 pi5; do
  (cd "$output/$board" && sha256sum --check --strict SHA256SUMS)
done
mkdir -p "$output/release"
for board in pi4 pi5; do
  mv -- "$output/$board/rk628-pikvm-$board.img.xz" "$output/release/"
done
cd "$output/release"
{
  printf 'Driver ref: %s\nuStreamer ref: %s\n' "$DRIVER_REF" "$USTREAMER_REF"
  printf 'Build: %s/%s/actions/runs/%s\n\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
  cat ../pi4/BUILD-INFO-pi4.txt
  printf '\n'
  cat ../pi5/BUILD-INFO-pi5.txt
} > BUILD-INFO.txt
sha256sum rk628-pikvm-pi{4,5}.img.xz BUILD-INFO.txt > SHA256SUMS

endpoint="repos/$GITHUB_REPOSITORY/releases"
drafts=$(gh api --paginate "$endpoint?per_page=100" --jq '.[] | select(.draft) | .html_url')
if [[ -n $drafts ]]; then
  echo "A draft already exists: $drafts" >&2
  exit 1
fi

tag="image-$(date -u +%Y%m%d)-$GITHUB_RUN_ID"
release_id=$(gh api --method POST "$endpoint" --jq .id \
  -f tag_name="$tag" -f name="$tag" -f target_commitish="$GITHUB_SHA" \
  -f body='Images are being uploaded. Wait for the Actions run to finish before testing.' -F draft=true)
[[ $release_id =~ ^[0-9]+$ ]]
cleanup() {
  if [[ $(gh api "$endpoint/$release_id" --jq .draft) == true ]]; then
    gh api --method DELETE "$endpoint/$release_id" --silent
  fi
}
trap cleanup EXIT
gh release upload "$tag" rk628-pikvm-pi{4,5}.img.xz SHA256SUMS BUILD-INFO.txt --repo "$GITHUB_REPOSITORY"
notes='RK628 PiKVM images for Raspberry Pi 4 and Pi 5. See BUILD-INFO.txt for the exact inputs.'
if [[ $GITHUB_EVENT_NAME == schedule ]]; then
  printf -v notes '%s\n\n<!-- rk628-auto-fingerprint: %s -->' "$notes" "$FINGERPRINT"
fi
url=$(gh api --method PATCH "$endpoint/$release_id" -f body="$notes" --jq .html_url)
trap - EXIT
printf '[Image draft](%s)\n' "$url" >> "$GITHUB_STEP_SUMMARY"
