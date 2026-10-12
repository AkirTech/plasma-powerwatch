// SPDX-FileCopyrightText: 2026 AkirTech
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

/*
    功耗历史曲线（Canvas 手绘，无需额外依赖）
*/
Item {
    id: graph

    property var values: []
    property color lineColor: Kirigami.Theme.highlightColor
    // 纵轴最小跨度：数据起伏比它还小时按此放大，避免曲线看起来是一条直线
    property real floorValue: 10

    onValuesChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onFloorValueChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            ctx.clearRect(0, 0, w, h);
            if (w <= 1 || h <= 1) {
                return;
            }

            var n = graph.values.length;

            // 参考横线
            ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.09);
            ctx.lineWidth = 1;
            for (var g = 1; g < 3; ++g) {
                var gy = Math.round(h * g / 3) + 0.5;
                ctx.beginPath();
                ctx.moveTo(0, gy);
                ctx.lineTo(w, gy);
                ctx.stroke();
            }

            if (n < 2) {
                ctx.strokeStyle = Qt.rgba(graph.lineColor.r, graph.lineColor.g,
                                          graph.lineColor.b, 0.3);
                ctx.beginPath();
                ctx.moveTo(0, h - 1.5);
                ctx.lineTo(w, h - 1.5);
                ctx.stroke();
                return;
            }

            var lo = graph.values[0];
            var hi = graph.values[0];
            for (var i = 1; i < n; ++i) {
                if (graph.values[i] < lo) {
                    lo = graph.values[i];
                }
                if (graph.values[i] > hi) {
                    hi = graph.values[i];
                }
            }

            // 起伏太小时以中点为基准向上下扩展，让曲线看得出形状
            var minSpan = Math.max(graph.floorValue * 0.2, 2);
            if (hi - lo < minSpan) {
                var mid = (hi + lo) / 2;
                lo = mid - minSpan / 2;
                hi = mid + minSpan / 2;
            }
            var pad = (hi - lo) * 0.10;
            lo -= pad;
            hi += pad;
            var range = hi - lo;
            if (range <= 0) {
                range = 1;
            }

            var step = w / (n - 1);
            var xs = [];
            var ys = [];
            for (i = 0; i < n; ++i) {
                var ratio = (graph.values[i] - lo) / range;
                if (ratio < 0) {
                    ratio = 0;
                } else if (ratio > 1) {
                    ratio = 1;
                }
                xs.push(i * step);
                ys.push(h - 2 - ratio * (h - 4));
            }

            // 曲线下方填充
            ctx.beginPath();
            ctx.moveTo(xs[0], h);
            for (i = 0; i < n; ++i) {
                ctx.lineTo(xs[i], ys[i]);
            }
            ctx.lineTo(xs[n - 1], h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(graph.lineColor.r, graph.lineColor.g,
                                    graph.lineColor.b, 0.20);
            ctx.fill();

            // 曲线本身
            ctx.beginPath();
            ctx.moveTo(xs[0], ys[0]);
            for (i = 1; i < n; ++i) {
                ctx.lineTo(xs[i], ys[i]);
            }
            ctx.strokeStyle = graph.lineColor;
            ctx.lineWidth = 1.6;
            ctx.stroke();
        }
    }
}
