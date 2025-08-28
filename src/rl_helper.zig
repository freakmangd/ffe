const rl = @import("raylib");
const Tab = @import("tab.zig");

pub fn isPressedRepeat(key: rl.KeyboardKey) bool {
    return rl.IsKeyPressed(key) or rl.IsKeyPressedRepeat(key);
}

pub fn modPressed(mod: rl.KeyboardKey, key: rl.KeyboardKey) bool {
    return rl.IsKeyDown(mod) and rl.IsKeyPressed(key);
}

pub fn modPressedRepeat(mod: rl.KeyboardKey, key: rl.KeyboardKey) bool {
    return rl.IsKeyDown(mod) and isPressedRepeat(key);
}

pub fn drawRoundedBox(rect: rl.Rectangle) void {
    rl.DrawRectangleRounded(rect, 0.2, 3, Tab.color.bg);
    rl.DrawRectangleRoundedLines(rect, 0.2, 3, Tab.color.text);
}
