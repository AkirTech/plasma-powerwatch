// SPDX-FileCopyrightText: 2026 AkirTech
// SPDX-License-Identifier: GPL-2.0-or-later

/*
    Power Watch — KDE Plasma 6 功耗监测小部件

    数据由 contents/scripts/powerwatch-collect 采集，通过 executable dataengine
    以命令行形式调用（该引擎用 QProcess 直接切分参数，不经 shell）。
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ================================================================ 状态 ==
    property var stats: ({})
    property var history: []
    property bool busy: false
    property bool everLoaded: false
    property string problem: ""
    property real sessionWh: 0
    property double lastSampleMs: 0
    property real cpuPeak: 1
    property real gpuPeak: 1

    readonly property var bat: stats.battery || ({})
    readonly property var ac: stats.ac || ({})
    readonly property var cpu: stats.cpu || ({})
    readonly property var gpu: stats.gpu || ({})
    readonly property var sys: stats.system || ({})
    readonly property var rapl: stats.rapl || ({})
    readonly property var raplDomains: rapl.domains || ({})
    readonly property var usbc: stats.usbc || []
    readonly property var activeUsbc: usbc.filter(function (port) {
        return port.online === true;
    })

    // ================================================================ 配置 ==
    readonly property int refreshSeconds: {
        var v = plasmoid.configuration.interval;
        return (v === undefined || v === null || v < 1) ? 2 : v;
    }
    readonly property int gpuPollSeconds: {
        var v = plasmoid.configuration.gpuPollSeconds;
        return (v === undefined || v === null || v < 0) ? 10 : v;
    }
    readonly property bool cfgShowGraph: plasmoid.configuration.showGraph !== false
    readonly property bool cfgShowCpu: plasmoid.configuration.showCpu !== false
    readonly property bool cfgShowGpu: plasmoid.configuration.showGpu !== false
    readonly property bool cfgShowBattery: plasmoid.configuration.showBattery !== false
    readonly property bool cfgShowSources: plasmoid.configuration.showPowerSources !== false
    readonly property bool cfgShowSession: plasmoid.configuration.showSessionEnergy !== false

    // ============================================================ 采集命令 ==
    readonly property string collectorPath: Qt.resolvedUrl("../scripts/powerwatch-collect")
                                                 .toString().replace(/^file:\/\//, "")
    readonly property string pollCommand: "'" + collectorPath + "' --gpu-poll=" + gpuPollSeconds
    readonly property string forceGpuCommand: "'" + collectorPath + "' --gpu-poll=" + gpuPollSeconds + " --force-gpu"

    // ============================================================ 数值换算 ==
    function isNum(v) {
        return v !== null && v !== undefined && typeof v === "number" && !isNaN(v);
    }

    function fmt(v, digits, unit) {
        if (!isNum(v)) {
            return "—";
        }
        return v.toFixed(digits === undefined ? 1 : digits) + (unit ? " " + unit : "");
    }

    function fmtPercent(v, digits) {
        if (!isNum(v)) {
            return "—";
        }
        return v.toFixed(digits === undefined ? 0 : digits) + "%";
    }

    function fmtDuration(seconds) {
        if (!isNum(seconds) || seconds <= 0) {
            return "—";
        }
        var h = Math.floor(seconds / 3600);
        var m = Math.round((seconds % 3600) / 60);
        if (h > 0) {
            return h + " 小时 " + m + " 分";
        }
        return m + " 分";
    }

    // CPU 封装功耗：优先 RAPL package-0，退而用 psys
    readonly property var cpuPower: {
        if (isNum(raplDomains["package-0"])) {
            return raplDomains["package-0"];
        }
        if (isNum(stats.psys)) {
            return stats.psys;
        }
        return null;
    }

    readonly property var cpuCorePower: isNum(raplDomains["core"]) ? raplDomains["core"] : null
    readonly property var cpuUncorePower: isNum(raplDomains["uncore"]) ? raplDomains["uncore"] : null

    // 独显功耗：挂起状态视为 0 W，不主动唤醒去读
    readonly property var gpuPower: {
        if (!gpu.available) {
            return null;
        }
        if (isNum(gpu.power)) {
            return gpu.power;
        }
        if (gpu.state === "suspended") {
            return 0;
        }
        return null;
    }

    readonly property bool totalMeasured: isNum(sys.power)
    readonly property var totalPower: {
        if (isNum(sys.power)) {
            return sys.power;
        }
        return isNum(sys.components) ? sys.components : null;
    }

    readonly property string powerSourceText: {
        if (ac.online === true) {
            if (bat.status === "Charging") {
                return "交流供电 · 充电中";
            }
            if (bat.status === "Full") {
                return "交流供电 · 已充满";
            }
            return "交流供电";
        }
        for (var i = 0; i < usbc.length; ++i) {
            if (usbc[i].online === true) {
                return "USB-C PD 供电";
            }
        }
        if (bat.present === true) {
            return "电池供电";
        }
        return "未知供电";
    }

    readonly property string totalCaption: {
        if (totalMeasured) {
            return "整机功耗 · 电池放电实测";
        }
        if (isNum(sys.components)) {
            return "组件合计（CPU + 独显）";
        }
        return "暂无可用功耗数据";
    }

    readonly property string tooltipText: {
        if (!everLoaded) {
            return "正在读取…";
        }
        var lines = [];
        lines.push("整机 " + fmt(totalPower, 1, "W") + (totalMeasured ? "" : "（组件合计）"));
        if (cpuPower !== null) {
            lines.push("CPU " + fmt(cpuPower, 1, "W") + " · " + fmt(cpu.temp, 0, "°C"));
        } else {
            lines.push("CPU — " + fmt(cpu.temp, 0, "°C") + (problem.length ? "（" + problem + "）" : ""));
        }
        lines.push("独显 " + (gpu.state === "suspended" ? "已挂起 ≈0 W" : fmt(gpuPower, 1, "W")));
        if (bat.present === true) {
            lines.push("电池 " + fmtPercent(bat.percent) + " · " + fmt(bat.voltage, 2, "V")
                       + " · " + fmt(bat.current, 2, "A"));
        }
        return lines.join("\n");
    }

    // ============================================================ 数据消费 ==
    function consume(rawOutput, dataMap) {
        var text = rawOutput ? String(rawOutput) : "";
        var parsed = null;

        if (text.trim().length > 0) {
            var lines = text.trim().split("\n");
            for (var i = lines.length - 1; i >= 0; --i) {
                if (lines[i].trim().length === 0) {
                    continue;
                }
                try {
                    parsed = JSON.parse(lines[i]);
                } catch (e) {
                    parsed = null;
                }
                if (parsed) {
                    break;
                }
            }
        }
        // 兜底：某些版本会直接把 JSON 展开进 data map
        if (!parsed && dataMap && dataMap["ok"] === true) {
            parsed = dataMap;
        }
        if (!parsed) {
            problem = text.length > 0 ? "输出无法解析" : "采集脚本无输出";
            return;
        }

        problem = "";
        stats = parsed;
        everLoaded = true;

        var now = Date.now();
        var watts = totalPower;
        if (isNum(watts)) {
            if (lastSampleMs > 0) {
                var dtHours = (now - lastSampleMs) / 3600000;
                sessionWh += watts * dtHours;
            }
            lastSampleMs = now;

            var hist = history.slice();
            hist.push(watts);
            while (hist.length > 60) {
                hist.shift();
            }
            history = hist;
        }
        if (isNum(cpuPower)) {
            cpuPeak = Math.max(cpuPeak, cpuPower);
        }
        if (isNum(gpuPower)) {
            gpuPeak = Math.max(gpuPeak, gpuPower);
        }
    }

    function poll(forceGpu) {
        if (busy) {
            return;
        }
        busy = true;
        busyGuard.restart();
        exec.connectSource(forceGpu ? forceGpuCommand : pollCommand);
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var out = (data && data["stdout"] !== undefined) ? data["stdout"] : "";
            exec.disconnectSource(sourceName);
            root.busy = false;
            root.consume(out, data);
        }
    }

    Timer {
        id: pollTimer
        interval: root.refreshSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll(false)
    }

    // 防止采集脚本异常时 busy 卡死
    Timer {
        id: busyGuard
        interval: 10000
        repeat: false
        onTriggered: root.busy = false
    }

    // =============================================================== 外观 ==
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: "功耗监测"
    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: "功耗监测"
    toolTipSubText: tooltipText

    // 桌面（Planar）形态下不做紧凑/完整切换，始终显示完整面板；
    // 放进面板时才按尺寸切换。-1 表示禁用切换。
    readonly property bool planar: Plasmoid.formFactor === PlasmaCore.Types.Planar
    switchWidth: planar ? -1 : Kirigami.Units.gridUnit * 12
    switchHeight: planar ? -1 : Kirigami.Units.gridUnit * 8
    preferredRepresentation: planar ? fullRepresentation : null

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "立即刷新"
            icon.name: "view-refresh"
            onTriggered: root.poll(false)
        },
        PlasmaCore.Action {
            text: "强制读取独立显卡"
            icon.name: "computer"
            onTriggered: root.poll(true)
        }
    ]

    // =========================================================== 面板紧凑态 ==
    compactRepresentation: Item {
        implicitWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: compactRow.implicitHeight
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.5)

            PlasmaComponents.Label {
                text: "⚡"
            }
            PlasmaComponents.Label {
                text: root.isNum(root.totalPower) ? root.totalPower.toFixed(0) + "W" : "—"
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ============================================================= 桌面完整态 ==
    fullRepresentation: Item {
        id: fullRep

        implicitWidth: Kirigami.Units.gridUnit * 18
        implicitHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 13
        Layout.minimumHeight: implicitHeight

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.80)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                  Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.13)
        }

        ColumnLayout {
            id: col
            x: Kirigami.Units.largeSpacing
            y: Kirigami.Units.largeSpacing
            width: parent.width - Kirigami.Units.largeSpacing * 2
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.8)

            // ------------------------------------------------------ 标题栏 --
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "⚡"
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.35)
                }

                PlasmaComponents.Label {
                    text: "功耗监测"
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                   Kirigami.Theme.highlightColor.g,
                                   Kirigami.Theme.highlightColor.b, 0.18)
                    implicitWidth: badge.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: badge.implicitHeight + Math.round(Kirigami.Units.smallSpacing * 0.7)

                    PlasmaComponents.Label {
                        id: badge
                        anchors.centerIn: parent
                        text: root.powerSourceText
                        color: Kirigami.Theme.highlightColor
                        font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.85)
                    }
                }
            }

            // -------------------------------------------------------- 总功耗 --
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.5)
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: root.everLoaded && root.isNum(root.totalPower)
                          ? root.totalPower.toFixed(1) : "—"
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.9)
                }

                PlasmaComponents.Label {
                    text: "W"
                    opacity: 0.65
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.85)
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Math.round(Kirigami.Units.gridUnit * 0.5)
                }

                Item { Layout.fillWidth: true }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.topMargin: -Math.round(Kirigami.Units.smallSpacing * 0.6)
                text: root.everLoaded ? root.totalCaption : "正在读取…"
                opacity: 0.6
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.85)
                elide: Text.ElideRight
            }

            // ---------------------------------------------------------- 曲线 --
            PowerGraph {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.5)
                visible: root.cfgShowGraph
                values: root.history
                floorValue: 10
            }

            // ------------------------------------------------------ CPU / GPU --
            StatRow {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.5)
                visible: root.cfgShowCpu
                label: "CPU"
                value: root.fmt(root.cpuPower, 1, "W")
                note: {
                    var parts = [];
                    if (root.isNum(root.cpu.temp)) {
                        parts.push(root.cpu.temp.toFixed(0) + "°C");
                    }
                    if (root.isNum(root.cpu.freq_mhz)) {
                        parts.push((root.cpu.freq_mhz / 1000).toFixed(2) + "GHz");
                    }
                    return parts.join(" · ");
                }
                fraction: root.isNum(root.cpuPower)
                          ? root.cpuPower / Math.max(20, root.cpuPeak) : -1
                barColor: "#3daee9"
            }

            StatRow {
                Layout.fillWidth: true
                visible: root.cfgShowGpu
                label: "独显"
                value: {
                    if (!root.gpu.available) {
                        return "—";
                    }
                    if (root.gpu.state === "suspended") {
                        return "已挂起";
                    }
                    return root.fmt(root.gpuPower, 1, "W");
                }
                note: {
                    var parts = [];
                    if (root.isNum(root.gpu.temp)) {
                        parts.push(root.gpu.temp.toFixed(0) + "°C");
                    }
                    if (root.isNum(root.gpu.util)) {
                        parts.push(root.gpu.util.toFixed(0) + "%");
                    }
                    return parts.join(" · ");
                }
                fraction: root.isNum(root.gpuPower) && root.gpu.state !== "suspended"
                          ? root.gpuPower / Math.max(20, root.gpuPeak) : -1
                barColor: "#76c76b"
            }

            // CPU 功耗读不到时给出原因
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.cfgShowCpu && root.cpuPower === null && root.problem.length === 0
                text: "⚠ " + (root.rapl.reason || "CPU 功耗不可用")
                opacity: 0.65
                wrapMode: Text.WordWrap
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.82)
            }

            // ---------------------------------------------------------- 分隔 --
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.6)
                Layout.bottomMargin: Math.round(Kirigami.Units.smallSpacing * 0.3)
                implicitHeight: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r,
                               Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.13)
                visible: root.cfgShowBattery && root.bat.present === true
            }

            // ------------------------------------------------------ 电池明细 --
            GridLayout {
                Layout.fillWidth: true
                visible: root.cfgShowBattery && root.bat.present === true
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.4)

                Repeater {
                    model: {
                        var cells = [];
                        function pair(label, value) {
                            cells.push({ "text": label, "isLabel": true });
                            cells.push({ "text": value, "isLabel": false });
                        }
                        pair("电压", root.fmt(root.bat.voltage, 2, "V"));
                        pair("电流", root.fmt(root.bat.current, 2, "A"));
                        pair("功率", root.fmt(root.bat.power, 2, "W"));
                        pair("电量", root.fmtPercent(root.bat.percent));
                        pair("可用", root.fmt(root.bat.energy_wh, 1, "Wh"));
                        pair("满充", root.fmt(root.bat.full_wh, 1, "Wh"));
                        pair("剩余", root.fmtDuration(root.bat.time_left));
                        pair("健康", root.fmtPercent(root.bat.health, 1));
                        return cells;
                    }

                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        text: modelData.text
                        opacity: modelData.isLabel ? 0.6 : 1
                        font.bold: !modelData.isLabel
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        horizontalAlignment: modelData.isLabel ? Text.AlignLeft : Text.AlignRight
                    }
                }
            }

            // ---------------------------------------------- 适配器 / USB-C PD --
            StatRow {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.3)
                visible: root.cfgShowSources && root.ac.present === true
                label: "适配器"
                value: root.ac.online === true ? "已连接" : "未连接"
                note: root.ac.name || ""
                fraction: -1
            }

            Repeater {
                model: root.cfgShowSources ? root.activeUsbc : []

                delegate: StatRow {
                    required property var modelData
                    Layout.fillWidth: true
                    label: "USB-C"
                    value: root.fmt(modelData.voltage, 2, "V") + " · "
                           + root.fmt(modelData.current, 2, "A")
                    note: root.fmt(modelData.power, 1, "W")
                    fraction: -1
                }
            }

            StatRow {
                Layout.fillWidth: true
                visible: root.cfgShowSources && root.usbc.length > 0 && root.activeUsbc.length === 0
                label: "USB-C"
                value: "未接入"
                note: root.usbc.length + " 个端口"
                fraction: -1
                opacity: 0.7
            }

            // ---------------------------------------------------------- 页脚 --
            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 0.6)
                visible: root.cfgShowSession || root.problem.length > 0
                text: {
                    if (root.problem.length > 0) {
                        return "⚠ " + root.problem;
                    }
                    return "本次会话 " + root.sessionWh.toFixed(2) + " Wh · 每次刷新 "
                           + root.refreshSeconds + " 秒";
                }
                opacity: 0.5
                elide: Text.ElideRight
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.8)
            }
        }
    }
}
