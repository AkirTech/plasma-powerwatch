// SPDX-FileCopyrightText: 2026 AkirTech
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Kirigami.FormLayout {
    id: page

    // 授权脚本随小部件一起安装，路径从当前文件推导，不依赖任何固定安装位置
    readonly property string raplHelper: Qt.resolvedUrl("../scripts/powerwatch-enable-rapl")
                                                .toString().replace(/^file:\/\//, "")

    property alias cfg_interval: intervalSpin.value
    property alias cfg_gpuPollSeconds: gpuSpin.value
    property alias cfg_showGraph: graphCheck.checked
    property alias cfg_showCpu: cpuCheck.checked
    property alias cfg_showGpu: gpuCheck.checked
    property alias cfg_showBattery: batteryCheck.checked
    property alias cfg_showPowerSources: sourcesCheck.checked
    property alias cfg_showSessionEnergy: sessionCheck.checked

    PlasmaComponents.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: "刷新间隔（秒）"
        from: 1
        to: 60
    }

    PlasmaComponents.SpinBox {
        id: gpuSpin
        Kirigami.FormData.label: "独立显卡采样间隔（秒）"
        from: 0
        to: 300
    }

    PlasmaComponents.Label {
        Kirigami.FormData.isSection: true
        text: "显示内容"
        font.bold: true
    }

    PlasmaComponents.CheckBox {
        id: graphCheck
        text: "功耗历史曲线"
    }

    PlasmaComponents.CheckBox {
        id: cpuCheck
        text: "CPU 功耗与温度"
    }

    PlasmaComponents.CheckBox {
        id: gpuCheck
        text: "独立显卡功耗"
    }

    PlasmaComponents.CheckBox {
        id: batteryCheck
        text: "电池电压 / 电流 / 电量"
    }

    PlasmaComponents.CheckBox {
        id: sourcesCheck
        text: "适配器与 USB-C PD"
    }

    PlasmaComponents.CheckBox {
        id: sessionCheck
        text: "本次会话累计用电量"
    }

    PlasmaComponents.Label {
        Kirigami.FormData.isSection: true
        text: "说明"
        font.bold: true
    }

    PlasmaComponents.Label {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        opacity: 0.75
        font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.85)
        text: "整机功耗取自电池放电功率（最准）。插电时改显示 CPU + 独显的合计值。\n"
              + "CPU 功耗来自 Intel RAPL，默认只有 root 能读；执行一次下面这条命令即可永久放行：\n"
              + "sudo " + page.raplHelper + "\n"
              + "独立显卡采样间隔设为 0 可完全停用；独显挂起时不会主动唤醒它。"
    }
}
