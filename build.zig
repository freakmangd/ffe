const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opts = b.addOptions();
    opts.addOption(?u32, "allocs", b.option(u32, "allocs", "Number of allocations before OOM") orelse null);

    const exe = b.addExecutable(.{
        .name = "ffe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("opts", opts.createModule());
    b.installArtifact(exe);

    const font = b.createModule(.{
        .root_source_file = b.path("assets/FiraSans-Regular.otf"),
    });
    exe.root_module.addImport("font", font);

    const icon = b.createModule(.{
        .root_source_file = b.path("assets/com.freakmangd.ffe_512.png"),
    });
    exe.root_module.addImport("icon", icon);

    b.installFile("assets/com.freakmangd.ffe.desktop", "share/applications/com.freakmangd.ffe.desktop");

    b.installFile("assets/com.freakmangd.ffe_512.png", "share/icons/hicolor/512x512/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_512.png", "share/icons/hicolor/256x156@2/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_256.png", "share/icons/hicolor/256x256/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_256.png", "share/icons/hicolor/128x128@2/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_128.png", "share/icons/hicolor/128x128/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_64.png", "share/icons/hicolor/32x32@2/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_32.png", "share/icons/hicolor/32x32/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_32.png", "share/icons/hicolor/16x16@2/apps/com.freakmangd.ffe.png");
    b.installFile("assets/com.freakmangd.ffe_16.png", "share/icons/hicolor/16x16/apps/com.freakmangd.ffe.png");

    const rd = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("raylib", rd.module("root"));

    const raylib = rd.artifact("raylib");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_BMP", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_TGA", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_JPG", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_PSD", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_HDR", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_PIC", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_KTX", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_ASTC", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_PKM", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_PVR", "1");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_SVG", "1");

    exe.linkLibrary(rd.artifact("raylib"));

    const kfd = b.dependency("known_folders", .{});
    exe.root_module.addImport("kf", kfd.module("known-folders"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_check = b.addExecutable(.{
        .name = "check-ffe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_check.root_module.addImport("opts", opts.createModule());
    exe_check.root_module.addImport("raylib", rd.module("root"));
    exe_check.linkLibrary(rd.artifact("raylib"));
    exe_check.root_module.addImport("kf", kfd.module("known-folders"));
    exe_check.root_module.addImport("font", font);
    exe_check.root_module.addImport("icon", icon);

    const check_step = b.step("check", "Run the app");
    check_step.dependOn(&exe_check.step);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
