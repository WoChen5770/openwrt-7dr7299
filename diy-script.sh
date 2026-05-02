#!/bin/bash
set -e

# 修改默认IP
sed -i 's/192.168.123.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 移除要替换的包
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/themes/luci-theme-netgear
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-serverchan

rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf package/feeds/luci/luci-app-argon-config
rm -rf feeds/packages/net/onionshare-cli
rm -rf package/feeds/packages/onionshare-cli
# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
  cd "$repodir"
  git sparse-checkout set "$@"
  mv -f "$@" ../package
  cd ..
  rm -rf "$repodir"
}

# MosDNS
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

# msd_lite
git clone --depth=1 https://github.com/ximiTech/luci-app-msd_lite package/luci-app-msd_lite
git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite

# SmartDNS
git clone --depth=1 -b lede https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns package/smartdns

# DDNS.to
git_sparse_clone main https://github.com/linkease/nas-packages-luci luci/luci-app-ddnsto
git_sparse_clone master https://github.com/linkease/nas-packages network/services/ddnsto

# iStore
git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
git_sparse_clone main https://github.com/linkease/istore luci

# 修改本地时间格式
find package feeds -type f -path '*/autocore/files/*/index.htm' 2>/dev/null \
  | xargs -r sed -i 's/os.date()/os.date("%a %Y-%m-%d %H:%M:%S")/g'

# 修改版本为编译日期
date_version=$(date +"%y.%m.%d")
if [ -n "$DEFAULT_SETTINGS_FILE" ] && [ -f "$DEFAULT_SETTINGS_FILE" ]; then
  orig_version=$(grep 'DISTRIB_REVISION=' "$DEFAULT_SETTINGS_FILE" | awk -F "'" '{print $2}' || true)
  if [ -n "$orig_version" ]; then
    sed -i "s/${orig_version}/R${date_version} by Haiibo/g" "$DEFAULT_SETTINGS_FILE"
  else
    echo "DISTRIB_REVISION not found, skip version patch"
  fi
fi

# 修复 armv8 设备 xfsprogs 报错
sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile

# 修改 Makefile
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's#\.\./\.\./luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's#\.\./\.\./lang/golang/golang-package.mk#$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's#PKG_SOURCE_URL:=@GHREPO#PKG_SOURCE_URL:=https://github.com#g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's#PKG_SOURCE_URL:=@GHCODELOAD#PKG_SOURCE_URL:=https://codeload.github.com#g' {}

# 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 修补 filogic 6.18.21 内核配置，启用 BPF 相关选项
KCFG="target/linux/mediatek/filogic/config-6.18"
if [ -f "$KCFG" ]; then
  echo "Patching kernel config: $KCFG"
  for opt in CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_NET_SCH_BPF; do
    sed -i "/^${opt}=.*/d" "$KCFG"
    sed -i "/^# ${opt} is not set/d" "$KCFG"
  done
  cat >> "$KCFG" <<'EOF'
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_NET_SCH_BPF=y
EOF
  echo "===== kernel fragment check ====="
  grep -nE 'CONFIG_(BPF_SYSCALL|BPF_JIT|NET_SCH_BPF)' "$KCFG" || true
else
  echo "Kernel config not found: $KCFG"
fi

# 修复 rtl8261d 驱动在 Linux 6.18 下 set_loopback 接口签名不兼容
RTL8261D_PKG_DIR="$(find package feeds -maxdepth 4 -type d -path '*/rtl8261d' 2>/dev/null | head -n 1)"
if [ -n "$RTL8261D_PKG_DIR" ] && [ -d "$RTL8261D_PKG_DIR" ]; then
  echo "Found rtl8261d package dir: $RTL8261D_PKG_DIR"
  mkdir -p "$RTL8261D_PKG_DIR/patches"
  cat > "$RTL8261D_PKG_DIR/patches/100-kernel-6.18-set-loopback-signature.patch" <<'EOF'
--- a/src/rtl8261d_main.c
+++ b/src/rtl8261d_main.c
@@
-int rtl8261x_set_loopback(struct phy_device *phydev, bool enable)
+int rtl8261x_set_loopback(struct phy_device *phydev, bool enable, int loopback_mode)
 {
+    (void)loopback_mode;
     return Nic_Rtl8261X_loopback_set(phydev, enable);
 }
EOF
  echo "===== rtl8261d patch check ====="
  ls -l "$RTL8261D_PKG_DIR/patches" || true
  sed -n '1,120p' "$RTL8261D_PKG_DIR/patches/100-kernel-6.18-set-loopback-signature.patch" || true
else
  echo "rtl8261d package dir not found, skip patch"
fi
