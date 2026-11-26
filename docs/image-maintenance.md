# Image maintenance

## Build an image locally

Use a Linux host with `sudo`, Git, curl, xz, util-linux, and `udevadm`. An x86-64 host also
needs ARM64 emulation registered with `binfmt_misc` (for example, via
`qemu-user-static`). Use `TMPDIR` to select a disk with room for the unpacked
image if needed. Run the command from the repository root.

```bash
./scripts/build-image.sh pi5 DRIVER_REF USTREAMER_REF out/pi5
```

Replace the refs with Release tags or full commit SHAs. Use `pi4` and `out/pi4`
for Pi 4. The build starts from the official image for that board, updates its
packages for matching kernel headers, and installs the RK628 components. To use a
specific official image, append its `.img.xz` URL. The output contains the
image, `SHA256SUMS`, and a build record.

## Image releases

In Actions, run **PiKVM images** to build the Pi 4 and Pi 5 images. Leave the inputs blank to use the latest formal RK628 driver and µStreamer Releases and the latest official PiKVM image for each board. A manual run skips the build while a Release draft is awaiting review.

The scheduled check builds images for both boards when an upstream input changes. It replaces an automatic draft only after seven days and only if an upstream input has changed. It removes the old draft after both new images are uploaded. Manual drafts stay available until you publish or discard them.

After a successful build, download both images from the Release draft and flash them for testing. Once both pass, publish the draft manually on GitHub. See `BUILD-INFO.txt` for the versions and commits used to build the images.
