.pragma library

function number(tokens, key, fallback, low, high) {
    var raw = tokens[key];
    var value = Number(raw);
    if (raw === undefined || raw === null || raw === "" || !isFinite(value))
        value = fallback;
    return Math.max(low, Math.min(high, value));
}
function savedWidths(value) {
    try {
        var result = JSON.parse(value);
        return result && typeof result === "object" && !Array.isArray(result) ? result : ({});
    } catch (e) { return ({}); }
}
function fixedWidth(column, overrides) {
    var saved = overrides ? Number(overrides[column.key]) : NaN;
    if (isFinite(saved) && saved > 0)
        return Math.max(column.key === "name" ? 120 : 48, Math.min(1200, saved));
    return column.width;
}
function columnWidth(columns, column, total, scale, overrides) {
    var fixed = fixedWidth(column, overrides);
    if (fixed > 0)
        return fixed * scale;
    var reserved = 0;
    for (var i = 0; i < columns.length; ++i) {
        var width = fixedWidth(columns[i], overrides);
        if (width > 0) reserved += width * scale;
    }
    return Math.max(120 * scale, total - reserved);
}
function tableWidth(columns, scale, overrides) {
    var width = 0;
    for (var i = 0; i < columns.length; ++i) {
        var fixed = fixedWidth(columns[i], overrides);
        width += fixed > 0 ? fixed : 120;
    }
    return width * scale;
}
