#!/bin/bash
# ============================================================
# OpenWrt ImageBuilder 构建脚本（x86-64）
# 运行环境：openwrt/imagebuilder:x86-64-<版本> 容器内，工作目录 /builder
# 由 .github/workflows/*.yml 调用，挂载到 /builder/build.sh
# ============================================================
LOGFILE="/tmp/build-log.txt"
echo "开始构建: $(date)" >> "$LOGFILE"

cd /builder || exit 1

# ---- 0. 24.10+ 官方镜像不含实际二进制，先 setup 下载 ImageBuilder ----
if [ ! -d ./scripts ]; then
  echo "运行 setup.sh 下载 ImageBuilder（中科大镜像源）..." | tee -a "$LOGFILE"
  UPSTREAM_URL="https://mirrors.ustc.edu.cn/openwrt" bash ./setup.sh
fi

# ---- 1. 生成 PPPoE 配置（供首次启动脚本 99-custom.sh 读取）----
mkdir -p /builder/files/etc/config
cat > /builder/files/etc/config/pppoe-settings <<EOF
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# ---- 2. 默认包集合（OpenWrt 官方源，可自由增删）----
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci"
PACKAGES="$PACKAGES luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"

# ---- 3. Docker 可选集成（官方源：dockerd + luci-app-dockerman）----
if [ "$INCLUDE_DOCKER" = "yes" ]; then
  PACKAGES="$PACKAGES dockerd docker luci-app-dockerman luci-i18n-dockerman-zh-cn"
  echo "✅ 集成 Docker" | tee -a "$LOGFILE"
fi

# ---- 4. 执行打包（软件源切到中科大镜像）----
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/releases/${OPENWRT_VERSION}"
echo "开始 make image (ROOTFS_PARTSIZE=$PROFILE, 软件源=$VERSION_REPO) ..." | tee -a "$LOGFILE"
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/builder/files" ROOTFS_PARTSIZE=$PROFILE \
  VERSION_REPO="$VERSION_REPO" VERSION_FIRMWARE_URL="https://mirrors.ustc.edu.cn/openwrt/"
if [ $? -ne 0 ]; then
  echo "❌ 构建失败！" | tee -a "$LOGFILE"
  exit 1
fi
echo "✅ 构建完成: $(date)" | tee -a "$LOGFILE"
ls -lah /builder/bin/targets/x86/64/
