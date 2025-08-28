const std = @import("std");
const rl = @import("raylib");
const h = @import("rl_helper.zig");
const Tab = @import("tab.zig");
const Textbox = @This();

str: std.ArrayListUnmanaged(u8) = .{},
insert_idx: usize = 0,

pub fn deinit(self: *Textbox, ally: std.mem.Allocator) void {
    self.str.deinit(ally);
}

pub fn update(self: *Textbox, ally: std.mem.Allocator) bool {
    if (!rl.IsKeyDown(.left_control) and rl.IsKeyPressed(.left)) {
        self.insert_idx -|= 1;
    } else if (!rl.IsKeyDown(.left_control) and rl.IsKeyPressed(.right)) {
        self.insert_idx = @min(self.insert_idx + 1, self.str.items.len);
    }

    if (self.str.items.len > 0 and h.isPressedRepeat(.backspace)) {
        if (rl.IsKeyDown(.left_alt) or rl.IsKeyDown(.left_shift)) {
            const idx = std.mem.lastIndexOfAny(u8, self.str.items[0..self.insert_idx], " !@#$%^&*()_+-=[{]};:'\",<.>/?`~\\|") orelse 0;
            for (0..self.insert_idx - idx) |_| {
                _ = self.str.orderedRemove(idx);
            }
            self.insert_idx -= self.insert_idx - idx;
        } else {
            _ = self.str.orderedRemove(self.insert_idx - 1);
            self.insert_idx -= 1;
        }

        return true;
    }

    const char = rl.GetCharPressed();
    if (char != 0) {
        self.str.insert(ally, self.insert_idx, @intCast(char)) catch |e| {
            std.log.err("Out of memory for appending to text box. Error: {}", .{e});
            return false;
        };

        self.insert_idx += 1;
        return true;
    }

    return false;
}

pub fn draw(self: Textbox, font: rl.Font, font_size: f32, rect: rl.Rectangle) void {
    h.drawRoundedBox(rect);
    rl.DrawTextSliceEx(font, self.str.items, .{ .x = rect.x + 5, .y = rect.y }, @intFromFloat(font_size), 0, Tab.color.text);

    const text_size = rl.MeasureTextSliceEx(font, self.str.items[0..self.insert_idx], 24, 0);
    rl.DrawLineV(.{ .x = rect.x + 6 + text_size.x, .y = rect.y + 2 }, .{ .x = rect.x + 6 + text_size.x, .y = rect.y + font_size - 2 }, Tab.color.text);
}

pub fn clear(self: *Textbox) void {
    self.str.clearRetainingCapacity();
    self.insert_idx = 0;
}
