# RK628 on PiKVM

**English** | [简体中文](README.zh-CN.md)

This guide explains how to use PiKVM on Raspberry Pi 4 and Raspberry Pi 5 with the `Radxa 4K HDMI IN to MIPI CSI-2 Adapter` for HDMI video and audio capture.

The official DIY PiKVM setups do not support audio capture, and the Pi 5 setup does not support HDMI-to-CSI-2 adapters. This setup therefore uses a modified uStreamer that adds software H.264 encoding on Pi 5, HDMI-to-CSI-2 support on Pi 5, and audio capture on both platforms. See the [uStreamer RK628 branch](https://github.com/NujoulDev/ustreamer/tree/rk628) for details.

## Test environments

| Platform | OS | Architecture | Kernel |
| --- | --- | --- | --- |
| Raspberry Pi 4 | PiKVM OS — DIY PiKVM V2 HDMI-CSI image | `aarch64` | `6.12.105-1-rpi` |
| Raspberry Pi 5 | PiKVM OS — DIY PiKVM V2 HDMI-USB image | `aarch64` | `6.12.116-1-rpi` |

Pi 4 and Pi 5 use the same modified uStreamer. The versions of the software and additional encoding dependencies are listed below:

| Component | Version |
| --- | --- |
| uStreamer | `6.67`, `rk628` branch, based on upstream `v6.67` |
| x264 | `3:0.165.r3222.b35605a-2` |
| FFmpeg | `2:9.0.2-5` |
| libswscale | `10.1.102` |
| libavutil | `61.1.102` |

## Hardware connections

For audio and video capture wiring, see [Hardware connections in the README](https://github.com/NujoulDev/rk628-rpi-driver#hardware-connections). For the remaining PiKVM wiring, see the [official DIY PiKVM V2 wiring instructions](https://docs.pikvm.org/v2/#wiring).

## Installation and configuration

Choose one installation method.

1. [Flash a preconfigured image](#flash-a-preconfigured-image). Download and flash the Release image.
2. [Install manually](#install-manually). Install the RK628 driver and modified µStreamer on the official PiKVM OS image.

### Flash a preconfigured image

- Pi 4: [rk628-pikvm-pi4.img.xz](https://github.com/NujoulDev/rk628-pikvm/releases/latest/download/rk628-pikvm-pi4.img.xz).
- Pi 5: [rk628-pikvm-pi5.img.xz](https://github.com/NujoulDev/rk628-pikvm/releases/latest/download/rk628-pikvm-pi5.img.xz).

Select the downloaded `.img.xz` in Raspberry Pi Imager using the [official flashing guide](https://docs.pikvm.org/flashing_os/#using-rpi-imager-linux-macos-and-windows). After booting, follow [Verification](#verification) to check video and audio.

> [!IMPORTANT]
> The preconfigured Pi 5 image uses CAM/DISP1 by default. If your adapter is connected to CAM/DISP0, boot the Pi, run `rw` as root, change `dtoverlay=rk628-pi5,cam1,audio` to `dtoverlay=rk628-pi5,cam0,audio` in `/boot/config.txt`, then reboot.

### Install manually

Select and flash the image for your board from the [official image download page](https://docs.pikvm.org/flashing_os/#download-the-image), then install the RK628 driver and modified µStreamer.

- Pi 4: `DIY PiKVM V2 Platform → Raspberry Pi 4 64-bit → For HDMI-CSI bridge`.
- Pi 5: `DIY PiKVM V2 Platform → Raspberry Pi 5 64-bit → For HDMI-USB dongle`.

#### Dependencies

Run all commands below as root. PiKVM runs in read-only mode by default. Use `rw` to switch to read-write mode and `ro` to return to read-only mode. The system returns to read-only mode after rebooting.

Make sure the Raspberry Pi is connected to the internet, then update the system:

```bash
pikvm-update
```

After the update finishes and you have rebooted as prompted, switch to read-write mode and install the dependencies:

```bash
rw

pacman -S --needed \
  git gcc make pkgconf dkms dtc linux-rpi-headers-pikvm \
  v4l-utils alsa-utils x264 ffmpeg
```

If prompted to select a dependency provider (`default=1`), press Enter to use the default option `1`. At `Proceed with installation? [Y/n]`, enter `y` and press Enter.

#### Driver

Clone the driver:

```bash
cd /root
git clone https://github.com/NujoulDev/rk628-rpi-driver.git
cd rk628-rpi-driver
```

Check that headers are available for the running kernel, then run the installer.

```bash
ls "/lib/modules/$(uname -r)/build/Makefile" && ./scripts/install.sh
```

When the driver installation succeeds, `Done.` is displayed. The script also installs the DTBO and udev rules. After rebooting, `/dev/rk628-*` device aliases are created automatically. PiKVM uses the modified uStreamer to configure the capture pipeline; do not install or enable media-initd.

Edit the boot configuration:

```bash
vim /boot/config.txt
```

Remove or comment out existing `dtoverlay=tc358743` and `dtoverlay=tc358743-audio` lines, including any parameters. If `camera_auto_detect=1` is present, change it to `camera_auto_detect=0`.

Add the `dtoverlay` line for your board to the `[all]` section. If the file has no `[all]` section, add one at the end.

Raspberry Pi 4:

```ini
dtoverlay=rk628-pi4,audio
```

Install the custom EDID on Pi 4:

```bash
git clone https://github.com/NujoulDev/rk628-pikvm.git /root/rk628-pikvm
install -m 644 /root/rk628-pikvm/edid/rk628-pikvm.hex \
  /etc/kvmd/tc358743-edid.hex
```

Raspberry Pi 5 (connected to CAM/DISP0):

```ini
dtoverlay=rk628-pi5,cam0,audio
```

For CAM/DISP1, replace `cam0` with `cam1`. The YAML and JCFG configuration below does not need to change.

Save the file and reboot to apply the driver and overlay:

```bash
reboot
```

After rebooting, check the devices:

```bash
v4l2-ctl --list-devices
arecord -l
```

Pi 4 should list a `unicam` video device. Pi 5 should list `rp1-cfe` video devices and an RK628 subdevice. The audio capture device list should include `RK628HDMI`.

#### RK628 uStreamer

Clone the uStreamer `rk628` branch:

```bash
rw
cd /root
git clone --branch rk628 --single-branch \
  https://github.com/NujoulDev/ustreamer.git ustreamer-rk628
cd ustreamer-rk628
```

Build the uStreamer application and Janus plugin:

```bash
make clean
make -j4 \
  WITH_LIBX264=1 \
  WITH_JANUS=1 \
  WITH_GPIO=1 \
  WITH_SYSTEMD=1 \
  WITH_V4P=1
```

`WITH_LIBX264=1` enables software H.264 encoding on the CPU. `WITH_JANUS=1` builds the Janus plugin with automatic detection of the RK628 audio sample rate.

Once the build succeeds, stop the services and install:

```bash
systemctl stop kvmd kvmd-janus

make \
  WITH_LIBX264=1 \
  WITH_JANUS=1 \
  WITH_GPIO=1 \
  WITH_SYSTEMD=1 \
  WITH_V4P=1 \
  PREFIX=/usr install
```

`PREFIX=/usr` installs to the paths used by PiKVM, including `/usr/bin/ustreamer` and `/usr/lib/ustreamer/janus/libjanus_ustreamer.so`.

Check the build features of the installed application:

```bash
/usr/bin/ustreamer --features
```

The output should include the following enabled features. `+` means enabled and `-` means disabled:

```text
+ WITH_LIBX264
+ WITH_JANUS
+ WITH_V4P
+ WITH_GPIO
+ WITH_SYSTEMD
```

`+ WITH_LIBX264` indicates that software H.264 encoding support has been compiled in. If any of these features show `-`, check the build options and installation steps above.

Check the new encoder selection option:

```bash
/usr/bin/ustreamer --help | grep h264-encoder
```

The output should include:

```text
--h264-encoder <type>  ───────── H264 encoder: M2M or CPU (requires WITH_LIBX264=1). Default: M2M.
```

#### PiKVM configuration

The configurations below apply to the Pi 4 HDMI-CSI image and Pi 5 HDMI-USB image specified above. If you already have a configuration, merge the relevant fields instead of adding duplicate YAML keys.

##### Raspberry Pi 4

Edit `/etc/kvmd/janus/janus.plugin.ustreamer.jcfg` and replace the existing `acap` block with:

```text
acap: {
    device = "plughw:RK628HDMI,0"
    v4l2 = "/dev/kvmd-video"
}
```

##### Raspberry Pi 5

Once the udev rules installed with the driver take effect, use the following device aliases:

| Configuration option | Device name |
| --- | --- |
| YAML: `--device` | `/dev/rk628-video` |
| YAML: `--media-device` | `/dev/rk628-media` |
| YAML: `--media-entity-name` | `/dev/rk628-subdev` |
| JCFG: `acap.v4l2` | `/dev/rk628-subdev` |

Check that all three aliases exist and that the topology includes RK628 and `rp1-cfe-csi2_ch0`:

```bash
ls -l /dev/rk628-video /dev/rk628-media /dev/rk628-subdev
media-ctl -d /dev/rk628-media -p
```

Edit `/etc/kvmd/override.yaml`:

```yaml
kvmd:
    streamer:
        quality: 80
        resolution:
            default: ""
            available: []
        h264_bitrate:
            default: 5000
        h264_gop:
            default: 30
        cmd_remove:
            - "--device=/dev/kvmd-video"
            - "--format=mjpeg"
            - "--resolution={resolution}"
        cmd_append:
            - "--device=/dev/rk628-video"
            - "--media-device=/dev/rk628-media"
            - "--media-entity-name=/dev/rk628-subdev"
            - "--dv-timings"
            - "--format=uyvy"
            - "--quality={quality}"
            - "--h264-encoder=cpu"
            - "--h264-sink=kvmd::ustreamer::h264"
            - "--h264-bitrate={h264_bitrate}"
            - "--h264-gop={h264_gop}"

media:
    memsink:
        h264:
            sink: "kvmd::ustreamer::h264"
```

Pi 5 uses the CPU to encode JPEG and H.264 separately.

Edit `/etc/kvmd/janus/janus.plugin.ustreamer.jcfg` and replace the existing `acap` block with:

```text
acap: {
    device = "plughw:RK628HDMI,0"
    v4l2 = "/dev/rk628-subdev"
}
```

#### WebRTC buffer configuration

Configure the send buffer to reduce dropped frames and stuttering when WebRTC sends bursts of video data. Pi 4 and Pi 5 use the same settings.

Create the configuration file:

```bash
mkdir -p /etc/sysctl.d
vim /etc/sysctl.d/99-rk628-pikvm.conf
```

Add:

```ini
net.core.wmem_default = 4194304
net.core.wmem_max = 4194304
```

Apply the configuration. It will also be loaded automatically on subsequent boots:

```bash
sysctl -p /etc/sysctl.d/99-rk628-pikvm.conf
```

#### Apply the configuration

Leave the other JCFG blocks unchanged. Do not set a fixed `sampling_rate` on either platform; the audio sample rate is detected automatically and follows the HDMI input.

Allow Janus to access V4L2 devices and check the YAML configuration:

```bash
usermod -aG video kvmd-janus
kvmd -m >/dev/null
```

Once all configuration is complete and the check passes, enable and restart the required services, then return to read-only mode:

```bash
systemctl enable kvmd-janus kvmd-media
systemctl restart kvmd kvmd-janus kvmd-media
sync
ro
```

## Verification

The default terminal username and password are both `root`. The default web username and password are both `admin`. After first login, change both passwords using the [official PiKVM instructions](https://docs.pikvm.org/auth/).

Using the [PiKVM UI](https://docs.pikvm.org/webui/), check that the HDMI picture is displayed correctly. Switch to WebRTC mode and check the audio. Video and audio should recover automatically after the HDMI input resolution or audio sample rate changes, without restarting the services.

For instructions on using PiKVM's features, see the [official user documentation](https://docs.pikvm.org/webui/).
