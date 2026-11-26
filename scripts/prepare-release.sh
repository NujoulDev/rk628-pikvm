#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/sources.sh"
releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" | jq -s .)
drafts=$(jq -c '[.[][] | select(.draft)]' <<<"$releases")
replace_draft_id=
replace_fingerprint=
if [[ $(jq 'length' <<<"$drafts") != 0 ]]; then
  if [[ $GITHUB_EVENT_NAME == schedule ]] && [[ $(jq 'length' <<<"$drafts") == 1 ]]; then
    replace_fingerprint=$(jq -r '.[0] | select(([.assets[]? | .updated_at | fromdateiso8601?] | max // now) <= now - 604800)
      | (.body // "") | scan("<!-- rk628-auto-fingerprint: ([a-f0-9]{64}) -->") | .[0]' <<<"$drafts")
  fi
  if [[ ! $replace_fingerprint =~ ^[a-f0-9]{64}$ ]]; then
    echo 'A draft is already awaiting review.' >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  replace_draft_id=$(jq -r '.[0].id' <<<"$drafts")
fi

driver=${DRIVER_REF:-$(latest_tag "$driver_repo")}
ustreamer=${USTREAMER_REF:-$(latest_tag "$ustreamer_repo")}
driver_sha=$(resolve_commit "$driver_repo" "$driver")
ustreamer_sha=$(resolve_commit "$ustreamer_repo" "$ustreamer")
pi4=${PI4_URL:-$(official_image pi4)}
pi5=${PI5_URL:-$(official_image pi5)}
validate_image_url "$pi4"
validate_image_url "$pi5"
pi4_sha=$(image_sha1 "$pi4")
pi5_sha=$(image_sha1 "$pi5")
fingerprint=$(printf '%s\n' "$driver" "$driver_sha" "$ustreamer" "$ustreamer_sha" \
  "$pi4_sha" "$pi5_sha" | sha256sum)
fingerprint=${fingerprint%% *}

if [[ -n $replace_draft_id ]]; then
  if [[ $fingerprint == "$replace_fingerprint" ]]; then
    echo 'The existing draft already uses these upstream versions.' >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
elif [[ $GITHUB_EVENT_NAME == schedule ]]; then
  state=$(gh api --paginate "repos/$GITHUB_REPOSITORY/actions/artifacts?per_page=100" |
    jq -sr '[.[].artifacts[] | select(.expired == false and (.name | startswith("auto-image-")))]
      | (max_by(.id).name // "") | ltrimstr("auto-image-")')
  if [[ -z $state ]]; then
    state=$(jq -r '[.[][] | select(.draft == false)
      | {published_at, fingerprint: (.body // "" | [scan("<!-- rk628-auto-fingerprint: ([a-f0-9]{64}) -->")][0][0])}
      | select(.fingerprint)] | max_by(.published_at).fingerprint // empty' <<<"$releases")
  fi
  if [[ $fingerprint == "$state" ]]; then
    echo 'The automatic build already succeeded with these upstream versions.' >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
fi

{
  echo 'build=true'
  printf 'driver=%s\ndriver_sha=%s\nustreamer=%s\nustreamer_sha=%s\n' "$driver" "$driver_sha" "$ustreamer" "$ustreamer_sha"
  printf 'pi4_url=%s\npi4_sha=%s\npi5_url=%s\npi5_sha=%s\n' "$pi4" "$pi4_sha" "$pi5" "$pi5_sha"
  printf 'fingerprint=%s\n' "$fingerprint"
  printf 'replace_draft_id=%s\nreplace_fingerprint=%s\n' "$replace_draft_id" "$replace_fingerprint"
} >> "$GITHUB_OUTPUT"
