<img width="768" src="https://github.com/openwrt/openwrt/blob/main/include/logo.png"/>

## 特别提示 [![](https://img.shields.io/badge/-个人免责声明-FFFFFF.svg)](#特别提示-)

- **本人不对任何人因使用本固件所遭受的任何理论或实际的损失承担责任！**
- **本固件禁止用于任何商业用途，请务必严格遵守国家互联网使用相关法律规定！**

## 项目说明 [![](https://img.shields.io/badge/-项目基本介绍-FFFFFF.svg)](#项目说明-)

- 固件机型：`TP-Link TL-7DR7299 v1`
- 固件默认管理地址：`192.168.123.1`
- 默认用户：`root`
- 默认密码：`password`
- 编译源码：[WoChen5770/imoutowrt](https://github.com/WoChen5770/imoutowrt)
- 源码分支：`master-mediatek-7dr7299`
- 在线编译工作流：[`.github/workflows/tl-7dr7299-v1.yml`](.github/workflows/tl-7dr7299-v1.yml)
- 专用配置文件：[configs/MTK-7DR7299.txt](configs/MTK-7DR7299.txt)（机型基础配置） + [configs/CUSTOMIZE.txt](configs/CUSTOMIZE.txt)（功能定制配置）

## 固件下载 [![](https://img.shields.io/badge/-编译状态及下载链接-FFFFFF.svg)](#固件下载-)

点击下方链接即可跳转到当前仓库的固件发布页：

- [Releases](../../releases)

| 机型 | 工作流 | 配置文件 | 发布标签 |
| :--: | :--: | :--: | :--: |
| TP-Link TL-7DR7299 v1 | [TL-7DR7299-v1](.github/workflows/tl-7dr7299-v1.yml) | [MTK-7DR7299.txt](configs/MTK-7DR7299.txt) + [CUSTOMIZE.txt](configs/CUSTOMIZE.txt) | `TL-7DR7299-v1` |

## 使用说明 [![](https://img.shields.io/badge/-项目基本编译教程-FFFFFF.svg)](#使用说明-)

1. 登录 GitHub 账号并 Fork 此项目到你自己的仓库。
2. 如需调整基础硬件/平台配置，请修改 [configs/MTK-7DR7299.txt](configs/MTK-7DR7299.txt)；如需增减插件和功能组件，请修改 [configs/CUSTOMIZE.txt](configs/CUSTOMIZE.txt)。
3. 如需调整默认设置或附加软件包，请修改 [diy-script.sh](scripts/diy-script.sh)。
4. 进入 `Actions` 页面，手动运行 [`TL-7DR7299-v1`](.github/workflows/tl-7dr7299-v1.yml) 工作流即可开始在线编译。
5. 编译完成后，在仓库主页的 [Releases](../../releases) 页面下载固件。

## 维护说明 [![](https://img.shields.io/badge/-仓库维护说明-FFFFFF.svg)](#维护说明-)

- 本仓库已收敛为单机型在线编译仓库，仅面向 `TP-Link TL-7DR7299 v1`。
- GitHub Actions 仅保留一个工作流：[`tl-7dr7299-v1.yml`](.github/workflows/tl-7dr7299-v1.yml)。
- 若上游源码目标定义发生变化，请优先同步并修正 [configs/MTK-7DR7299.txt](configs/MTK-7DR7299.txt) 中的目标项。
- 编译时工作流会将 `MTK-7DR7299.txt`（基础配置）与 `CUSTOMIZE.txt`（功能定制）按顺序合并后执行 `make defconfig`。

<a href="#readme">
<img src="https://img.shields.io/badge/-返回顶部-FFFFFF.svg" title="返回顶部" align="right"/>
</a>
