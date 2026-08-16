# Alibaba Cloud Client for Linux

将阿里云官方 macOS 客户端转换为 Linux x86_64 应用，并生成 Arch/Manjaro
安装包与 AppImage。项目不包含、下载或重新发布阿里云客户端本身；构建时必须由用户
提供官方 DMG。

当前固定支持：

- Alibaba Cloud Client 2.3.3
- Electron 19.1.9
- Linux x86_64
- Arch/Manjaro `.pkg.tar.zst` 与 AppImage

## 构建依赖

需要 `bash`、`make`、`7z`、`curl`、`unzip`、`tar`、`xz`、`python3`、
`gcc/g++`、`file`、ImageMagick、`makepkg`。构建脚本使用固定的
Node.js 22.22.2，并从 Electron 官方发布页下载和校验 Electron 19.1.9。

在 Arch/Manjaro 上可安装常用构建依赖：

```bash
sudo pacman -S --needed base-devel p7zip curl unzip xz python imagemagick
```

## 使用

由于官方下载文件名可能带 URL 查询参数，建议显式传入完整路径：

```bash
make build-app DMG='/path/to/alibaba-cloud-client-latest.dmg?...'
make run
make pacman
APPIMAGETOOL=/path/to/appimagetool make appimage
```

也可以运行 `make package` 同时构建两种格式。输出位于 `dist/`：

- `alibaba-cloud-client-2.3.3-1-x86_64.pkg.tar.zst`
- `Alibaba_Cloud_Client-2.3.3-x86_64.AppImage`

安装 pacman 包：

```bash
sudo pacman -U dist/alibaba-cloud-client-2.3.3-1-x86_64.pkg.tar.zst
```

如果 Electron 在 Wayland 会话中显示异常，可以显式使用 XWayland：

```bash
./alibaba-cloud-client-app/start.sh --ozone-platform=x11
```

启动器不会默认关闭 Electron 沙箱。只有在明确理解风险时，才应自行传入
`--no-sandbox`。

## Linux 差异

- `better-sqlite3` 与 `node-pty` 会针对 Linux/Electron 19 重新编译。
- 本地终端会扫描 Linux 上的 `bash`、`fish`、`zsh`、`node` 和 `python`。
- Linux 新构建的终端默认使用等宽字体 `Consolas`，避免 macOS 默认字体
  `Monaco` 缺失后回退到比例字体而产生异常字间距。
- 剪贴板历史和复制保留，但不会记录来源窗口，也不会模拟按键自动粘贴。
- RDP、活动窗口识别和应用内自动安装更新在首版禁用。
- “检查更新”会提示使用新的官方 DMG 重新构建。
- 配置和凭据继续使用官方路径，包括 `~/.aliyun`。

## 验证

```bash
make test
./scripts/verify-app.sh
make smoke
```

构建过程会检查上游版本、补丁命中次数、ELF 架构、动态库依赖及残留的 Mach-O
原生模块。`make smoke` 使用 AppImage portable 目录限时启动应用，检查窗口初始化、
原生模块加载错误及未处理 Promise。若上游 DMG 结构变化，构建会直接失败，避免产生
不完整安装包。
