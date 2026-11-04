# OpenWrt 编译自动化（ImmortalWrt ImageBuilder）

基于 [wukongdaily/ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) 机制定制的 **GitHub Actions 云端自动化**：Fork/推送本仓库后，在 Actions 页面填参数一键构建 ImmortalWrt 固件，自动发布到 Release，并可选封装成 ISO 安装器。

本质是 **云端 ImageBuilder 打包（非源码编译）**，使用官方 `immortalwrt/imagebuilder` Docker 镜像执行 `make image`。

---

## 一、项目结构

```
openwrt-build-automation/
├── .github/workflows/
│   ├── build-x86-64.yml   # 构建 x86-64 固件（*.img.gz）→ Release
│   └── build-iso.yml      # 构建 x86-64 ISO 安装器（两阶段）→ Release
├── x86-64/
│   └── build.sh           # ImageBuilder 构建脚本（默认包 + 第三方插件 + make image）
├── shell/
│   ├── custom-packages.sh     # 第三方插件开关（取消注释即集成）
│   └── prepare-packages.sh    # 解压 .run / 收集 .apk 到 packages
├── files/etc/uci-defaults/
│   └── 99-custom.sh           # 首次启动自适应（单网口DHCP / 多网口WAN+LAN / PPPoE / docker防火墙）
├── README.md
└── .gitignore
```

## 二、使用方法

### 1. 推送仓库到 GitHub
```bash
# 在你的 GitHub 新建空仓库 openwrt-build-automation，然后：
git init
git add .
git commit -m "init: openwrt build automation"
git branch -M main
git remote add origin https://github.com/<你的账号>/openwrt-build-automation.git
git push -u origin main
```

### 2. 触发构建
GitHub → 你的仓库 → **Actions** → 选择 `Build x86-64 ImmortalWrt (25.12.x)`（或 `Build x86-64 ISO Installer (25.12.x)`）→ **Run workflow** → 填参数 → 运行。

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
| `luci_version` | 25.12.0 / 25.12.1 / 25.12.2 | luci / 固件版本 |
| `profile` | 1G / 2G / 3G / 4G | 固件根文件系统大小，**推荐 1G~2G** |
| `custom_router_ip` | `192.168.x.1` | **仅多网口生效**；单网口/旁路由请勿修改 |
| `include_docker` | yes / no | 是否集成 Docker（luci-app-dockerman） |
| `enable_store` | true / false | 是否集成 Store 商店 |
| `enable_pppoe` | yes / no | 是否配置 PPPoE 拨号 |
| `pppoe_account` / `pppoe_password` | 文本 | 启用 PPPoE 时**必填**，为空会直接报错 |

## 四、定制固件内容

### 1. 增减插件（最常用）
编辑 `shell/custom-packages.sh`，**取消对应行注释**即可把第三方插件打进固件。文件内已内置冲突提示。

### 2. 调整默认包集合
编辑 `x86-64/build.sh` 第 4 节的 `PACKAGES` 列表（增删 luci 插件名）。

### 3. 修改首次启动行为
编辑 `files/etc/uci-defaults/99-custom.sh`（网口策略、防火墙、PPPoE、Docker zone 等）。

### 4. 进阶：自定义 ImageBuilder 配置
默认使用 ImageBuilder 镜像内置的 x86-64 默认 `.config`，可直接构建。如需深度定制（内核选项、apk 包管理器开关、附加镜像格式如 qcow2/vmdk），可参考上游 `x86-64/imm25.config` 生成一份 `.config`，并在工作流 `docker run` 中加入挂载：
```yaml
-v "${{ github.workspace }}/x86-64/imm.config:/home/build/immortalwrt/.config" \
```

---

## 五、固件默认属性（重要）

- **单网口设备**：默认 **DHCP 自动获取 IP**（类 NAS 逻辑）。旁路由场景：先在上级路由器查到分配给它的 IP，再进后台配置旁路 IP。
- **多网口设备**：`eth0`=WAN（DHCP，勾选拨号则 PPPoE），其余网口并入 `br-lan`，LAN 静态 IP（默认 `192.168.100.1`，可用 `custom_router_ip` 修改）。
- **防火墙**：为易用性默认 WAN 入站 `ACCEPT`，**首次调试完毕后请手动改为拒绝**（网络 → 防火墙 → wan 入站 → 拒绝 → 保存并应用）。
- **插件追新**：可前往 [RunFilesBuilder](https://github.com/wukongdaily/RunFilesBuilder) 下载 run 文件，用 `sh xx.run` 覆盖安装。

## 六、关联项目

| 项目 | 用途 |
|---|---|
| [ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) | 上游参考（多目标平台工作流） |
| [RunFilesBuilder](https://github.com/wukongdaily/RunFilesBuilder) | 一键生成 run 插件 |
| [DockerTarBuilder](https://github.com/wukongdaily/DockerTarBuilder) | 一键生成 Docker 离线镜像 |
| [img-installer](https://github.com/wukongdaily/img-installer) | OpenWrt/Armbian IMG 安装器 ISO |

> 本项目为个人使用而整理的自动化，与 ImmortalWrt 官方无关；定制产生的 bug 不代表官方固件问题。
