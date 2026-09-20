import QtQuick

Canvas {
    id: chart
    property var points: []
    property string field: "cpu"
    property string field2: ""
    property bool autoScale: false
    property color ink: "#8ab4f8"
    property color secondInk: "#8291a8"
    property color grid: "#303748"
    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onInkChanged: requestPaint()
    onGridChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.strokeStyle = grid;
        ctx.lineWidth = 1;
        for (var i = 0; i < 5; i++) {
            var y = 8 + (height - 16) * i / 4;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();
        }
        if (points.length < 2)
            return;
        var maximum = 100, end = points[points.length - 1].time;
        if (autoScale) {
            maximum = 1;
            for (var k = 0; k < points.length; k++)
                maximum = Math.max(maximum, points[k][field] || 0, points[k][field2] || 0);
        }
        var fields = field2 ? [field, field2] : [field];
        for (var f = 0; f < fields.length; f++) {
            ctx.strokeStyle = f === 0 ? ink : secondInk;
            ctx.lineWidth = 2;
            ctx.beginPath();
            var active = false;
            for (var j = 0; j < points.length; j++) {
                var p = points[j], v = p[fields[f]];
                if (v === null || v === undefined) {
                    active = false;
                    continue;
                }
                var x = width * (1 - (end - p.time) / 60000), yy = 8 + (height - 16) * (1 - Math.min(maximum, Math.max(0, v)) / maximum);
                if (active)
                    ctx.lineTo(x, yy);
                else
                    ctx.moveTo(x, yy);
                active = true;
            }
            ctx.stroke();
        }
    }
}
