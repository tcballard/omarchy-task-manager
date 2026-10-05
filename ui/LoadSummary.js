.pragma library

// Presentation heuristic, not a diagnosis: every sample must meet the threshold
// over ten seconds. Missing readings and gaps never count as low or high usage.
function valid(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= 100;
}

function level(points, field, maxGap) {
    if (!points.length)
        return "unknown";
    var end = points[points.length - 1].time;
    var previous = end;
    var high = true;
    for (var i = points.length - 1; i >= 0; --i) {
        var point = points[i];
        if (typeof point.time !== "number" || !isFinite(point.time) ||
                point.time > previous || previous - point.time > maxGap ||
                !valid(point[field]))
            return "unknown";
        high = high && point[field] >= 90;
        if (end - point.time >= 10000)
            return high ? "high" : "normal";
        previous = point.time;
    }
    return "unknown";
}

function explain(points, paused, fresh, maxGap) {
    if (paused)
        return "Monitoring is paused. Resume to check recent CPU and memory use.";
    if (!fresh)
        return "Waiting for fresh readings before checking CPU and memory use.";
    var cpu = level(points, "cpu", maxGap);
    var memory = level(points, "memory", maxGap);
    if (cpu === "high" && memory === "high")
        return "CPU use has stayed high and memory is nearly full. Both can slow other work. Review Applications before deciding what to close.";
    if (cpu === "high")
        return "CPU use has stayed high. Busy work can slow other apps. Review Applications to see current use; high use does not mean an app is frozen.";
    if (memory === "high")
        return "Memory has stayed nearly full. This can slow apps. Review Applications and save your work before closing anything.";
    if (cpu === "unknown" || memory === "unknown")
        return "Collecting CPU and memory readings. Allow at least ten seconds of continuous monitoring.";
    return "No sustained high CPU or memory use detected. Other causes of slowness are still possible.";
}
