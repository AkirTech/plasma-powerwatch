#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 AkirTech
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Power Watch 安装 / 卸载脚本

set -euo pipefail

PLUGIN_ID="io.github.akirtech.powerwatch"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PKG_DIR="$HERE/package"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/plasma/plasmoids/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"

CREATE_LINKS=1
DO_UNINSTALL=0

usage() {
    cat <<'EOF'
Power Watch — KDE Plasma 6 功耗监测小部件

用法：
  ./install.sh              安装 / 升级（当前用户）
  ./install.sh --uninstall  卸载
  ./install.sh --no-bin     不创建 ~/.local/bin 下的命令软链接
  ./install.sh --help       显示本帮助
EOF
}

for arg in "$@"; do
    case "$arg" in
        --uninstall) DO_UNINSTALL=1 ;;
        --no-bin)    CREATE_LINKS=0 ;;
        -h|--help)   usage; exit 0 ;;
        *) printf '未知参数：%s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

need_kpackagetool() {
    command -v kpackagetool6 >/dev/null 2>&1 && return 0
    cat >&2 <<'EOF'
错误：找不到 kpackagetool6（Plasma 6 的 KPackage 管理工具）。

Debian / Ubuntu / Kali： sudo apt install kpackagetool6
Fedora：                sudo dnf install kf6-kpackage
Arch：                  sudo pacman -S kpackage
EOF
    exit 1
}

uninstall() {
    need_kpackagetool

    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"; then
        kpackagetool6 -t Plasma/Applet --remove "$PLUGIN_ID"
        echo "已移除小部件 $PLUGIN_ID"
    else
        echo "未安装 $PLUGIN_ID，跳过"
    fi

    # 只删指向本插件的软链接，避免误删用户自己的文件
    for name in powerwatch-collect powerwatch-enable-rapl; do
        link="$BIN_DIR/$name"
        case "$(readlink -f "$link" 2>/dev/null || true)" in
            */plasmoids/"$PLUGIN_ID"/*)
                rm -f "$link"
                echo "已删除软链接 $link"
                ;;
        esac
    done

    echo
    echo "注意：桌面上已经放好的部件实例不会自动消失，请右键它 → 移除部件。"
    echo "      如果之前放行过 Intel RAPL，可用该脚本的 --undo 撤销（需要 root）。"
}

install() {
    need_kpackagetool

    if [ ! -f "$PKG_DIR/metadata.json" ]; then
        echo "错误：$PKG_DIR 下找不到 metadata.json，仓库结构不完整。" >&2
        exit 1
    fi

    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"; then
        echo "检测到已安装，执行升级…"
        kpackagetool6 -t Plasma/Applet --upgrade "$PKG_DIR"
    else
        echo "正在安装…"
        kpackagetool6 -t Plasma/Applet --install "$PKG_DIR"
    fi

    # 采集脚本必须可执行，这里兜一层保险
    chmod +x "$INSTALL_DIR/contents/scripts/powerwatch-collect" \
             "$INSTALL_DIR/contents/scripts/powerwatch-enable-rapl" 2>/dev/null || true

    if [ "$CREATE_LINKS" = 1 ]; then
        mkdir -p "$BIN_DIR"
        for name in powerwatch-collect powerwatch-enable-rapl; do
            ln -sfn "$INSTALL_DIR/contents/scripts/$name" "$BIN_DIR/$name"
        done
        echo "已创建命令软链接于 $BIN_DIR"
        case ":$PATH:" in
            *":$BIN_DIR:"*) ;;
            *) echo "提示：$BIN_DIR 不在 PATH 中，命令行调用请写完整路径。" ;;
        esac
    fi

    echo
    echo "安装完成，接下来："
    echo "  1) 添加部件：右键桌面 → 添加部件 → 搜索「功耗监测」"
    echo "  2) 让 CPU 功耗可用（只需执行一次）："
    echo "       sudo $INSTALL_DIR/contents/scripts/powerwatch-enable-rapl"
    echo "  3) 命令行查看原始数据："
    echo "       $INSTALL_DIR/contents/scripts/powerwatch-collect --pretty"
    echo
    echo "提示：升级后若界面没有变化，重启一下 plasmashell。"
    echo "      Plasma 会缓存已编译的 QML，改完代码不一定自动重载："
    echo "        plasmashell --replace & disown"
}

if [ "$DO_UNINSTALL" = 1 ]; then
    uninstall
else
    install
fi
