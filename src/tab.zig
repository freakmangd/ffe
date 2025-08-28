const std = @import("std");
const rl = @import("raylib");
const h = @import("rl_helper.zig");
const fuzz = @import("fuzz.zig");
const Textbox = @import("textbox.zig");

pub var home_path: ?[]const u8 = null;
pub var thumbnail_cache: ?std.fs.Dir = null;

pub const color = struct {
    pub const bg = rl.Color.fromHex(0x1F1F28FF);
    pub const text = rl.Color.fromHex(0xEEEEEEFF);
};

const Tab = @This();

ally: std.mem.Allocator,
dir: std.fs.Dir,

path: std.ArrayListUnmanaged(u8),

search_bar: Textbox = .{},

files: std.ArrayListUnmanaged(File) = .{},
selected_file: usize = 0,

cutting: bool = false,

special_action: enum {
    none,
    create_file,
    run_command,
} = .none,
special_action_textbox: Textbox = .{},

show_bookmarks: bool = false,
bookmarks_textbox: Textbox = .{},

scroll: c_int = 0,

display_mode: enum {
    list,
    tile,
} = .list,

pub fn init(ally: std.mem.Allocator, path: []const u8) !Tab {
    const dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    const full_path = try dir.realpathAlloc(ally, ".");

    var self: Tab = .{
        .ally = ally,
        .dir = dir,
        .path = std.ArrayListUnmanaged(u8).fromOwnedSlice(full_path),
    };
    try self.readDir(dir, &self.files);

    return self;
}

pub fn deinit(self: *Tab) void {
    self.search_bar.deinit(self.ally);
    self.special_action_textbox.deinit(self.ally);
    self.path.deinit(self.ally);
    for (self.files.items) |file| {
        file.name.deinit(self.ally);
    }
    self.files.deinit(self.ally);
    self.dir.close();
}

pub fn update(self: *Tab) void {
    if (self.special_action != .none) {
        _ = self.special_action_textbox.update(self.ally);

        if (rl.IsKeyPressed(.escape)) {
            self.special_action = .none;
        } else if (rl.IsKeyPressed(.enter)) {
            if (self.special_action_textbox.str.items.len == 0) {
                self.special_action = .none;
                return;
            }

            const str = self.special_action_textbox.str.items;
            switch (self.special_action) {
                .none => unreachable,
                .create_file => {
                    const new_file = self.dir.createFile(str, .{ .exclusive = true }) catch |err| {
                        std.log.err("Failed to create {s}. Error: {}", .{ str, err });
                        return;
                    };
                    new_file.close();
                },
                .run_command => run_command: {
                    var argv = std.ArrayList([]const u8).init(self.ally);
                    defer argv.deinit();

                    var start: usize = 0;
                    var end: usize = 0;
                    var in_quotes = false;

                    while (end < str.len) {
                        while (end < str.len) : (end += 1) switch (str[end]) {
                            '"' => in_quotes = !in_quotes,
                            ' ' => if (!in_quotes) break,
                            else => {},
                        };

                        if (start != end) argv.append(str[start..end]) catch |err| {
                            std.log.err("Failed to parse argv for command. Error: {}", .{err});
                            break :run_command;
                        };
                        end += 1;
                        start = end;
                    }

                    //for (argv.items) |arg| {
                    //    std.log.info("Parsed: `{s}`", .{arg});
                    //}

                    spawnIn(self.ally, self.dir, argv.items);
                },
            }

            self.special_action = .none;
            // TODO: add new file instead of refresh
            self.refresh();
        }
        return;
    }

    if (self.show_bookmarks) {
        _ = self.bookmarks_textbox.update(self.ally);

        if (rl.IsKeyPressed(.escape)) {
            self.show_bookmarks = false;
        } else if (rl.IsKeyPressed(.enter)) {
            self.show_bookmarks = false;
        }

        return;
    }

    if (rl.IsKeyPressed(.tab)) {
        self.show_bookmarks = true;
        self.bookmarks_textbox.clear();
        return;
    }

    if (h.isPressedRepeat(.down) or h.modPressedRepeat(.left_control, .j)) {
        switch (self.display_mode) {
            .list => self.selected_file = @min(self.selected_file + 1, self.files.items.len - 1),
            .tile => self.selected_file = @min(self.selected_file + tilesPerRow(), self.files.items.len - 1),
        }
    } else if (h.isPressedRepeat(.up) or h.modPressedRepeat(.left_control, .k)) {
        switch (self.display_mode) {
            .list => self.selected_file -|= 1,
            .tile => self.selected_file -|= tilesPerRow(),
        }
    } else if (h.modPressedRepeat(.left_control, .d)) {
        switch (self.display_mode) {
            .list => self.selected_file = @min(self.selected_file + 10, self.files.items.len - 1),
            .tile => self.selected_file = @min(self.selected_file + tilesPerRow() * 2, self.files.items.len - 1),
        }
    } else if (h.modPressedRepeat(.left_control, .u)) {
        switch (self.display_mode) {
            .list => self.selected_file -|= 10,
            .tile => self.selected_file -|= tilesPerRow() * 2,
        }
    } else if (h.modPressedRepeat(.left_control, .right) or h.modPressedRepeat(.left_control, .l)) {
        switch (self.display_mode) {
            .list => {},
            .tile => self.selected_file = @min(self.selected_file + 1, self.files.items.len - 1),
        }
    } else if (h.modPressedRepeat(.left_control, .left) or h.modPressedRepeat(.left_control, .h)) {
        switch (self.display_mode) {
            .list => {},
            .tile => self.selected_file -|= 1,
        }
    }

    if (self.search_bar.update(self.ally)) {
        self.selected_file = 0;
        searchbarSort(self.files.items, self.search_bar.str.items);
    }

    if (rl.IsKeyDown(.left_control)) {
        if (rl.IsKeyPressed(.c)) copy: {
            var buf: [std.fs.max_path_bytes:0]u8 = undefined;

            const selected = self.files.items[self.selected_file];
            const selected_name = selected.getName() orelse {
                std.log.err("Could not copy {}, the name of the file is wrong due to OOM, try refreshing (ctrl+r)", .{selected.name});
                break :copy;
            };

            const realpath = self.dir.realpath(selected_name, buf[0..]) catch |err| {
                std.log.err("Failed to get path for file, did not copy. Error: {}", .{err});
                break :copy;
            };

            if (realpath.len <= buf.len)
                buf[realpath.len] = 0;

            std.log.info("Copied {s}", .{realpath});
            rl.SetClipboardText(&buf);
        } else if (rl.IsKeyPressed(.x)) cut: {
            var buf: [std.fs.max_path_bytes:0]u8 = undefined;

            const selected = self.files.items[self.selected_file];
            const selected_name = selected.getName() orelse {
                std.log.err("Could not cut {}, the name of the file is wrong due to OOM, try refreshing (ctrl+r)", .{selected.name});
                break :cut;
            };

            const realpath = self.dir.realpath(selected_name, buf[0..]) catch |err| {
                std.log.err("Failed to get path for file, did not cut. Error: {}", .{err});
                break :cut;
            };

            if (realpath.len <= buf.len)
                buf[realpath.len] = 0;

            std.log.info("Cut {s}", .{realpath});
            self.cutting = true;
        } else if (rl.IsKeyPressed(.v)) paste: {
            defer self.cutting = false;

            const copy_path = std.mem.sliceTo(rl.GetClipboardText() orelse break :paste, 0);
            if (!std.fs.path.isAbsolute(copy_path)) break :paste;

            const basename = std.fs.path.basename(copy_path);

            var alloced = false;
            const copy_to_name = copy_to_name: {
                var accesses: usize = 1;
                var copy_to_name = basename;

                while (true) : (accesses += 1) {
                    self.dir.access(copy_to_name, .{}) catch |err| switch (err) {
                        error.FileNotFound => break,
                        else => {},
                    };

                    if (alloced) self.ally.free(copy_to_name);
                    alloced = true;

                    var str = std.ArrayList(u8).init(self.ally);
                    const str_writer = str.writer();

                    (str_build: {
                        str_writer.writeAll(basename) catch |err| break :str_build err;
                        str_writer.writeAll(" (copy") catch |err| break :str_build err;
                        if (accesses > 1) {
                            str_writer.print(" {}", .{accesses}) catch |err| break :str_build err;
                        }
                        str_writer.writeAll(")") catch |err| break :str_build err;

                        copy_to_name = str.toOwnedSlice() catch |err| break :str_build err;
                    }) catch |err| {
                        std.log.err("Failed to build string for file name. Error: {}", .{err});
                        str.deinit();
                        break :paste;
                    };
                }

                break :copy_to_name copy_to_name;
            };
            defer if (alloced) self.ally.free(copy_to_name);

            std.log.info("Pasted {s} to {s}{c}{s}", .{ copy_path, self.path.items, std.fs.path.sep, copy_to_name });

            if (std.fs.Dir.copyFile(std.fs.cwd(), copy_path, self.dir, copy_to_name, .{})) {
                if (self.cutting) {
                    std.fs.Dir.deleteFile(std.fs.cwd(), copy_path) catch |err| {
                        std.log.err("Failed to delete cut file. Error: {}", .{err});
                        // we can still continue appending the file to our list
                    };
                }

                self.files.append(self.ally, File.init(self.ally, self.dir, .{
                    .name = copy_to_name,
                    .kind = .file,
                })) catch |e| {
                    std.log.err("Failed to append newly copied file to list, try refreshing (ctrl+r). Error: {}", .{e});
                    break :paste;
                };
            } else |e| {
                std.log.err("Failed to copy file. Error: {}", .{e});
                break :paste;
            }

            searchbarSort(self.files.items, self.search_bar.str.items);
        } else if (rl.IsKeyPressed(.r)) {
            self.refresh();
            self.resetTitlePath();
        } else if (rl.IsKeyPressed(.delete)) delete: {
            const selected = self.files.items[self.selected_file];
            const file_name = selected.getName() orelse {
                std.log.err("Could not delete {}, the name of the file is wrong due to OOM, try refreshing (ctrl+r)", .{selected.name});
                break :delete;
            };

            const realpath = self.dir.realpathAlloc(self.ally, file_name) catch |err| {
                std.log.err("Failed getting realpath for file {s}. Error: {}", .{ file_name, err });
                break :delete;
            };
            defer self.ally.free(realpath);

            // IWOMM: https://docs.gtk.org/gio/method.File.trash.html
            spawnIn(self.ally, self.dir, &.{ "gio", "trash", realpath });

            const file = self.files.orderedRemove(self.selected_file);
            file.deinit(self.ally);
            self.selected_file -|= 1;
        } else if (rl.IsKeyPressed(.t)) {
            // IWOMM: Replace with open default terminal for OS
            spawnIn(self.ally, self.dir, &.{"ghostty"});
        } else if (rl.IsKeyPressed(.grave)) {
            self.display_mode = switch (self.display_mode) {
                .tile => .list,
                .list => .tile,
            };
            self.refresh();
        } else if (rl.IsKeyPressed(.n)) {
            self.special_action = .create_file;
            self.special_action_textbox.clear();
            return;
        } else if (rl.IsKeyPressed(.semicolon)) {
            self.special_action = .run_command;
            self.special_action_textbox.clear();
            return;
        } else if (rl.IsKeyPressed(.left_bracket)) {
            // IWOMM: Replace with config file for keybinds
            spawnIn(self.ally, self.dir, &.{ "ghostty", "-e", "nvim.appimage" });
        }
    }

    if (rl.IsKeyPressed(.escape)) {
        self.selected_file = 0;
        self.search_bar.clear();
        defaultSort(self.files.items);
    } else if ((rl.IsKeyPressed(.enter) and (rl.IsKeyDown(.left_shift) or rl.IsKeyDown(.left_control))) or
        (self.display_mode == .list and h.modPressed(.left_control, .h)) or
        h.modPressed(.left_control, .o))
    {
        if (self.switchDirToOrLog("..", "Cannot open parent dir. Error: {}", .{})) {
            if (std.fs.path.dirname(self.path.items)) |dirname| {
                self.path.items.len = dirname.len;
            }
            self.search_bar.clear();
            self.selected_file = 0;
        }
    } else if (rl.IsKeyPressed(.enter) or
        (self.display_mode == .list and h.modPressed(.left_control, .l)) or
        h.modPressed(.left_control, .i))
    open: {
        const selected_file = self.selected_file;
        self.selected_file = 0;

        if (self.search_bar.str.items.len == 1 and self.search_bar.str.items[0] == '~') {
            const home_path_str = home_path orelse {
                std.log.err("Your system doesn't have a recognized home directory", .{});
                break :open;
            };

            if (self.switchDirToOrLog(home_path_str, "Cannot open home dir. Error: {}", .{})) {
                self.search_bar.clear();
                self.resetTitlePath();
            }

            break :open;
        }

        if (self.files.items.len == 0) break :open;

        const selected: File = self.files.items[selected_file];

        const name = selected.getName() orelse {
            std.log.err("Cannot open file/dir {}, the name of the file is wrong due to OOM, try refreshing (ctrl+r)", .{selected.name});
            break :open;
        };

        self.search_bar.clear();

        switch (selected.type) {
            .dir => {
                self.path.writer(self.ally).print(std.fs.path.sep_str ++ "{s}", .{name}) catch |err| {
                    std.log.err("Couldn't list full path for directory. Error: {}", .{err});
                };

                if (!self.switchDirToOrLog(name, "Cannot open dir {}. Error: {}", .{selected.name})) {
                    if (std.fs.path.dirname(self.path.items)) |dirname| {
                        self.path.items.len = dirname.len;
                    }
                }
            },
            .exe => exe: {
                // ... do i really have to alloc print just to prepend `./`? :(
                const arg = std.fmt.allocPrint(self.ally, "./{s}", .{name}) catch |err| {
                    std.log.err("Cannot start executable {s}, ran into OOM: {}", .{ name, err });
                    break :exe;
                };
                defer self.ally.free(arg);

                spawnIn(self.ally, self.dir, &.{arg});
            },
            else => {
                spawnIn(self.ally, self.dir, &.{ "xdg-open", name });
                defaultSort(self.files.items);
            },
        }
    }

    self.scroll = scroll: {
        if (self.files.items.len == 0) break :scroll 0;

        const min_height = 100;
        const max_height = rl.GetScreenHeight() - 100;
        const selected_y_global: c_int = @intCast(68 + self.selected_file * 24);
        const selected_y_local = selected_y_global + self.scroll;

        if (selected_y_local > max_height) {
            break :scroll max_height - selected_y_global;
        } else if (selected_y_local < min_height) {
            break :scroll @min(0, min_height - selected_y_global);
        }

        break :scroll self.scroll;
    };
}

pub fn draw(self: Tab, rl_text_writer: *rl.DrawTextWriter, rl_writer: anytype, font: rl.Font) void {
    const width = rl.GetScreenWidth();
    const height_u = rl.GetScreenHeightU();

    switch (self.display_mode) {
        .list => {
            if (self.files.items.len > 0)
                rl.DrawRectangle(5, self.scroll + @as(c_int, @intCast(68 + self.selected_file * 24)), width - 10, 24, rl.Color.white.alpha(0.1));

            rl_text_writer.offset.y = @floatFromInt(self.scroll);

            for (self.files.items, 0..) |file, i| {
                rl_text_writer.tint = if (file.score == 0) rl.Color.gray else color.text;
                rl_writer.print("{}\n", .{file.name}) catch unreachable;

                rl.DrawRectangle(5, self.scroll + @as(c_int, @intCast(68 + i * 24)), 20, 20, if (file.score == 0) rl.Color.gray else switch (file.type) {
                    .dir => rl.Color.blue,
                    .exe => rl.Color.yellow,
                    else => rl.Color.white,
                });
            }
        },
        .tile => {
            const tiles_per_row = tilesPerRow();

            if (self.files.items.len > 0) {
                const x, const y, const size = self.tilePos(tiles_per_row, self.selected_file);
                rl.DrawRectangleRec(.{ .x = x, .y = y, .width = size, .height = size }, rl.Color.white.alpha(0.1));
            }

            for (self.files.items, 0..) |file, i| {
                const x, const y, const size = self.tilePos(tiles_per_row, i);
                var name = file.name.get();

                var buf: [10]u8 = undefined;
                if (name.len > buf.len) {
                    @memcpy(buf[0 .. buf.len - 3], name[0 .. buf.len - 3]);
                    @memcpy(buf[buf.len - 3 ..], "...");
                    name = &buf;
                }

                const len = rl.MeasureTextSliceEx(font, name, 24, 0);

                rl.DrawTextSliceEx(font, name[0..@min(name.len, 12)], .{
                    .x = x + tile_size / 2 - len.x / 2,
                    .y = y + tile_size - 24,
                }, 24, 0, color.text);

                if (file.preview.id == 0) {
                    rl.DrawRectangleLinesEx(.{
                        .x = x + 31 / 2,
                        .y = y + 5,
                        .width = size - 31,
                        .height = size - 31,
                    }, 1, if (file.score == 0) rl.Color.gray else switch (file.type) {
                        .dir => .blue,
                        .exe => .yellow,
                        else => .white,
                    });
                } else {
                    const width_f: f32 = @floatFromInt(file.preview.width);
                    const height_f: f32 = @floatFromInt(file.preview.height);
                    const scale_f: f32 = (tile_size - 31) / @max(width_f, height_f);

                    var x_off: f32 = 0;
                    var y_off: f32 = 0;
                    if (width_f > height_f) {
                        y_off = ((tile_size - 31) / 2) - (height_f * scale_f / 2);
                    } else {
                        x_off = ((tile_size - 31) / 2) - (width_f * scale_f / 2);
                    }

                    file.preview.drawEx(.{
                        .x = x + x_off + 31 / 2,
                        .y = y + y_off + 5,
                    }, 0, scale_f, .white);
                }
            }
        },
    }

    rl.DrawRectangle(0, 0, width, 68, color.bg);
    rl.DrawTextSliceEx(font, self.path.items, .init(10, 7), 24, 0, color.text);

    self.search_bar.draw(font, 24, .init(10, 39, @floatFromInt(width - 20), 24));

    if (self.special_action != .none) {
        const dialogue_x = 50;
        const dialogue_height = 30;

        const dialogue_y: f32 = @floatFromInt(height_u / 2 - @divFloor(dialogue_height, 2));
        const dialogue_width: f32 = @floatFromInt(width - 100);

        h.drawRoundedBox(rl.Rectangle.init(dialogue_x - 5, dialogue_y - 34, dialogue_width + 10, dialogue_height + 39));

        rl.DrawTextSliceEx(font, switch (self.special_action) {
            .create_file => "Enter new file name:",
            .run_command => "Enter command:",
            .none => unreachable,
        }, .{ .x = dialogue_x + 5, .y = dialogue_y - 29 }, 24, 0, color.text);
        self.special_action_textbox.draw(font, 24, .init(dialogue_x, dialogue_y, dialogue_width, 24));
    }
}

const tile_size = 100;
const tile_spacing = 10;

fn tilesPerRow() u16 {
    const width_u: c_uint = rl.GetScreenWidthU();
    return @truncate(@min(std.math.maxInt(u16), width_u / (tile_size + tile_spacing)));
}

fn tilePos(self: Tab, tiles_per_row: u16, idx: usize) [3]f32 {
    return .{
        tile_spacing + @as(f32, @floatFromInt((idx % tiles_per_row) * (tile_size + tile_spacing))),
        @as(f32, @floatFromInt(self.scroll)) + 68 + @as(f32, @floatFromInt((idx / tiles_per_row) * (tile_size + tile_spacing))),
        tile_size,
    };
}

fn refresh(self: *Tab) void {
    self.unloadFiles();

    self.readDir(self.dir, &self.files) catch |err| {
        std.log.err("Failed to refresh dir. Error: {}", .{err});
    };
    searchbarSort(self.files.items, self.search_bar.str.items);
}

fn resetTitlePath(self: *Tab) void {
    const full_path = self.dir.realpathAlloc(self.ally, ".") catch |err| {
        std.log.err("Failed to refresh full path text. Error: {}", .{err});
        return;
    };
    self.path.deinit(self.ally);
    self.path = std.ArrayListUnmanaged(u8).fromOwnedSlice(full_path);
}

fn switchDirToOrLog(self: *Tab, path: []const u8, comptime err_fmt: []const u8, args: anytype) bool {
    const inner = self.dir.openDir(path, .{ .iterate = true }) catch |err| {
        std.log.err(err_fmt, args ++ .{err});
        return false;
    };

    self.switchDirTo(inner);
    return true;
}

fn switchDirTo(self: *Tab, dir: std.fs.Dir) void {
    var files: std.ArrayListUnmanaged(File) = .{};

    self.readDir(dir, &files) catch |err| {
        std.log.err("Couldn't read dir, error: {}", .{err});
        files.deinit(self.ally);
        return;
    };

    self.dir.close();
    self.dir = dir;

    for (self.files.items) |file| file.name.deinit(self.ally);
    self.files.deinit(self.ally);

    self.files = files;
}

fn readDir(self: *Tab, dir: std.fs.Dir, files: *std.ArrayListUnmanaged(File)) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var file = File.init(self.ally, dir, entry);
        errdefer file.deinit(self.ally);

        if (file.type == .image and self.display_mode == .tile) load_preview: {
            try self.path.append(self.ally, 0);
            if (!rl.ChangeDirectory(@ptrCast(self.path.items.ptr))) {
                std.log.err("Failed to change directory for previews", .{});
                break :load_preview;
            }
            _ = self.path.pop();

            const name = try self.ally.dupeZ(u8, entry.name);
            defer self.ally.free(name);

            file.preview = rl.Texture.init(name);
        }

        files.append(self.ally, file) catch |err| {
            std.log.err("Failed to append file {s}. Error: {}", .{ entry.name, err });
            file.name.deinit(self.ally);
        };
    }

    defaultSort(files.items);
}

fn unloadFiles(self: *Tab) void {
    for (self.files.items) |file| file.deinit(self.ally);
    self.files.clearRetainingCapacity();
}

fn defaultSort(files: []File) void {
    for (files) |*file| {
        file.score = if (file.name.at(0) == '.') 0 else if (file.type == .dir) 1 else 0.5;
    }
    std.sort.block(File, files, {}, struct {
        fn f(_: void, lhs: File, rhs: File) bool {
            return std.ascii.toLower(lhs.name.at(0)) < std.ascii.toLower(rhs.name.at(0));
        }
    }.f);
    std.sort.block(File, files, {}, struct {
        fn f(_: void, lhs: File, rhs: File) bool {
            return lhs.score > rhs.score;
        }
    }.f);
}

fn searchbarSort(files: []File, search_bar_text: []const u8) void {
    if (search_bar_text.len == 0) {
        defaultSort(files);
        return;
    }

    if (search_bar_text[0] == '/') return;

    for (files) |*file| {
        file.score = if (file.name.at(0) == '.' and search_bar_text[0] != '.') 0 else fuzz.score(search_bar_text, file.name.get());
    }
    std.sort.pdq(File, files, {}, struct {
        fn f(_: void, lhs: File, rhs: File) bool {
            return lhs.score > rhs.score;
        }
    }.f);
}

const File = struct {
    name: Str,
    type: Type,
    score: f32 = 1,
    preview: rl.Texture = .{},

    corrupted_name: bool,

    pub fn init(ally: std.mem.Allocator, dir: std.fs.Dir, entry: std.fs.Dir.Entry) File {
        const name: Str = Str.dupeOrStack(ally, entry.name);

        return .{
            .name = name,
            .type = switch (entry.kind) {
                .file => file: {
                    const exten = std.fs.path.extension(entry.name);

                    if (exten.len == 0) is_exe: {
                        const file = dir.openFile(entry.name, .{}) catch |err| {
                            std.log.err("Cannot open {s} to check if it is executable. You won't be able to execute it. Error: {}", .{ entry.name, err });
                            break :is_exe;
                        };

                        const stat = file.stat() catch |err| {
                            std.log.err("Cannot stat {s} to check if it is executable. You won't be able to execute it. Error: {}", .{ entry.name, err });
                            break :is_exe;
                        };

                        if (stat.mode & std.c.S.IXUSR != 0) {
                            break :file .exe;
                        }
                    }

                    if (extension_map.get(exten)) |t| break :file t;
                    if (source_file_extensions.has(exten)) break :file .source_file;

                    break :file .other;
                },
                .directory => .dir,
                else => .other,
            },
            // we ran into OOM while copying over the name, don't try any
            // operations on this file
            .corrupted_name = name == .stack and entry.name.len > Str.stack_len - 1,
        };
    }

    pub fn deinit(self: File, ally: std.mem.Allocator) void {
        self.name.deinit(ally);
        self.preview.deinit();
    }

    pub fn getName(self: File) ?[]const u8 {
        if (self.corrupted_name) return null;
        return self.name.get();
    }

    const Type = enum {
        dir,
        text,
        markdown,
        source_file,
        image,
        video,
        exe,
        other,
    };
};

const Str = union(enum) {
    heap: []const u8,
    static: []const u8,
    stack: [stack_len]u8,

    comptime {
        std.debug.assert(@sizeOf([stack_len]u8) == @sizeOf([]const u8));
    }

    const stack_len = @bitSizeOf([]const u8) / 8;

    pub fn get(self: *const Str) []const u8 {
        return switch (self.*) {
            .stack => |*s| std.mem.sliceTo(s, 0),
            inline else => |v| v,
        };
    }

    pub fn at(self: Str, idx: usize) u8 {
        return switch (self) {
            inline else => |v| v[idx],
        };
    }

    pub fn deinit(self: Str, ally: std.mem.Allocator) void {
        if (self == .heap) {
            ally.free(self.heap);
        }
    }

    pub fn dupeOrStack(ally: std.mem.Allocator, str: []const u8) Str {
        return .{ .heap = ally.dupe(u8, str) catch {
            var out: Str = .{ .stack = undefined };

            const len = @min(str.len, stack_len - 1);
            @memcpy(out.stack[0..len], str[0..len]);
            out.stack[len] = 0;

            return out;
        } };
    }

    pub fn format(value: Str, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{value.get()});
    }
};

fn spawnIn(ally: std.mem.Allocator, dir: std.fs.Dir, argv: []const []const u8) void {
    var child = std.process.Child.init(argv, ally);
    child.cwd_dir = dir;
    child.stdout_behavior = .Ignore;
    child.stdin_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch |err| {
        std.log.err("Failed to spawn process {s}. Error: {}", .{ argv, err });
    };
}

const extension_map = std.StaticStringMap(Tab.File.Type).initComptime(.{
    .{ ".txt", .text },
    .{ ".md", .markdown },
    .{ ".png", .image },
    .{ ".jpg", .image },
    .{ ".jpeg", .image },
    .{ ".webp", .image },
    .{ ".qoi", .image },
    .{ ".gif", .image },
    .{ ".mp4", .video },
    .{ ".mov", .video },
    .{ ".exe", .exe },
});

const source_file_extensions = std.StaticStringMap(void).initComptime(.{
    .{".zig"},
    .{".c"},
    .{".cpp"},
    .{".rs"},
    .{".go"},
    .{".lua"},
    .{".cs"},
    .{".java"},
    .{".js"},
});
