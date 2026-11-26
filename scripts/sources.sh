#!/usr/bin/env bash

# shellcheck disable=SC2034
driver_repo=NujoulDev/rk628-rpi-driver
# shellcheck disable=SC2034
ustreamer_repo=NujoulDev/ustreamer

official_image() {
  local target
  case "$1" in
    pi4) target=v2-hdmi-rpi4 ;;
    pi5) target=v2-hdmiusb-rpi5 ;;
    *) return 1 ;;
  esac
  printf 'https://files.pikvm.org/images/%s/aarch64/%s-aarch64-latest.img.xz\n' "$target" "$target"
}

download() {
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 20 "$@"
}

validate_image_url() {
  [[ $1 =~ ^https://files[.]pikvm[.]org/images/[A-Za-z0-9._/-]+[.]img[.]xz$ ]] || {
    printf 'Expected an official PiKVM .img.xz URL: %s\n' "$1" >&2
    return 1
  }
}

image_sha1() {
  local checksum
  checksum=$(download --max-time 60 "$1.sha1" | awk 'NR == 1 {print tolower($1)}') || return
  if [[ ! $checksum =~ ^[a-f0-9]{40}$ ]]; then
    printf 'Invalid image SHA-1 for %s\n' "$1" >&2
    return 1
  fi
  printf '%s\n' "$checksum"
}

latest_tag() {
  gh api "repos/$1/releases/latest" --jq .tag_name || {
    printf 'A formal Release is required for %s. Specify a ref for manual builds.\n' "$1" >&2
    return 1
  }
}

resolve_commit() {
  local repo=$1 ref=$2 refs tag
  if [[ $ref =~ ^[a-f0-9]{40}$ ]]; then
    printf '%s\n' "$ref"
    return
  fi
  tag="refs/tags/$ref"
  git check-ref-format "$tag" || return
  refs=$(git ls-remote --exit-code "https://github.com/$repo.git" "$tag" "$tag^{}") || return
  awk -v tag="$tag" '$2 == tag {obj=$1} $2 == tag "^{}" {commit=$1}
    END {if (commit) print commit; else if (obj) print obj; else exit 1}' <<<"$refs"
}
