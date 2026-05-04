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

# 修复 rtl8261d 在 Linux 6.18 下 set_loopback 函数签名不匹配问题
echo "===== patch rtl8261d for kernel 6.18 ====="
find package feeds -path '*/rtl8261d/patches/100-kernel-6.18-set-loopback-signature.patch' -delete 2>/dev/null || true
RTL8261D_MAKEFILE="$(find package feeds -maxdepth 5 -type f -path '*/rtl8261d/Makefile' 2>/dev/null | head -n 1 || true)"
if [ -n "${RTL8261D_MAKEFILE:-}" ] && [ -f "$RTL8261D_MAKEFILE" ]; then
  echo "Found rtl8261d Makefile: $RTL8261D_MAKEFILE"
  python3 - "$RTL8261D_MAKEFILE" <<'PY'
from pathlib import Path
import sys
mf = Path(sys.argv[1])
text = mf.read_text()
begin = "define Build/Prepare"
end = "endef"
if begin in text:
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i].startswith(begin):
            block = []
            j = i
            while j < len(lines):
                block.append(lines[j])
                if lines[j].strip() == end:
                    break
                j += 1
            joined = "\n".join(block)
            if "rtl8261x_set_loopback" in joined and "$(PKG_BUILD_DIR)/src/rtl8261d_main.c" in joined:
                i = j + 1
                continue
        out.append(lines[i])
        i += 1
    text = "\n".join(out) + "\n"
marker = "define Build/Compile"
block = r'''
define Build/Prepare
	$(call Build/Prepare/Default)
	python3 - "$(PKG_BUILD_DIR)/src/rtl8261d_main.c" <<'EOF'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = """int rtl8261x_set_loopback(struct phy_device *phydev, bool enable)
{
\treturn Nic_Rtl8261X_loopback_set(phydev, enable);
}
"""
new = """int rtl8261x_set_loopback(struct phy_device *phydev, bool enable, int loopback_mode)
{
\t(void)loopback_mode;
\treturn Nic_Rtl8261X_loopback_set(phydev, enable);
}
"""
if new in s:
    print("rtl8261x_set_loopback already patched")
elif old in s:
    s = s.replace(old, new, 1)
    p.write_text(s)
    print("rtl8261x_set_loopback patched")
else:
    print("rtl8261x_set_loopback source block not found", file=sys.stderr)
    sys.exit(1)
EOF
	grep -n "rtl8261x_set_loopback" $(PKG_BUILD_DIR)/src/rtl8261d_main.c || true
endef
'''.lstrip("\n")
if marker not in text:
    print("Build/Compile marker not found in rtl8261d Makefile", file=sys.stderr)
    sys.exit(1)
if block not in text:
    text = text.replace(marker, block + "\n" + marker, 1)
mf.write_text(text)
PY
  echo "===== rtl8261d Makefile preview ====="
  sed -n '1,160p' "$RTL8261D_MAKEFILE" || true
else
  echo "rtl8261d Makefile not found, skip rtl8261d fix"
fi

# 修复 rtl837x 在 Linux 6.18 下 SFP API / probe 返回值兼容性问题
echo "===== patch rtl837x for kernel 6.18 ====="
find package feeds -path '*/rtl837x*/patches/100-kernel-6.18-sfp-compat.patch' -delete 2>/dev/null || true

RTL837X_MAKEFILE="$(find package feeds -maxdepth 6 -type f \( -path '*/rtl837x*/Makefile' -o -path '*/rtl837x-gsw/Makefile' \) 2>/dev/null | head -n 1 || true)"
if [ -n "${RTL837X_MAKEFILE:-}" ] && [ -f "$RTL837X_MAKEFILE" ]; then
  echo "Found rtl837x Makefile: $RTL837X_MAKEFILE"
  python3 - "$RTL837X_MAKEFILE" <<'PY'
from pathlib import Path
import sys

mf = Path(sys.argv[1])
text = mf.read_text()

begin = "define Build/Prepare"
end = "endef"

# 删除旧的同类注入块，避免重复
if begin in text:
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i].startswith(begin):
            block = []
            j = i
            while j < len(lines):
                block.append(lines[j])
                if lines[j].strip() == end:
                    break
                j += 1
            joined = "\n".join(block)
            if "rtl837x_sfp_module_insert" in joined and "rtl837x_mdio.c" in joined:
                i = j + 1
                continue
        out.append(lines[i])
        i += 1
    text = "\n".join(out) + "\n"

marker = "define Build/Compile"
block = r'''
define Build/Prepare
	$(call Build/Prepare/Default)
	python3 - "$(PKG_BUILD_DIR)" <<'EOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])

candidates = list(root.rglob("rtl837x_mdio.c"))
if not candidates:
    print("rtl837x_mdio.c not found under", root, file=sys.stderr)
    sys.exit(1)

p = candidates[0]
s = p.read_text()
orig = s

old_func = """static int rtl837x_sfp_module_insert(void *upstream, const struct sfp_eeprom_id *id)
{
\tstruct rtk_gsw *gsw = upstream;
\t__ETHTOOL_DECLARE_LINK_MODE_MASK(support) = { 0, };
\tDECLARE_PHY_INTERFACE_MASK(interfaces);
\tphy_interface_t iface;

\tsfp_parse_support(gsw->sfp_bus, id, support, interfaces);
\tiface = sfp_select_interface(gsw->sfp_bus, support);

\tdev_info(gsw->dev, "%s SFP module inserted\\n", phy_modes(iface));

\tswitch (iface) {
\tcase PHY_INTERFACE_MODE_10GBASER:
\t\tUSE_SERDESMODE(1, SERDES_10GR);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_2500BASEX:
\t\tUSE_SERDESMODE(1, SERDES_2500BASEX);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_1000BASEX:
\tcase PHY_INTERFACE_MODE_SGMII:
\t\tUSE_SERDESMODE(1, SERDES_1000BASEX);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_100BASEX:
\t\tUSE_SERDESMODE(1, SERDES_100FX);
\t\tbreak;
\tdefault:
\t\tdev_err(gsw->dev, "Incompatible SFP module inserted\\n");
\t\treturn -EINVAL;
\t}

\trtk_sdsMode_set(1, gsw->sds1mode);
\treturn 0;
}
"""

new_func = """static int rtl837x_sfp_module_insert(void *upstream, const struct sfp_eeprom_id *id)
{
\tstruct rtk_gsw *gsw = upstream;
\tphy_interface_t iface;

\tswitch (gsw->sds1mode) {
\tcase SERDES_10GR:
\t\tiface = PHY_INTERFACE_MODE_10GBASER;
\t\tbreak;
\tcase SERDES_2500BASEX:
\t\tiface = PHY_INTERFACE_MODE_2500BASEX;
\t\tbreak;
\tcase SERDES_1000BASEX:
\t\tiface = PHY_INTERFACE_MODE_1000BASEX;
\t\tbreak;
\tcase SERDES_100FX:
\t\tiface = PHY_INTERFACE_MODE_100BASEX;
\t\tbreak;
\tdefault:
\t\tdev_err(gsw->dev, "Unsupported preset SFP serdes mode: %d\\n", gsw->sds1mode);
\t\treturn -EINVAL;
\t}

\tdev_info(gsw->dev, "%s SFP module inserted, using preset serdes mode\\n", phy_modes(iface));

\tswitch (iface) {
\tcase PHY_INTERFACE_MODE_10GBASER:
\t\tUSE_SERDESMODE(1, SERDES_10GR);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_2500BASEX:
\t\tUSE_SERDESMODE(1, SERDES_2500BASEX);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_1000BASEX:
\tcase PHY_INTERFACE_MODE_SGMII:
\t\tUSE_SERDESMODE(1, SERDES_1000BASEX);
\t\tbreak;
\tcase PHY_INTERFACE_MODE_100BASEX:
\t\tUSE_SERDESMODE(1, SERDES_100FX);
\t\tbreak;
\tdefault:
\t\tdev_err(gsw->dev, "Incompatible SFP module inserted\\n");
\t\treturn -EINVAL;
\t}

\trtk_sdsMode_set(1, gsw->sds1mode);
\treturn 0;
}
"""

old_ret = """\tif (of_property_read_u32(np, "rtl837x,cpu-port", &gsw->cpu_port)) {
\t\tdev_err(gsw->dev, "failed to get cpu port\\n");
\t\tdevm_kfree(dev, gsw);
\t\treturn ret;
\t}
"""

new_ret = """\tif (of_property_read_u32(np, "rtl837x,cpu-port", &gsw->cpu_port)) {
\t\tdev_err(gsw->dev, "failed to get cpu port\\n");
\t\tdevm_kfree(dev, gsw);
\t\treturn -EINVAL;
\t}
"""

changed = False

if new_func in s:
    print("rtl837x_sfp_module_insert already patched")
elif old_func in s:
    s = s.replace(old_func, new_func, 1)
    print("rtl837x_sfp_module_insert patched")
    changed = True
else:
    print("rtl837x_sfp_module_insert source block not found", file=sys.stderr)
    sys.exit(1)

if new_ret in s:
    print("cpu-port return value already patched")
elif old_ret in s:
    s = s.replace(old_ret, new_ret, 1)
    print("cpu-port return value patched")
    changed = True
else:
    print("cpu-port return block not found", file=sys.stderr)
    sys.exit(1)

if changed and s != orig:
    p.write_text(s)

print("patched file:", p)
EOF
	find "$(PKG_BUILD_DIR)" -type f -name 'rtl837x_mdio.c' -exec grep -n "rtl837x_sfp_module_insert\|failed to get cpu port\|Unsupported preset SFP serdes mode" {} \; || true
endef
'''.lstrip("\n")

if marker not in text:
    print("Build/Compile marker not found in rtl837x Makefile", file=sys.stderr)
    sys.exit(1)

if block not in text:
    text = text.replace(marker, block + "\n" + marker, 1)

mf.write_text(text)
PY

  echo "===== rtl837x Makefile preview ====="
  sed -n '1,220p' "$RTL837X_MAKEFILE" || true
else
  echo "rtl837x Makefile not found, skip rtl837x fix"
fi

# 刷新配置
make defconfig
