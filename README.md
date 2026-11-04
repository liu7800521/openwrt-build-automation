# OpenWrt 编译自动化（OpenWrt ImageBuilder）

基于 [wukongdaily/ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) 的云端 ImageBuilder 思路，改造为 **OpenWrt 官方（openwrt/imagebuilder）纯净版** 的 GitHub Actions 自动化：Fork/推送本仓库后，在 Actions 页面填参数一键构建 **OpenWrt 官方 x86-64 固件**，自动发布到 Release，并可选封装成 ISO 安装器。

本质是 **云端 ImageBuilder 打包（非源码编译）**，使用官方 `openwrt/imagebuilder` Docker 镜像执行 `make image`。

> 说明：本工程已切换到 OpenWrt 官方发行版，**不含 ImmortalWrt 私有插件**（diskman / argon 主题 / istore / filemanager / dockerman）与第三方插件框架（wukongdaily apk / OpenClash / SSR-Plus 等），包集合均为 OpenWrt 官方软件源内可用包。

---

## 一、项目结构

```
openwrt-build-automation/
├── .github/workflows/
│   ├── build-x86-64.yml   # 构建 x86-64 固件（*.img.gz）→ Release
│   └── build-iso.yml      # 构建 x86-64 ISO 安装器（两阶段）→ Release
├── x86-64/
│   └── build.sh           # ImageBuilder 构建脚本（默认包 + make image）
├── files/etc/uci-defaults/
│   └── 99-custom.sh           # 首次启动自适应（单网口DHCP / 多网口WAN+LAN / PPPoE / docker防火墙）
├── README.md
└── .gitignore
```

## 二、使用方法

### 1. 推送仓库到 GitHub
```bash
git init
git add .
git commit -m "init: openwrt build automation"
git branch -M main
git remote add origin https://github.com/<你的账号>/openwrt-build-automation.git
git push -u origin main
```

### 2. 触发构建
GitHub → 你的仓库 → **Actions** → 选择 `Build x86-64 OpenWrt (25.12.x)`（或 `Build x86-64 ISO Installer (25.12.x)`）→ **Run workflow** → 填参数 → 运行。

### 3. 获取产物
构建完成后到仓库 **Releases** 下载：
- 固件工作流：`*.squashfs-combined-efi.img.gz`
- ISO 工作流：`custom-installer-x86_64.iso`

### 4. 安装
- **虚拟机（PVE/ESXi 等）**：用 ISO 工作流产物，挂载 ISO 引导 → 跑码结束输入 `ddd` → 选择目标虚拟磁盘写入。
- **物理机**：ISO 拷入 Ventoy（Windows）/ balenaEtcher（macOS）U 盘 → 启动选 U 盘 → 输入 `ddd`。
- **已有 OpenWrt**：用 `sysupgrade` 直刷 `.img.gz`。

---

## 三、构建参数说明

| 参数 | 取值 | 说明 |
|---|---|---|
| `openwrt_version` | 25.12.0 ~ 25.12.6 | OpenWrt 固件版本，默认最新 **25.12.6** |
| `profile` | 1G / 2G / 3G / 4G | 固件根文件系统大小，**推荐 1G~2G** |
| `custom_router_ip` | `192.168.x.1` | **仅多网口生效**；单网口/旁路由请勿修改 |
| `include_docker` | yes / no | 是否集成 Docker（官方 `luci-app-docker`） |
| `enable_pppoe` | yes / no | 是否配置 PPPoE 拨号 |
| `pppoe_account` / `pppoe_password` | 文本 | 启用 PPPoE 时**必填**，为空会直接报错 |

## 四、定制固件内容

### 1. 调整默认包集合
编辑 `x86-64/build.sh` 第 2 节的 `PACKAGES` 列表（增删 OpenWrt 官方 luci 包名，如 `luci-i18n-xxx-zh-cn`）。
> 包名需存在于 OpenWrt 官方源：可到 https://downloads.openwrt.org/releases/25.12.6/packages/x86_64/luci/ 查询。

### 2. 修改首次启动行为
编辑 `files/etc/uci-defaults/99-custom.sh`（网口策略、防火墙、PPPoE、Docker zone 等）。

### 3. 进阶：自定义 ImageBuilder 配置
默认使用 ImageBuilder 镜像内置的 x86-64 默认 `.config`，可直接构建。如需深度定制（内核选项、附加镜像格式如 qcow2/vmdk），可生成一份 `.config` 并在工作流 `docker run` 中加入挂载：
```yaml
-v "${{ github.workspace }}/x86-64/imm.config:/builder/.config" \
```

---

## 五、固件默认属性（重要）

- **单网口设备**：默认 **DHCP 自动获取 IP**（类 NAS 逻辑）。旁路由场景：先在上级路由器查到分配给它的 IP，再进后台配置旁路 IP。
- **多网口设备**：`eth0`=WAN（DHCP，勾选拨号则 PPPoE），其余网口并入 `br-lan`，LAN 静态 IP（默认 `192.168.100.1`，可用 `custom_router_ip` 修改）。
- **防火墙**：为易用性默认 WAN 入站 `ACCEPT`，**首次调试完毕后请手动改为拒绝**（网络 → 防火墙 → wan 入站 → 拒绝 → 保存并应用）。

## 六、技术要点（相对上游的差异）

| 项 | 上游（ImmortalWrt） | 本工程（OpenWrt 官方） |
|---|---|---|
| Docker 镜像 | `immortalwrt/imagebuilder:x86-64-openwrt-*` | `openwrt/imagebuilder:x86-64-25.12.x` |
| 容器工作目录 | `/home/build/immortalwrt` | `/builder` |
| 版本 | ImmortalWrt 25.12.x | OpenWrt 25.12.x（最新 25.12.6） |
| 初始化 | 镜像内已含 ImageBuilder | 24.10+ 镜像需先 `setup.sh` 下载 |
| 包集合 | ImmortalWrt 私有包 + wukongdaily 第三方 | 仅 OpenWrt 官方源包 |
| Docker | `luci-app-dockerman` | 官方 `luci-app-docker` |

## 七、关联项目

| 项目 | 用途 |
|---|---|
| [openwrt/docker](https://github.com/openwrt/docker) | OpenWrt 官方 ImageBuilder/SDK/rootfs 容器 |
| [img-installer](https://github.com/wukongdaily/img-installer) | OpenWrt/Armbian IMG 安装器 ISO |
| [ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) | 上游参考（多目标平台工作流） |

> 本项目为个人使用而整理的自动化；若需 ImmortalWrt 私有插件（diskman / istore / argon 等）或第三方插件，请改用上游 ImmortalWrt-ImageBuilder 工程。
