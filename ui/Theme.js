.pragma library

function number(tokens, key, fallback, low, high) {
    var raw = tokens[key];
    var value = Number(raw);
    if (raw === undefined || raw === null || raw === "" || !isFinite(value))
        value = fallback;
    return Math.max(low, Math.min(high, value));
}
function columnWidth(columns, column, total, scale) {
    if (column.width > 0)
        return column.width * scale;
    var reserved = 0;
    for (var i = 0; i < columns.length; ++i)
        if (columns[i].width > 0)
            reserved += columns[i].width * scale;
    return Math.max(120 * scale, total - reserved);
}
function tableWidth(columns, scale) {
    var width = 120;
    for (var i = 0; i < columns.length; ++i)
        if (columns[i].width > 0)
            width += columns[i].width;
    return width * scale;
}
