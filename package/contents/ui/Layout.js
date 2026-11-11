.pragma library

// Strip length, fit and drag arithmetic. The functions are pure and see no QML properties.
// The caller builds the input record in one binding that reads every dependency.
//
// Input record:
//   levels  the steps the strip can take, longest first: [0,1,2,3], or [0,1,3] when vertical
//   cells   for each level (key is the level), the length of each shown stat in order
//   gap     for each level, the whole separator cost between two stats
// The number of stats is the length of the cell array of the first level.
// A layout is { level, drop, len }. A fit is { level, drop }.
// Level 3 is the drop level: stats are dropped from the end at this level only.

var DROP_LEVEL = 3

function statCount(input) {
    return input.cells[input.levels[0]].length
}

// Length of the strip at a level, with the last `drop` stats removed.
// The sum is rounded up, plus one pixel for layout rounding.
function stripLength(input, level, drop) {
    var n = statCount(input) - drop
    if (n <= 0) return 0
    var cells = input.cells[level]
    var total = 0
    for (var i = 0; i < n; ++i) total += cells[i]
    return Math.ceil(total + (n - 1) * input.gap[level]) + 1
}

// Every layout the strip can take, longest first: each level with all stats,
// then dropping stats one by one at the drop level.
function configs(input) {
    var list = []
    var n = statCount(input)
    for (var k = 0; k < input.levels.length; ++k) {
        var lv = input.levels[k]
        list.push({ level: lv, drop: 0, len: stripLength(input, lv, 0) })
    }
    for (var drop = 1; drop < n; ++drop)
        list.push({ level: DROP_LEVEL, drop: drop, len: stripLength(input, DROP_LEVEL, drop) })
    return list
}

// The longest layout that fits maxLength. A limit of 0 or less means no limit.
function computeFit(input, maxLength) {
    var n = statCount(input)
    if (maxLength <= 0 || n === 0) return { level: 0, drop: 0 }
    for (var k = 0; k < input.levels.length; ++k)
        if (stripLength(input, input.levels[k], 0) <= maxLength) return { level: input.levels[k], drop: 0 }
    for (var drop = 1; drop < n; ++drop)
        if (stripLength(input, DROP_LEVEL, drop) <= maxLength) return { level: DROP_LEVEL, drop: drop }
    return { level: DROP_LEVEL, drop: n - 1 }                         // only the first stat is left
}

// The index of the layout equal to the fit. 0 when the fit is absent.
function dragStart(layouts, fit) {
    for (var i = 0; i < layouts.length; ++i)
        if (layouts[i].level === fit.level && layouts[i].drop === fit.drop) return i
    return 0
}

// The limit for a pointer length, snapped to 5 px, never below 20 px.
function snapLimit(dragLength) {
    return Math.max(20, Math.round(dragLength / 5) * 5)
}

// The new layout index for a snapped limit. Growing is immediate: as soon as a longer layout
// fits, it is shown. Shrinking needs the limit at or below the halfway point between the
// current layout and the next strictly shorter one.
function dragStep(layouts, cfgIndex, limit) {
    var cfg = cfgIndex
    var fitIdx = layouts.length - 1
    for (var i = 0; i < layouts.length; ++i) if (layouts[i].len <= limit) { fitIdx = i; break }
    if (fitIdx < cfg) cfg = fitIdx
    while (cfg < layouts.length - 1) {
        var cur = layouts[cfg].len
        var j = cfg + 1
        while (j < layouts.length && layouts[j].len >= cur) ++j       // next strictly shorter layout
        if (j >= layouts.length) break
        if (limit > (cur + layouts[j].len) / 2) break                 // not yet halfway
        cfg = j
    }
    return cfg
}

// The limit to save: the snapped limit, never shorter than the shown layout.
// 0 (no limit) when it reaches the full length.
function dragMax(layouts, cfgIndex, limit, fullLength) {
    var layout = layouts[Math.min(cfgIndex, layouts.length - 1)]
    var v = Math.max(limit, layout.len)
    return v >= fullLength ? 0 : v
}
