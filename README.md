# Alibaba Cloud Client for Linux

将阿里云官方 macOS 客户端转换为 Linux x86_64 应用，并生成 Arch/Manjaro、
Debian/Ubuntu 安装包与 AppImage。构建脚本默认从阿里云官方下载地址获取 DMG；
也可以显式指定本地 DMG。

当前固定支持：

- Alibaba Cloud Client 2.3.3
- Electron 19.1.9
- Linux x86_64
- Arch/Manjaro `.pkg.tar.zst`、Debian/Ubuntu `.deb` 与 AppImage

## 构建依赖

需要 `bash`、`make`、`7z`、`curl`、`unzip`、`tar`、`xz`、`ar`、`python3`、
`gcc/g++`、`file`、ImageMagick；Arch 包还需要 `makepkg`。构建脚本使用固定的
Node.js 22.22.2，并从 Electron 官方发布页下载和校验 Electron 19.1.9。

在 Arch/Manjaro 上可安装常用构建依赖：

```bash
sudo pacman -S --needed base-devel p7zip curl unzip xz python imagemagick
```

## 使用

不带参数时会从官方默认地址下载并缓存 DMG：

```bash
make build-app
make run
make pacman
make deb
APPIMAGETOOL=/path/to/appimagetool make appimage
```

也可以通过 `DMG=/path/to/file.dmg` 使用本地文件；设置 `REFRESH_DMG=1` 会刷新
缓存。默认下载地址可通过 `DMG_URL` 覆盖。

运行 `make package` 会同时构建三种格式。输出位于 `dist/`：

- `alibaba-cloud-client-2.3.3-1-x86_64.pkg.tar.zst`
- `alibaba-cloud-client_2.3.3-1_amd64.deb`
- `Alibaba_Cloud_Client-2.3.3-x86_64.AppImage`

推送形如 `v2.3.3-1` 的标签时，[GitHub Actions](.github/workflows/release.yml)
会在 Ubuntu runner 上构建 `.deb` 和 AppImage，并上传到对应 GitHub Release。
Arch/Manjaro 包继续使用 `make pacman` 在 Arch 系环境中构建。

安装 pacman 包：

```bash
sudo pacman -U dist/alibaba-cloud-client-2.3.3-1-x86_64.pkg.tar.zst
```

AUR 用户也可以安装二进制包：

```bash
yay -S alibaba-cloud-client-bin
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
