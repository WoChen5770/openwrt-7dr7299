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

# 修复 rtl837x-gsw 在 Linux 6.18 下的 SFP 兼容问题
echo "===== patch rtl837x-gsw sfp for kernel 6.18 ====="

echo "===== debug search rtl837x ====="
find package feeds target -type f 2>/dev/null | grep -i 'rtl837x\|sfp\|mdio' || true

RTL837X_MDIO_C="$(find package feeds target -type f -name 'rtl837x_mdio.c' 2>/dev/null | head -n 1 || true)"

if [ -z "${RTL837X_MDIO_C:-}" ]; then
  RTL837X_MDIO_C="$(grep -Rsl 'rtl837x_sfp_module_insert' package feeds target 2>/dev/null | head -n 1 || true)"
fi

if [ -n "${RTL837X_MDIO_C:-}" ] && [ -f "$RTL837X_MDIO_C" ]; then
  echo "Found rtl837x source: $RTL837X_MDIO_C"

  python3 - "$RTL837X_MDIO_C" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text()

new_block = r'''static int rtl837x_sfp_module_insert(void *upstream, const struct sfp_eeprom_id *id)
{
	struct rtk_gsw *gsw = upstream;

	dev_info(gsw->dev, "SFP module inserted, use configured serdes mode: %d\n",
		 gsw->sds1mode);

	switch (gsw->sds1mode) {
	case SERDES_10GR:
		dev_info(gsw->dev, "Using 10g-kr/10gbase-r mode for SFP module\n");
		break;
	case SERDES_2500BASEX:
		dev_info(gsw->dev, "Using 2500base-x mode for SFP module\n");
		break;
	case SERDES_1000BASEX:
	case SERDES_SG:
		dev_info(gsw->dev, "Using 1000base-x/sgmii mode for SFP module\n");
		break;
	case SERDES_100FX:
		dev_info(gsw->dev, "Using 100base-fx mode for SFP module\n");
		break;
	default:
		dev_err(gsw->dev, "Unsupported configured sds1mode for SFP: %d\n",
			gsw->sds1mode);
		return -EINVAL;
	}

	rtk_sdsMode_set(1, gsw->sds1mode);
	return 0;
}
'''

pattern = re.compile(
    r'static\s+int\s+rtl837x_sfp_module_insert\s*\([^)]*\)\s*\{.*?\n\}',
    re.S
)

m = pattern.search(s)
if not m:
    print("rtl837x_sfp_module_insert not found", file=sys.stderr)
    sys.exit(1)

old_block = m.group(0)

if old_block.strip() == new_block.strip():
    print("rtl837x_sfp_module_insert already patched")
else:
    s = s[:m.start()] + new_block + s[m.end():]
    p.write_text(s)
    print("rtl837x_sfp_module_insert patched successfully")
PY

  echo "===== verify rtl837x patch ====="
  grep -n "rtl837x_sfp_module_insert" "$RTL837X_MDIO_C" || true
else
  echo "No rtl837x source found in current source tree, skip patch (not an error)"
fi

python3 - "$RTL837X_MDIO_C" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
s = p.read_text()
m = re.search(r'static\s+int\s+rtl837x_sfp_module_insert\s*\([^)]*\)\s*\{.*?\n\}', s, re.S)
if m:
    print(m.group(0))
else:
    print("function not found")
PY

# 刷新配置
make defconfig
