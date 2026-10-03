function check(condition, message) {
    if (!condition) throw new Error(message);
}
function samples(cpu, memory, interval) {
    var result = [];
    for (var t = 0; t <= 10000; t += interval)
        result.push({time: t, cpu: cpu, memory: memory});
    return result;
}
var points = samples(95, 40, 1000);
check(level(points, "cpu", 3000) === "high", "sustained CPU");
check(explain(points, false, true, 3000).indexOf("CPU use has stayed high") === 0, "CPU explanation");
check(level(points.slice(1), "cpu", 3000) === "unknown", "short history");
points[4].cpu = 20;
check(level(points, "cpu", 3000) === "normal", "interrupted high usage");
points = samples(20, 40, 1000);
points[10].cpu = 100;
check(level(points, "cpu", 3000) === "normal", "brief spike");
for (var missing of [null, undefined, NaN, Infinity, -1, 101, "95"]) {
    points = samples(95, 40, 1000);
    points[5].cpu = missing;
    check(level(points, "cpu", 3000) === "unknown", "invalid reading " + missing);
}
points = samples(95, 95, 1000);
check(explain(points, false, true, 3000).indexOf("Both can slow") > 0, "combined high");
check(explain(points, true, true, 3000).indexOf("Monitoring is paused") === 0, "paused");
check(explain(points, false, false, 3000).indexOf("Waiting for fresh") === 0, "stale");
check(level([points[0], points[10]], "cpu", 3000) === "unknown", "gap");
points[5].time = 20000;
check(level(points, "cpu", 3000) === "unknown", "out of order");
check(level(samples(95, 40, 5000), "cpu", 10000) === "high", "slow interval");
check(level(samples(95, 40, 500), "cpu", 3000) === "high", "fast interval");
points = samples(20, 95, 1000);
check(explain(points, false, true, 3000).indexOf("Memory has stayed") === 0, "memory");
points = samples(20, null, 1000);
check(explain(points, false, true, 3000).indexOf("Collecting") === 0, "unknown is not healthy");
points = samples(20, 40, 1000);
check(explain(points, false, true, 3000).indexOf("Other causes") > 0, "limited reassurance");
check(level([], "cpu", 3000) === "unknown", "empty");
