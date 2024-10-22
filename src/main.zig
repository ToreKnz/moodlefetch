const std = @import("std");
const moodle_processing = @import("moodle_processing.zig");
const config = @import("config.zig");
const terminal = @import("terminal.zig");
const http_req = @import("http_req.zig");
const builtin = @import("builtin");

const UTF8ConsoleOutput = struct {
    original: c_uint = undefined,
    fn init() UTF8ConsoleOutput {
        var self = UTF8ConsoleOutput{};
        if (comptime builtin.os.tag == .windows) {
            const kernel32 = std.os.windows.kernel32;
            self.original = kernel32.GetConsoleOutputCP();
            _ = kernel32.SetConsoleOutputCP(65001);
        }
        return self;
    }
    fn deinit(self: *UTF8ConsoleOutput) void {
        if (comptime builtin.os.tag == .windows) {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(self.original);
        }
    }
};

pub fn main() !void {
    var cp_out = UTF8ConsoleOutput.init();
    defer cp_out.deinit();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var conf: config.MoodleConfig = undefined;
    const config_read = config.getConfig(allocator);

    if (config_read) |data| {
        conf = data.value.clone(allocator);
        data.deinit();
        std.debug.print("Config read successfully!\n", .{});
    } else |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            const token = terminal.promptUser(allocator, "No configuration file found, please enter your Moodle token!\n") catch |e| {
                std.debug.print("Error occured: {!}\n", .{e});
                return;
            };
            defer allocator.free(token);
            const sub_folders = try terminal.promptUserForBoolYN(allocator, "Do you want to have subfolders for every group for every sheet (which might create many folders)? (y/n)");
            conf = config.createNewConfig(allocator, token, sub_folders);
        } else {
            std.debug.print("Could not read config\n", .{});
            const new_config = terminal.promptUserForBoolYN(allocator, "Do you want to overwrite your config with a new one? All config data will be lost. (y/n)") catch |e| {
                std.debug.print("Error occured: {!}\n", .{e});
                return;
            };
            if (new_config) {
                const token = terminal.promptUser(allocator, "Please enter your Moodle token!\n") catch |e| {
                    std.debug.print("Error occured: {!}\n", .{e});
                    return;
                };
                const sub_folders = try terminal.promptUserForBoolYN(allocator, "Do you want to have subfolders for every group for every sheet (which might create many folders)? (y/n)");
                conf = config.createNewConfig(allocator, token, sub_folders);
            } else {
                std.debug.print("Fix your configuration file and try again!", .{});
                return;
            }
        }
    }
    defer conf.deinit(allocator);
    const options = conf.getCourseOptions(allocator);
    defer {
        for (0.., options) |idx, _| {
            allocator.free(options[idx]);
        }
        allocator.free(options);
    }
    const choice = terminal.getUserChoice(allocator, options) catch |e| {
        std.debug.print("Error occured: {!}\n", .{e});
        return;
    };
    std.debug.print("Chosen option: {}\n", .{choice + 1});
    if (choice < conf.moodle_courses.len) {
        moodle_processing.getSubmissions(allocator, &conf, conf.moodle_courses[choice].moodle_course_id) catch |err| {
            std.debug.print("Error fetching submissions: {!}\n", .{err});
        };
    } else {
        const course_id = terminal.promptUser(allocator, "Please input a moodle course id!") catch |e| {
            std.debug.print("Error occured: {!}\n", .{e});
            return;
        };
        defer allocator.free(course_id);
        moodle_processing.getSubmissions(allocator, &conf, course_id) catch |err| {
            std.debug.print("Error fetching submissions: {!}\n", .{err});
        };
    }
    std.debug.print("Writing config to file!\n", .{});
    config.writeConfigToFile(conf) catch |e| {
        std.debug.print("Error occured: {!}\n", .{e});
    };
}
