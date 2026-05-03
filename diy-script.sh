#!/bin/bash

set -euo pipefail

#========================================
# 0. 基本信息
#========================================
echo "===== start diy-script.sh ====="

OPENWRT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
echo "OPENWRT_DIR: ${OPENWRT_DIR}"
pwd
ls

#========================================
# 1. 默认 LAN IP
#========================================
DEFAULT_LAN_IP="192.168.123.1"

if [ -f "package/base-files/files/bin/config_generate" ]; then
  echo "===== set default LAN IP to ${DEFAULT_LAN_IP} ====="
  sed -i "s/192\.168\.[0-9]*\.[0-9]*/${DEFAULT_LAN_IP}/g" package/base-files/files/bin/config_generate
else
  echo "WARNING: package/base-files/files/bin/config_generate not found"
fi

#========================================
# 2. 拉取额外插件源码
#========================================
echo "===== clone extra packages ====="

mkdir -p package/extra

clone_or_update() {
  local url="$1"
  local dest="$2"
  if [ -d "$dest/.git" ]; then
    echo "update $dest"
    git -C "$dest" pull --rebase || true
  else
    rm -rf "$dest"
    git clone --depth=1 "$url" "$dest"
  fi
}

clone_or_update https://github.com/sirpdboy/luci-app-ddns-go.git        package/extra/luci-app-ddns-go
clone_or_update https://github.com/sbwml/luci-app-mosdns.git            package/extra/luci-app-mosdns
clone_or_update https://github.com/ophub/luci-app-amlogic.git           package/extra/luci-app-amlogic
clone_or_update https://github.com/xiaorouji/openwrt-passwall.git       package/extra/openwrt-passwall
clone_or_update https://github.com/xiaorouji/openwrt-passwall2.git      package/extra/openwrt-passwall2
clone_or_update https://github.com/jerrykuku/luci-app-vssr.git          package/extra/luci-app-vssr
clone_or_update https://github.com/sbwml/openwrt_helloworld.git         package/extra/helloworld

#========================================
# 3. 生成 .config 并拉取依赖源码
#========================================
echo "===== make defconfig ====="
make defconfig

#========================================
# 4. 修复 linux-6.18 filogic 设备名兼容
#========================================
echo "===== patch filogic device name for kernel 6.18 ====="

IMAGE_MT798X="$(find target/linux/mediatek/image -name 'mt798x.mk' | head -n 1 || true)"
if [ -n "${IMAGE_MT798X:-}" ] && [ -f "$IMAGE_MT798X" ]; then
  if grep -qE 'append-kernel.*ubi_kernel|ubinize-kernel|has-tag-kernel' "$IMAGE_MT798X"; then
    echo "patch $IMAGE_MT798X"

    sed -i 's/append-kernel.*ubi_kernel/append-kernel | attach-kernel/g' "$IMAGE_MT798X"
    sed -i 's/ubinize-kernel/attach-kernel/g' "$IMAGE_MT798X"
    sed -i 's/has-tag-kernel/attach-kernel/g' "$IMAGE_MT798X"
    sed -i 's/has-tag-rootfs/attach-rootfs/g' "$IMAGE_MT798X"

    echo "filogic device-name patch applied"
  else
    echo "mt798x.mk looks already compatible, skip"
  fi
else
  echo "target/linux/mediatek/image/mt798x.mk not found, skip"
fi

#========================================
# 5. 修复 linux-6.18 eBPF / xdp-tools 兼容
#========================================
echo "===== patch xdp-tools / bpftool for kernel 6.18 ====="

XDP_TOOLS_H="$(find package -type f -path '*/xdp-tools/headers-src/xdp/xdp_helpers.h' | head -n 1 || true)"
BPFTOOL_H="$(find package -type f -path '*/bpftool/src/libbpf/include/uapi/linux/bpf.h' | head -n 1 || true)"

XDP_PATCHED="no"

if [ -n "${XDP_TOOLS_H:-}" ] && [ -f "$XDP_TOOLS_H" ]; then
  if grep -q 'bpf_redirect neigh' "$XDP_TOOLS_H"; then
    echo "patch $XDP_TOOLS_H"

    python3 - "$XDP_TOOLS_H" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

old_pattern = r"dst_neigh\s*=\s*bpf_redirect_neigh\([^)]*\)\s*;\s*\n\s*if\s*\(\s*dst_neigh\s*\)\s*\{[^}]*\}"
new_block = "dst_neigh = bpf_redirect_map(&xdp_redirect_map, ctx->rx_queue_index, 0);\nif (dst_neigh) {\n    bpf_printk(\"xdp_redirect: error redirecting to ifindex %d\", ctx->rx_queue_index);\n}"

s, n = re.subn(old_pattern, new_block, s, count=1, flags=re.S)
if n == 0:
    print("target xdp_helpers.h block not found", file=sys.stderr)
    sys.exit(1)

p.write_text(s)
print("xdp_helpers.h patched successfully")
PY

    XDP_PATCHED="yes"
    echo "verify xdp_helpers.h:"
    grep -n "bpf_redirect_map\|bpf_redirect neigh" "$XDP_TOOLS_H" || true
  else
    echo "xdp_helpers.h already looks compatible, skip"
  fi
else
  echo "xdp_helpers.h not found, skip"
fi

if [ -n "${BPFTOOL_H:-}" ] && [ -f "$BPFTOOL_H" ]; then
  if grep -q 'BPF_F_NEIGH' "$BPFTOOL_H"; then
    echo "patch $BPFTOOL_H"

    python3 - "$BPFTOOL_H" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

old_pattern = r"#\s*define\s+BPF_F_NEIGH\s+[\s\S]*?#endif"
new_block = """#define BPF_F_NEIGH 0x10
#define BPF_F_REDIRECT 0x20
#define BPF_F_BROADCAST 0x40
#define BPF_F_EXCLUDE_INGRESS 0x80
#endif"""

s, n = re.subn(old_pattern, new_block, s, count=1, flags=re.S)
if n == 0:
    print("target bpftool bpf.h block not found", file=sys.stderr)
    sys.exit(1)

p.write_text(s)
print("bpftool bpf.h patched successfully")
PY

    XDP_PATCHED="yes"
    echo "verify bpftool bpf.h:"
    grep -n "BPF_F_NEIGH\|BPF_F_REDIRECT" "$BPFTOOL_H" || true
  else
    echo "bpftool bpf.h already looks compatible, skip"
  fi
else
  echo "bpftool bpf.h not found, skip"
fi

if [ "$XDP_PATCHED" = "no" ]; then
  echo "WARNING: xdp-tools / bpftool sources were not found or not patched"
fi

#========================================
# 6. 修复 rtl8261d 在 linux-6.18 下兼容
#========================================
echo "===== patch rtl8261d for kernel 6.18 ====="

RTL8261D_C="$(find package feeds -type f -path '*/rtl8261d/src/phy_rtl8261d.c' | head -n 1 || true)"

if [ -n "${RTL8261D_C:-}" ] && [ -f "$RTL8261D_C" ]; then
  if grep -q "struct mdio_device \*mdiodev = to_mdio_device" "$RTL8261D_C"; then
    echo "patch $RTL8261D_C"

    python3 - "$RTL8261D_C" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

old = "struct mdio_device *mdiodev = to_mdio_device(dev);\n\tphydev->mdio.dev = mdiodev->dev;"
new = "phydev->mdio.dev = dev;"

if old not in s:
    print("target block not found", file=sys.stderr)
    sys.exit(1)

s = s.replace(old, new, 1)
p.write_text(s)
print("rtl8261d patched successfully")
PY

    echo "verify rtl8261d:"
    grep -n "to_mdio_device\|phydev->mdio.dev = dev;" "$RTL8261D_C" || true
  else
    echo "rtl8261d already looks compatible, skip"
  fi
else
  echo "rtl8261d source not found, skip"
fi

#========================================
# 7. 修复 rtl837x-gsw 在 linux-6.18 下 SFP 兼容
#========================================
echo "===== patch rtl837x-gsw sfp for kernel 6.18 ====="

RTL837X_MDIO_C="$(find package feeds -type f -path '*/rtl837x-gsw*/src/rtl837x_mdio.c' | head -n 1 || true)"

if [ -n "${RTL837X_MDIO_C:-}" ] && [ -f "$RTL837X_MDIO_C" ]; then
  echo "Found rtl837x_mdio.c: $RTL837X_MDIO_C"

  python3 - "$RTL837X_MDIO_C" <<'PY'
from pathlib import Path
import re, sys

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

pattern = re.compile(r"static\s+int\s+rtl837x_sfp_module_insert\b[^{]*\{.*?\}\s*\n?", re.S)

if not pattern.search(s):
    print("rtl837x_sfp_module_insert not found", file=sys.stderr)
    sys.exit(1)

s = pattern.sub(new_block, s)
p.write_text(s)
print("rtl837x_sfp_module_insert patched successfully")
PY

  echo "verify rtl837x_mdio.c:"
  grep -n "rtl837x_sfp_module_insert\|sfp_parse_support" "$RTL837X_MDIO_C" || true
else
  echo "rtl837x_mdio.c not found, skip patch"
fi

#========================================
# 8. 结束
#========================================
echo "===== finish diy-script.sh ====="
