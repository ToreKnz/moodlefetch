const std = @import("std");

pub const MoodleConfig = struct {
    moodle_token: []u8,
    moodle_courses: []CourseConfigData,
    make_subfolders_for_groups: bool,

    pub fn getCourseOptions(self: MoodleConfig, allocator: std.mem.Allocator) [][]u8 {
        var options = allocator.alloc([]u8, self.moodle_courses.len + 1) catch unreachable;
        for (0.., self.moodle_courses) |idx, course_data| {
            const option = allocator.dupe(u8, course_data.moodle_course_name) catch unreachable;
            options[idx] = option;
        }
        options[options.len - 1] = std.fmt.allocPrint(allocator, "Add new course to list", .{}) catch unreachable;
        return options;
    }

    pub fn clone(self: MoodleConfig, allocator: std.mem.Allocator) MoodleConfig {
        const token = allocator.dupe(u8, self.moodle_token) catch unreachable;
        const courses = allocator.alloc(CourseConfigData, self.moodle_courses.len) catch unreachable;
        for (0.., self.moodle_courses) |idx, c| {
            const new_course = CourseConfigData{
                .moodle_course_id = allocator.dupe(u8, c.moodle_course_id) catch unreachable,
                .moodle_course_name = allocator.dupe(u8, c.moodle_course_name) catch unreachable,
            };
            courses[idx] = new_course;
        }
        return MoodleConfig{ .moodle_token = token, .moodle_courses = courses, .make_subfolders_for_groups = self.make_subfolders_for_groups};
    }

    pub fn deinit(self: MoodleConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.moodle_token);
        for (self.moodle_courses) |course| {
            course.deinit(allocator);
        }
        allocator.free(self.moodle_courses);
    }

    pub fn containsCourseId(self: MoodleConfig, course_id: []const u8) bool {
        for (self.moodle_courses) |c| {
            if (std.mem.eql(u8, c.moodle_course_id, course_id)) return true;
        }
        return false;
    }

    pub fn addCourse(self: *MoodleConfig, allocator: std.mem.Allocator, id: []const u8, name: []const u8) void {
        const new_course = CourseConfigData.init(allocator, id, name);
        var courses = allocator.alloc(CourseConfigData, self.moodle_courses.len + 1) catch unreachable;
        for (0.., self.moodle_courses) |idx, c| {
            courses[idx] = c;
        }
        courses[courses.len - 1] = new_course;
        allocator.free(self.moodle_courses);
        self.moodle_courses = courses;
    }
};

pub const CourseConfigData = struct {
    moodle_course_id: []u8,
    moodle_course_name: []u8,

    pub fn deinit(self: CourseConfigData, allocator: std.mem.Allocator) void {
        allocator.free(self.moodle_course_id);
        allocator.free(self.moodle_course_name);
    }

    pub fn init(allocator: std.mem.Allocator, id: []const u8, name: []const u8) CourseConfigData {
        const course_id = allocator.dupe(u8, id) catch unreachable;
        const course_name = allocator.dupe(u8, name) catch unreachable;
        return CourseConfigData{ .moodle_course_id = course_id, .moodle_course_name = course_name };
    }
};

pub fn getConfig(allocator: std.mem.Allocator) !std.json.Parsed(MoodleConfig) {
    const cd = std.fs.cwd();
    const config_file = try cd.openFile("CONFIG", .{});
    const read_slice = try config_file.readToEndAlloc(allocator, 5 * 1024 * 1024);
    defer allocator.free(read_slice);
    const config = try std.json.parseFromSlice(MoodleConfig, allocator, read_slice, .{});
    return config;
}

pub fn writeConfigToFile(config: MoodleConfig) !void {
    const cd = std.fs.cwd();
    var config_file = try cd.createFile("CONFIG", .{});
    try std.json.stringify(config, .{}, config_file.writer());
}

pub fn createNewConfig(allocator: std.mem.Allocator, token: []const u8, sub_folders: bool) MoodleConfig {
    const moodle_token = allocator.dupe(u8, token) catch unreachable;
    const moodle_courses = allocator.alloc(CourseConfigData, 0) catch unreachable;
    const new_config = MoodleConfig{ .moodle_token = moodle_token, .moodle_courses = moodle_courses, .make_subfolders_for_groups = sub_folders};
    return new_config;
}
