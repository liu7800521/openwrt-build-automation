#!/bin/sh
# ============================================================
# 99-custom.sh：ImmortalWrt 首次启动自适应脚本
# 位于固件内 /etc/uci-defaults/99-custom.sh，刷机后首次启动自动执行一次
# 逻辑：自动探测网口数量 → 单网口走 DHCP / 多网口走 WAN+LAN 静态IP（可 PPPoE）
# ============================================================
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> "$LOGFILE"

# 默认防火墙：方便首次访问 WebUI（调试完建议在 Web 界面将 wan 入站改为拒绝）
uci set firewall.@zone[1].input='ACCEPT'

# 域名映射：解决安卓原生 TV 无法联网
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 读取 PPPoE 配置（由 build.sh 动态生成）
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SETTINGS_FILE"
fi

# ---- 1. 探测物理网口 ----
ifnames=""
for iface in /sys/class/net/*; do
  iface_name=$(basename "$iface")
  if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
    ifnames="$ifnames $iface_name"
  fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')
count=$(echo "$ifnames" | wc -w)
echo "Detected interfaces: [$ifnames] count=$count" >> "$LOGFILE"

board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")

wan_ifname=""
lan_ifnames=""
# 特殊机型网口顺序修正
case "$board_name" in
  "radxa,e20c"|"friendlyarm,nanopi-r5c")
    wan_ifname="eth1"; lan_ifnames="eth0" ;;
  *)
    wan_ifname=$(echo "$ifnames" | awk '{print $1}')
    lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-) ;;
esac

# ---- 2. 配置网络 ----
if [ "$count" -eq 1 ]; then
  # 单网口：DHCP 自动获取 IP（旁路由/单臂场景）
  uci set network.lan.proto='dhcp'
  uci delete network.lan.ipaddr
  uci delete network.lan.netmask
  uci delete network.lan.gateway
  uci delete network.lan.dns
  uci commit network
elif [ "$count" -gt 1 ]; then
  # 多网口：第一个网口=WAN，其余=LAN(br-lan)，LAN 静态 IP
  uci set network.wan=interface
  uci set network.wan.device="$wan_ifname"
  uci set network.wan.proto='dhcp'
  uci set network.wan6=interface
  uci set network.wan6.device="$wan_ifname"
  uci set network.wan6.proto='dhcpv6'

  # 更新 br-lan 端口
  section=$(uci show network | awk -F '[.=]' '/\.@?device\[[0-9]+\]\.name=.br-lan.$/ {print $2; exit}')
  if [ -n "$section" ]; then
    uci -q delete "network.$section.ports"
    for port in $lan_ifnames; do
      uci add_list "network.$section.ports"="$port"
    done
  fi

  # LAN 静态 IP（优先用户设置，否则默认 192.168.100.1）
  uci set network.lan.proto='static'
  uci set network.lan.netmask='255.255.255.0'
  IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
  if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    uci set network.lan.ipaddr="$CUSTOM_IP"
    echo "custom router ip: $CUSTOM_IP" >> "$LOGFILE"
  else
    uci set network.lan.ipaddr='192.168.100.1'
  fi

  # PPPoE 拨号（可选）
  if [ "$enable_pppoe" = "yes" ]; then
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
  fi
  uci commit network
fi

# ---- 3. 所有网口开放网页终端与 SSH ----
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''
uci commit

# ---- 4. 固件构建者信息 ----
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='Packaged by openwrt-automation'/" /etc/openwrt_release

# ---- 5. 若集成 Docker，重建防火墙 zone（扩大子网，方便容器端口放行）----
if command -v dockerd >/dev/null 2>&1; then
  echo "检测到 Docker，配置防火墙规则..." >> "$LOGFILE"
  uci delete firewall.docker
  # 倒序删除所有指向 docker 的 forwarding
  for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
    src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
    dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
    if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
      uci delete firewall.@forwarding[$idx]
    fi
  done
  uci commit firewall
  cat <<EOF >>/etc/config/firewall
config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'
config forwarding
  option src 'docker'
  option dest 'lan'
config forwarding
  option src 'docker'
  option dest 'wan'
config forwarding
  option src 'lan'
  option dest 'docker'
EOF
fi

exit 0
