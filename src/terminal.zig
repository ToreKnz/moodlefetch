const std = @import("std");

pub fn promptUser(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    std.debug.print("{s}\n", .{text});
    std.debug.print("> ", .{});
    const stdin = std.io.getStdIn().reader();
    const user_input = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024) orelse unreachable;
    defer allocator.free(user_input);
    const trimmed = std.mem.trim(u8, user_input, "\t\n\r ");
    const trimmed_user_input = allocator.dupe(u8, trimmed) catch unreachable;
    return trimmed_user_input;
}

pub fn promptUserForNumber(allocator: std.mem.Allocator, text: []const u8) !u32 {
    const input = try promptUser(allocator, text);
    defer allocator.free(input);
    const num = try std.fmt.parseInt(u32, input, 10);
    return num;
}

pub fn promptUserForBoolYN(allocator: std.mem.Allocator, text: []const u8) !bool {
    const input = try promptUser(allocator, text);
    const trimmed_input = std.mem.trimLeft(u8, input, " \n\r\t");
    defer allocator.free(input);
    if (trimmed_input.len > 0) {
        if (trimmed_input[0] == 'y' or trimmed_input[0] == 'Y') {
            return true;
        }
        if (trimmed_input[0] == 'n' or trimmed_input[0] == 'N') {
            return false;
        }
        std.debug.print("Invalid value, please try again.", .{});
    } else {
        std.debug.print("No input found, please try again.", .{});
    }
    return promptUserForBoolYN(allocator, text);
}

pub fn getUserChoice(allocator: std.mem.Allocator, options: []const []const u8) !u32 {
    std.debug.print("\n", .{});
    for (0.., options) |i, option| {
        std.debug.print("({}) {s}\n", .{ i + 1, option });
    }
    const num = promptUserForNumber(allocator, "Select a row!");
    if (num) |n| {
        if (n <= 0 or n > options.len) {
            std.debug.print("Number out of range!\n", .{});
            return error.NumberOutOfRange;
        }
        return n - 1;
    } else |err| {
        std.debug.print("Error returning number!\n", .{});
        return err;
    }
}
