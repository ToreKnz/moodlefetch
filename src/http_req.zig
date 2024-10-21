const std = @import("std");
const HttpClient = @import("tls12");

pub fn urlRequest(allocator: std.mem.Allocator, url: []const u8) !std.ArrayList(u8) {
    var client = HttpClient{ .allocator = allocator };
    defer client.deinit();
    try client.initDefaultProxies(allocator);
    const uri = try std.Uri.parse(url);
    var server_header_buffer: [1024 * 1024]u8 = undefined;
    var req = try HttpClient.open(&client, .GET, uri, .{
        .server_header_buffer = &server_header_buffer,
        .redirect_behavior = @enumFromInt(10),
    });
    defer req.deinit();
    try req.send();
    try req.wait();
    var body = std.ArrayList(u8).initCapacity(allocator, 50*1024*1024) catch unreachable;
    try req.reader().readAllArrayList(&body, 50 * 1024 * 1024);
    return body;
}
