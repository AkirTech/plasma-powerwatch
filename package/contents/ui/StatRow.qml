// SPDX-FileCopyrightText: 2026 AkirTech
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

/*
    一行 "标签  数值  备注" + 可选的比例条
*/
ColumnLayout {
    id: stat

    property string label: ""
    property string value: ""
    property string note: ""
    // 小于 0 表示不画比例条，否则为 0~1 的占比
    property real fraction: -1
    property color barColor: Kirigami.Theme.highlightColor

    spacing: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.35))

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: stat.label
            opacity: 0.72
            elide: Text.ElideRight
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 2.4)
        }

        PlasmaComponents.Label {
            text: stat.value
            font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            text: stat.note
            visible: stat.note.length > 0
            opacity: 0.55
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 5.6)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: stat.fraction >= 0
        implicitHeight: Math.max(3, Math.round(Kirigami.Units.smallSpacing * 0.7))
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.14)

        Rectangle {
            height: parent.height
            radius: parent.radius
            color: stat.barColor
            width: parent.width * Math.max(0, Math.min(1, stat.fraction))
            Behavior on width {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
        }
    }
}
