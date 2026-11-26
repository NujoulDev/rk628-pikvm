#!/usr/bin/env bash
set -euo pipefail

work=$1
project=$2
board=$3
root=$work/root
mkdir -- "$root"
loop=$(flock /run/lock/rk628-image-loop.lock losetup --find --show --partscan "$work/disk.img")
cleanup() {
  if mountpoint -q "$root"; then
    umount -R "$root" || return
  fi
  losetup --detach "$loop"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

udevadm settle
boot=
system=
for partition in "$loop"p*; do
  case "$(blkid -s LABEL -o value "$partition" || true)" in
    PIBOOT) boot=$partition ;;
    PIROOT) system=$partition ;;
  esac
done
: "${boot:?PiKVM boot partition PIBOOT not found}" "${system:?PiKVM root partition PIROOT not found}"

mount "$system" "$root"
mount "$boot" "$root/boot"
test -f "$root/boot/config.txt"
test -f "$root/etc/kvmd/override.yaml"
if ! chroot "$root" /usr/bin/true; then
  echo 'The ARM64 image requires an ARM64 host or registered qemu-aarch64 binfmt support.' >&2
  exit 1
fi

mount -t tmpfs -o nosuid,mode=0755 tmpfs "$root/dev"
mknod -m 666 "$root/dev/null" c 1 3
mknod -m 666 "$root/dev/zero" c 1 5
mknod -m 666 "$root/dev/random" c 1 8
mknod -m 666 "$root/dev/urandom" c 1 9
ln -s /proc/self/fd "$root/dev/fd"

staging=$root/tmp/rk628-image
mkdir -m 700 -- "$staging"
for source in driver ustreamer; do
  mkdir "$staging/$source"
  git -c safe.directory="$work/$source" -C "$work/$source" archive HEAD | tar -x -C "$staging/$source"
done
cp -a -- "$project/config" "$staging/config"
install -m 644 "$project/edid/rk628-pikvm.hex" "$staging/edid.hex"
install -m 644 "$project/scripts/install-in-image.sh" "$staging/install.sh"
install -m 644 "$project/scripts/configure-image.py" "$staging/configure.py"
# Copy DNS options into the image temporarily, preserving its first-boot configuration.
cp -a -- "$root/etc/resolv.conf" "$staging/resolv.conf.original"
rm -- "$root/etc/resolv.conf"
if [[ -r /run/systemd/resolve/resolv.conf ]]; then
  install -m 644 /run/systemd/resolve/resolv.conf "$root/etc/resolv.conf"
else
  install -m 644 /etc/resolv.conf "$root/etc/resolv.conf"
fi
# shellcheck disable=SC2016
unshare --mount --propagation private --pid --fork --kill-child -- bash -eu -c '
  mount -t proc -o ro,nosuid,nodev,noexec proc "$1/proc"
  exec chroot "$1" /usr/bin/env -i PATH=/usr/bin HOME=/root LC_ALL=C \
    /usr/bin/bash /tmp/rk628-image/install.sh "$2"
' rk628-image "$root" "$board"
install -m 644 "$staging/packages.txt" "$work/packages.txt"
mv -fT -- "$staging/resolv.conf.original" "$root/etc/resolv.conf"
rm -rf -- "$staging"
sync -f "$root/boot"
sync -f "$root"
cleanup
trap - EXIT
