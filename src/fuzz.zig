const std = @import("std");

pub fn score(prompt: []const u8, line: []const u8) f32 {
    if (prompt.len > line.len) return 0;
    if (prompt.len == 0) return 1;

    var hits: f32 = 0;

    if (prompt[0] == line[0]) {
        hits += @floatFromInt(line.len);
    }

    var pi: usize = 0;
    var li: usize = 0;

    var prev_hit: bool = false;
    while (pi < prompt.len and li < line.len) : ({
        li += 1;
    }) {
        if (std.ascii.toLower(prompt[pi]) == std.ascii.toLower(line[li])) {
            hits += 1;
            pi += 1;
            if (prev_hit) {
                hits += @floatFromInt(line.len);
            }
            prev_hit = true;
        } else if (std.ascii.toLower(prompt[0]) == std.ascii.toLower(line[li])) {
            hits = @max(hits, score(prompt, line[li..]));
        } else prev_hit = false;
    }

    if (pi != prompt.len) return 0;

    return hits / @as(f32, @floatFromInt(line.len));
}

fn div(a: anytype, b: anytype) f32 {
    return @as(f32, @floatFromInt(a)) / @as(f32, @floatFromInt(b));
}

test score {
    //const exact_match = score("abcdef", "abcdef");
    //const no_match = score("abcdef", "ghijkl");
    //const ok_match = score("ab", "abcdef");

    //try expectGt(exact_match, ok_match);
    //try expectGt(ok_match, no_match);

    const sequence_match = score("zo", "build.zig.zon");
    const non_seq_match = score("zo", "zig-out");

    try expectGt(sequence_match, non_seq_match);
}

fn expectGt(a: anytype, b: @TypeOf(a)) !void {
    if (a <= b) {
        std.debug.print("Found {d} > {d}\n", .{ a, b });
        return error.TestExpectedGt;
    }
}
