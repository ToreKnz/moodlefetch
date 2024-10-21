const std = @import("std");
pub const Url = struct {
    url: []u8,
    contains_query: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) Url {
        const url_string = std.fmt.allocPrint(allocator, "{s}", .{url}) catch unreachable;
        return Url{ .url = url_string, .contains_query = false, .allocator = allocator };
    }

    pub fn deinit(self: *Url) void {
        self.allocator.free(self.url);
    }

    pub fn addQuery(self: *Url, option_name: []const u8, value_name: []const u8) void {
        const delim: u8 = if (self.contains_query) '&' else '?';
        const new_url = std.fmt.allocPrint(self.allocator, "{s}{c}{s}={s}", .{ self.url, delim, option_name, value_name }) catch unreachable;
        self.allocator.free(self.url);
        self.url = new_url;
        self.contains_query = true;
    }

    pub fn getString(self: Url) []const u8 {
        return self.url;
    }
};
