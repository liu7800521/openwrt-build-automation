#!/bin/bash
# ============================================================
# ImmortalWrt ImageBuilder 构建脚本（x86-64）
# 运行环境：immortalwrt/imagebuilder:x86-64-openwrt-<版本> 容器内
# 由 .github/workflows/*.yml 调用，挂载到 /home/build/immortalwrt/build.sh
# ============================================================
LOGFILE="/tmp/build-log.txt"
echo "开始构建: $(date)" >> "$LOGFILE"

# ---- 1. 合并第三方插件（shell/custom-packages.sh 取消注释即生效）----
if [ -f /home/build/immortalwrt/shell/custom-packages.sh ]; then
  # shellcheck disable=SC1091
  source /home/build/immortalwrt/shell/custom-packages.sh
fi
echo "第三方插件: [$CUSTOM_PACKAGES]" | tee -a "$LOGFILE"

# ---- 2. 生成 PPPoE 配置（供首次启动脚本 99-custom.sh 读取）----
mkdir -p /home/build/immortalwrt/files/etc/config
cat > /home/build/immortalwrt/files/etc/config/pppoe-settings <<EOF
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# ---- 3. 集成第三方 apk/run 插件（若开启了 custom-packages.sh）----
if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "同步第三方插件仓库（wukongdaily/apk）..." | tee -a "$LOGFILE"
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo 2>/dev/null || echo "⚠️ 克隆第三方仓库失败，跳过"
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/x86/* /home/build/immortalwrt/extra-packages/ 2>/dev/null || true
  if [ -f /home/build/immortalwrt/shell/prepare-packages.sh ]; then
    sh /home/build/immortalwrt/shell/prepare-packages.sh
  fi
fi

# ---- 4. 默认包集合（可自由增删）----
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# 合并第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ---- 5. Docker 可选集成 ----
if [ "$INCLUDE_DOCKER" = "yes" ]; then
  PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
  echo "✅ 集成 Docker" | tee -a "$LOGFILE"
fi

# ---- 6. 代理插件自动下载内核 ----
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
  echo "✅ 集成 OpenClash，下载 clash_meta 内核..." | tee -a "$LOGFILE"
  mkdir -p files/etc/openclash/core
  META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
  wget -qO- "$META_URL" | tar xOvz > files/etc/openclash/core/clash_meta 2>/dev/null
  chmod +x files/etc/openclash/core/clash_meta
  wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat 2>/dev/null
  wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat 2>/dev/null
  OPENCLASH_URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
    | grep "browser_download_url.*apk" | head -n1 | cut -d '"' -f 4)
  [ -n "$OPENCLASH_URL" ] && wget "$OPENCLASH_URL" -P /home/build/immortalwrt/packages/ 2>/dev/null
fi
if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
  echo "✅ 集成 SSR-Plus，下载 mihomo 内核..." | tee -a "$LOGFILE"
  mkdir -p files/usr/bin
  MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-amd64-compatible-v1.19.24.gz"
  wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo 2>/dev/null
  chmod +x files/usr/bin/mihomo
fi

# ---- 7. 执行打包 ----
echo "开始 make image (ROOTFS_PARTSIZE=$PROFILE) ..." | tee -a "$LOGFILE"
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE
if [ $? -ne 0 ]; then
  echo "❌ 构建失败！" | tee -a "$LOGFILE"
  exit 1
fi
echo "✅ 构建完成: $(date)" | tee -a "$LOGFILE"
ls -lah /home/build/immortalwrt/bin/targets/x86/64/
