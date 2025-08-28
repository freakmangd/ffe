// TODO:
// [X] ctrl.T: Open terminal here
// [X] Scrolling!!!
// [X] Tile mode
//      [X] Layout
//      [X] Thumbnails
// [X] Change "run" from "/" to ctrl+; and use a text box
// [ ] Shortcuts
// [ ] Allow typing abs paths like "/usr/share/fonts/" or "~/project/assets" to go there
//      Combined with the other todo, when you type "/" it will preview root dir,
//      and typing "~/" will preview home dir
// [ ] Tab to complete the rest of the hovered file name
// [ ] When you have a full dir name in search bar and you then press "/",
//      preview dir contents, so if youre in "~/project/abc/" you can search
//      "assets/art/thing" and press enter and open "~/project/assets/art/thing.png"
// [ ] Icons for list and tile mode

const std = @import("std");
const rl = @import("raylib");
const kf = @import("kf");
const fuzz = @import("fuzz.zig");
const opts = @import("opts");
const h = @import("rl_helper.zig");
const font_file = @embedFile("font");
const eql = std.mem.eql;

const Tab = @import("tab.zig");
const Textbox = @import("textbox.zig");

const thumbnail_size = 80;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_ally = gpa.allocator();

    var failing = std.testing.FailingAllocator.init(gpa_ally, .{ .fail_index = opts.allocs orelse std.math.maxInt(usize) });

    const ally = ally: {
        if (opts.allocs) |_| {
            break :ally failing.allocator();
        } else {
            break :ally gpa_ally;
        }
    };

    rl.SetTraceLogLevel(.warning);
    rl.SetConfigFlags(.{
        .window_resizable = true,
    });

    rl.InitWindow(800, 600, "ffe");
    defer rl.CloseWindow();

    const icon = rl.Image.initFromMemory(".png", @embedFile("icon"), @embedFile("icon").len);
    defer icon.deinit();

    rl.SetWindowIcon(icon);
    rl.SetWindowMinSize(300, 300);
    rl.SetExitKey(.null);

    var font = rl.Font.initFromMemory(".otf", font_file, 24, null);
    defer font.deinit();

    rl.SetTextureFilter(font.texture, .bilinear);

    var dtw = rl.DrawTextWriter.initEx(font, rl.Vector2.init(30, 68), 24, 0, Tab.color.text);
    const rl_writer = dtw.writer();

    var tabs: std.ArrayListUnmanaged(Tab) = .{};
    defer {
        for (tabs.items) |*tab| {
            tab.deinit();
        }
        tabs.deinit(ally);
    }

    var args = try std.process.argsWithAllocator(ally);
    defer args.deinit();
    _ = args.skip();

    Tab.home_path = try kf.getPath(ally, .home);
    defer if (Tab.home_path) |path| ally.free(path);

    try tabs.append(ally, try Tab.init(ally, args.next() orelse Tab.home_path orelse "."));

    if (try kf.open(ally, .local_configuration, .{})) |config_folder| {
        const conf = config_folder.openFile("ffe_config.json", .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try config_folder.createFile("ffe_config.json", .{}),
            else => return err,
        };

        const writer = conf.writer();
        try writer.writeAll(@embedFile("default_config.json"));
    }

    if (try kf.open(ally, .cache, .{})) |cache| {
        Tab.thumbnail_cache = cache.makeOpenPath("ffe/thumbnails", .{}) catch |err| thumbnail_cache: {
            std.log.err("Failed to open cache, it will be disabled for this run. Error: {}", .{err});
            break :thumbnail_cache null;
        };
    }

    while (!rl.WindowShouldClose()) {
        defer dtw.reset();

        if (rl.IsKeyPressed(.insert)) {
            failing.alloc_index = 0;
        }

        if (h.modPressed(.left_control, .q)) return;

        for (tabs.items) |*tab| tab.update();

        rl.BeginDrawing();

        rl.ClearBackground(Tab.color.bg);
        for (tabs.items) |tab| tab.draw(&dtw, rl_writer, font);

        rl.EndDrawing();
    }
}

test {
    _ = @import("fuzz.zig");
}
