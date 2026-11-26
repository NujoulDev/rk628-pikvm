# RK628 on PiKVM

[English](README.md) | **简体中文**

该文档主要讲解如何基于 `瑞莎 4K HDMI IN 转 MIPI CSI-2 转接板` 在 Raspberry Pi 4 和 Raspberry Pi 5 使用 PiKVM，实现 HDMI 视频和音频采集。

PiKVM 官方的 DIY 方案并不支持音频采集，而且 Pi5 平台上不支持 HDMI 转 CSI-2 方案，所以该文档的方案使用了经过修改的 uStreamer，增加了 Pi5 软件 H.264 编码，额外支持 Pi5 的HDMI 转 CSI-2 及两个平台的音频采集。详情见 [uStreamer RK628 分支](https://github.com/NujoulDev/ustreamer/tree/rk628)。

## 测试环境

| 平台 | 系统 | 架构 | 内核 |
| --- | --- | --- | --- |
| Raspberry Pi 4 | PiKVM OS — DIY PiKVM V2 HDMI-CSI 镜像 | `aarch64` | `6.12.105-1-rpi` |
| Raspberry Pi 5 | PiKVM OS — DIY PiKVM V2 HDMI-USB 镜像 | `aarch64` | `6.12.116-1-rpi` |

Pi4 和 Pi5 均安装同一个修改版 uStreamer，软件及新增编码依赖的版本参考如下：

| 组件 | 版本 |
| --- | --- |
| uStreamer | `6.67`，`rk628` 分支，基于上游 `v6.67` |
| x264 | `3:0.165.r3222.b35605a-2` |
| FFmpeg | `2:9.0.2-5` |
| libswscale | `10.1.102` |
| libavutil | `61.1.102` |

## 硬件连接

音视频采集接线参考 [README 的硬件连接](https://github.com/NujoulDev/rk628-rpi-driver/blob/main/README.zh-CN.md#硬件连接)，其他 PiKVM 所需接线参考 [DIY PiKVM V2 官方接线说明](https://docs.pikvm.org/v2/#wiring)。

## 安装与配置

选择一种安装方式：

1. [烧录预配置镜像](#烧录预配置镜像)，下载 Release 镜像直接烧录。
2. [手动安装](#手动安装)，在官方 PiKVM OS 上安装 RK628 驱动和修改版 µStreamer。

### 烧录预配置镜像

- pi4：[rk628-pikvm-pi4.img.xz](https://github.com/NujoulDev/rk628-pikvm/releases/latest/download/rk628-pikvm-pi4.img.xz)
- pi5：[rk628-pikvm-pi5.img.xz](https://github.com/NujoulDev/rk628-pikvm/releases/latest/download/rk628-pikvm-pi5.img.xz)

按[官方烧录说明](https://docs.pikvm.org/flashing_os/#using-rpi-imager-linux-macos-and-windows)在 Raspberry Pi Imager 中选择下载的 `.img.xz`。启动后按[验证](#验证)检查画面和音频。

> [!IMPORTANT]
> Pi 5 预配置镜像默认使用 CAM/DISP1。如果转接板接在 CAM/DISP0，启动后以 root 运行 `rw`，将 `/boot/config.txt` 中的 `dtoverlay=rk628-pi5,cam1,audio` 改为 `dtoverlay=rk628-pi5,cam0,audio`，然后重启。

### 手动安装

从[官方镜像下载页面](https://docs.pikvm.org/flashing_os/#download-the-image)选择并烧录对应镜像，再安装 RK628 驱动和修改版 µStreamer。

- Pi4：`DIY PiKVM V2 Platform → Raspberry Pi 4 64-bit → For HDMI-CSI bridge`。
- Pi5：`DIY PiKVM V2 Platform → Raspberry Pi 5 64-bit → For HDMI-USB dongle`。

#### 依赖

以下命令均以 root 用户执行。PiKVM 默认以只读模式运行，`rw` 切换为可写，`ro` 恢复只读；重启后系统会恢复只读模式。

确保树莓派已联网，执行系统更新：

```bash
pikvm-update
```

更新完成并按提示重启后，切换为可写模式并安装依赖：

```bash
rw

pacman -S --needed \
  git gcc make pkgconf dkms dtc linux-rpi-headers-pikvm \
  v4l-utils alsa-utils x264 ffmpeg
```

安装过程中，如提示选择依赖提供者（`default=1`），直接按回车使用默认选项 `1`；出现 `Proceed with installation? [Y/n]` 时，输入 `y` 并按回车。

#### 驱动

下载驱动：

```bash
cd /root
git clone https://github.com/NujoulDev/rk628-rpi-driver.git
cd rk628-rpi-driver
```

确认当前内核的头文件可用后运行安装脚本。

```bash
ls "/lib/modules/$(uname -r)/build/Makefile" && ./scripts/install.sh
```

驱动安装成功后显示 `Done.`，同时安装 DTBO 和 udev 规则，重启后自动建立 `/dev/rk628-*` 设备别名。PiKVM 使用修改版 uStreamer 配置采集链路，不安装或启用 media-initd。

编辑启动配置：

```bash
vim /boot/config.txt
```

删除或注释原有的 `dtoverlay=tc358743`、`dtoverlay=tc358743-audio` 配置行（包括带参数的行）。如有 `camera_auto_detect=1`，将其改为 `camera_auto_detect=0`。

将对应机型的 `dtoverlay` 配置行加到 `[all]` 段。如果文件中没有 `[all]` 段，就在末尾添加。

Raspberry Pi 4：

```ini
dtoverlay=rk628-pi4,audio
```

Pi4 安装自定义 EDID：

```bash
git clone https://github.com/NujoulDev/rk628-pikvm.git /root/rk628-pikvm
install -m 644 /root/rk628-pikvm/edid/rk628-pikvm.hex \
  /etc/kvmd/tc358743-edid.hex
```

Raspberry Pi 5（连接 CAM/DISP0）：

```ini
dtoverlay=rk628-pi5,cam0,audio
```

连接 CAM/DISP1 时，将 `cam0` 改为 `cam1`；下方的 YAML 和 JCFG 配置无需更改。

保存后重启，使驱动和 overlay 生效：

```bash
reboot
```

重启后检查设备：

```bash
v4l2-ctl --list-devices
arecord -l
```

Pi4 应列出 `unicam` 视频设备；Pi5 应列出 `rp1-cfe` 视频设备和 RK628 子设备。音频采集设备列表应包含 `RK628HDMI`。

#### RK628 uStreamer

下载 ustreamer rk628 分支源码：

```bash
rw
cd /root
git clone --branch rk628 --single-branch \
  https://github.com/NujoulDev/ustreamer.git ustreamer-rk628
cd ustreamer-rk628
```

编译 uStreamer 主程序和 Janus 插件：

```bash
make clean
make -j4 \
  WITH_LIBX264=1 \
  WITH_JANUS=1 \
  WITH_GPIO=1 \
  WITH_SYSTEMD=1 \
  WITH_V4P=1
```

其中 `WITH_LIBX264=1` 启用 CPU 软件 H.264 编码，`WITH_JANUS=1` 构建包含 RK628 动态音频采样率检测的 Janus 插件。

编译成功后，停止服务并安装：

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

`PREFIX=/usr` 将程序安装到 PiKVM 使用的路径，包括 `/usr/bin/ustreamer` 和 `/usr/lib/ustreamer/janus/libjanus_ustreamer.so`。

检查已安装程序的编译选项：

```bash
/usr/bin/ustreamer --features
```

输出应包含以下启用项，`+` 表示已启用，`-` 表示未启用：

```text
+ WITH_LIBX264
+ WITH_JANUS
+ WITH_V4P
+ WITH_GPIO
+ WITH_SYSTEMD
```

其中 `+ WITH_LIBX264` 表示已编入 CPU 软件 H.264 编码支持。若这些选项显示为 `-`，需检查前面的编译参数和安装步骤。

检查新增的编码器选择参数：

```bash
/usr/bin/ustreamer --help | grep h264-encoder
```

输出应包含：

```text
--h264-encoder <type>  ───────── H264 encoder: M2M or CPU (requires WITH_LIBX264=1). Default: M2M.
```

#### PiKVM 参数配置

以下配置分别对应前面指定的 Pi4 HDMI-CSI 镜像和 Pi5 HDMI-USB 镜像。已有配置请合并相应字段，不要重复添加同名 YAML 键。

##### Raspberry Pi 4

编辑 `/etc/kvmd/janus/janus.plugin.ustreamer.jcfg`，将原有 `acap` 块替换为：

```text
acap: {
    device = "plughw:RK628HDMI,0"
    v4l2 = "/dev/kvmd-video"
}
```

##### Raspberry Pi 5

驱动安装步骤中的 udev 规则生效后，使用以下设备别名：

| 配置项 | 设备名称 |
| --- | --- |
| YAML：`--device` | `/dev/rk628-video` |
| YAML：`--media-device` | `/dev/rk628-media` |
| YAML：`--media-entity-name` | `/dev/rk628-subdev` |
| JCFG：`acap.v4l2` | `/dev/rk628-subdev` |

检查三个别名均已建立，并确认拓扑中包含 RK628 和 `rp1-cfe-csi2_ch0`：

```bash
ls -l /dev/rk628-video /dev/rk628-media /dev/rk628-subdev
media-ctl -d /dev/rk628-media -p
```

编辑 `/etc/kvmd/override.yaml`：

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

Pi5 使用 CPU 分别编码 JPEG 和 H.264。

编辑 `/etc/kvmd/janus/janus.plugin.ustreamer.jcfg`，将原有 `acap` 块替换为：

```text
acap: {
    device = "plughw:RK628HDMI,0"
    v4l2 = "/dev/rk628-subdev"
}
```

#### WebRTC 缓冲区配置

设置发送缓冲区，减少 WebRTC 在视频数据突发发送时出现的丢帧和卡顿。Pi4 和 Pi5 使用相同配置。

创建配置文件：

```bash
mkdir -p /etc/sysctl.d
vim /etc/sysctl.d/99-rk628-pikvm.conf
```

写入：

```ini
net.core.wmem_default = 4194304
net.core.wmem_max = 4194304
```

应用配置，后续开机也会自动加载：

```bash
sysctl -p /etc/sysctl.d/99-rk628-pikvm.conf
```

#### 应用配置

JCFG 的其他块保持不变。两种平台均不设置固定 `sampling_rate`，由 RK628 自动检测并跟随 HDMI 音频采样率。

允许 Janus 访问 V4L2 设备，并检查 YAML 配置：

```bash
usermod -aG video kvmd-janus
kvmd -m >/dev/null
```

全部配置完成并检查通过后，启用并重启所需服务，最后切回只读模式：

```bash
systemctl enable kvmd-janus kvmd-media
systemctl restart kvmd kvmd-janus kvmd-media
sync
ro
```

## 验证

终端默认账号和密码均为 `root`，网页默认账号和密码均为 `admin`。

根据 [PiKVM UI](https://docs.pikvm.org/webui/)，确认 HDMI 画面正常；切换到 WebRTC 模式，确认声音正常。HDMI 输入分辨率或音频采样率变化后，画面和声音应自动恢复，无需重启服务。

PiKVM 各项功能的使用方法参考[官方使用文档](https://docs.pikvm.org/webui/)。
