#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$project/scripts/sources.sh"

usage() {
  echo 'Usage: build-image.sh pi4|pi5 DRIVER_REF USTREAMER_REF OUTPUT_DIR [OFFICIAL_IMAGE_URL [SHA1]]'
}

if [[ ${1:-} == --help ]]; then usage; exit 0; fi
if (( $# < 4 || $# > 6 )); then usage >&2; exit 2; fi
board=$1
base_url=$(official_image "$board")
base_url=${5:-$base_url}
validate_image_url "$base_url"
base_sha=${6:-$(image_sha1 "$base_url")}
[[ $base_sha =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid image SHA-1.' >&2; exit 2; }
if [[ $(uname -m) != aarch64 ]] && ! grep -qs '^enabled$' /proc/sys/fs/binfmt_misc/qemu-aarch64; then
  echo 'Register qemu-aarch64 with binfmt_misc or use a native ARM64 Linux host.' >&2
  exit 1
fi
sudo -v
driver_sha=$(resolve_commit "$driver_repo" "$2")
ustreamer_sha=$(resolve_commit "$ustreamer_repo" "$3")

mkdir -p -- "$4"
output=$(realpath -- "$4")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fetch_source() {
  local repo=$1 commit=$2 destination=$3
  git init -q "$destination"
  git -C "$destination" fetch -q --depth=1 "https://github.com/$repo.git" "$commit"
  git -C "$destination" checkout -q --detach FETCH_HEAD
  test "$(git -C "$destination" rev-parse HEAD)" = "$commit"
}

fetch_source "$driver_repo" "$driver_sha" "$work/driver"
fetch_source "$ustreamer_repo" "$ustreamer_sha" "$work/ustreamer"
download --max-time 1800 "$base_url" --output "$work/base.img.xz"
printf '%s  %s\n' "$base_sha" "$work/base.img.xz" | sha1sum --check --strict
xz -dc "$work/base.img.xz" | dd of="$work/disk.img" bs=1M conv=sparse status=none
rm -- "$work/base.img.xz"

sudo unshare --mount --propagation private -- \
  "$project/scripts/customize-image.sh" "$work" "$project" "$board"

name=rk628-pikvm-$board.img.xz
xz -T2 -3 -c "$work/disk.img" > "$work/$name"
if (( $(stat -c %s "$work/$name") >= 2147483648 )); then
  echo 'Compressed image exceeds the GitHub Release asset limit.' >&2
  exit 1
fi
xz -t "$work/$name"

{
  printf 'Board: %s\nPiKVM image: %s\nPiKVM image SHA-1: %s\n' "$board" "$base_url" "$base_sha"
  printf 'RK628 driver: %s\nRK628 driver commit: %s\n' "$2" "$driver_sha"
  printf 'RK628 uStreamer: %s\nRK628 uStreamer commit: %s\n' "$3" "$ustreamer_sha"
  printf 'Integration commit: %s\n' "$(git -C "$project" rev-parse HEAD)"
  cat "$work/packages.txt"
} > "$work/BUILD-INFO-$board.txt"
(cd "$work" && sha256sum "$name" "BUILD-INFO-$board.txt") > "$work/SHA256SUMS"
for file in "$name" "BUILD-INFO-$board.txt" SHA256SUMS; do
  mv -- "$work/$file" "$output/$file"
done
printf 'Image: %s/%s\n' "$output" "$name"
