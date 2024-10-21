const std = @import("std");
const urlquery = @import("urlquery.zig");
const Url = urlquery.Url;
const config = @import("config.zig");
const terminal = @import("terminal.zig");
const http_req = @import("http_req.zig");

const moodle_base_link = "https://moodle.rwth-aachen.de/webservice/rest/server.php";

const AssignmentResponse = struct {
    courses: []Course,
};

const Course = struct {
    id: u32,
    shortname: []const u8,
    assignments: []Assignment,

    fn debug_print(self: Course) void {
        std.debug.print("course name: {s}\n", .{self.shortname});
        for (self.assignments) |assign| {
            std.debug.print("id: {} name: {s}\n", .{ assign.id, assign.name });
        }
    }
};

const Assignment = struct {
    id: u32,
    name: []const u8,
};

const AssignmentData = struct {
    id: u32,
    name: []u8,

    fn deinit(self: AssignmentData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    fn fromAssignment(assignment: Assignment, allocator: std.mem.Allocator) AssignmentData {
        return AssignmentData{ .id = assignment.id, .name = allocator.dupe(u8, assignment.name) catch unreachable };
    }

    fn getSheetNumberByNameOrUser(self: AssignmentData, allocator: std.mem.Allocator) !u32 {
        var splits = std.mem.split(u8, self.name, " ");
        while (splits.next()) |split| {
            const num_parse = std.fmt.parseInt(u32, split, 10);
            if (num_parse) |value| {
                return value;
            } else |_| {}
        } 
        const num = try terminal.promptUserForNumber(allocator, "Sheet number could not be inferred from name, please input the number of the sheet manually (for file naming)!");
        return num;
    }
};

pub fn getAssignmentIds(allocator: std.mem.Allocator, conf: *config.MoodleConfig, course_id: []const u8) !std.ArrayList(AssignmentData) {
    std.debug.print("Fetching assignment data from moodle...\n", .{});
    var url = Url.init(allocator, moodle_base_link);
    defer url.deinit();
    url.addQuery("moodlewsrestformat", "json");
    url.addQuery("wsfunction", "mod_assign_get_assignments");
    url.addQuery("courseids[0]", course_id);
    url.addQuery("wstoken", conf.moodle_token);
    const response_body = http_req.urlRequest(allocator, url.getString()) catch |err| {
        std.debug.print("Error getting moodle response for course: {s}\n", .{course_id});
        return err;
    };
    defer response_body.deinit();

    const parsed = std.json.parseFromSlice(AssignmentResponse, allocator, response_body.items, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print("Error parsing moodle response: {!}\n", .{err});
        return err;
    };
    defer parsed.deinit();

    if (parsed.value.courses.len == 0) return error.NoMatchingCourseFound;
    if (parsed.value.courses.len > 1) return error.MultipleCoursesFound;
    const course = parsed.value.courses[0];

    var assignments = std.ArrayList(AssignmentData).init(allocator);
    for (course.assignments) |assign| {
        const data = AssignmentData.fromAssignment(assign, allocator);
        assignments.append(data) catch unreachable;
    }
    if (!conf.containsCourseId(course_id)) {
        const id_string = std.fmt.allocPrint(allocator, "{}", .{course.id}) catch unreachable;
        defer allocator.free(id_string);
        std.debug.print("Adding course to config:\n  id: {}\n  name:{s}!\n", .{ course.id, course.shortname });
        conf.addCourse(allocator, id_string, course.shortname);
    }
    return assignments;
}

const SubmissionResponse = struct {
    assignments: []SubmissionData,
};

const SubmissionData = struct {
    assignmentid: u32,
    submissions: []Submission,
};

const Submission = struct {
    id: u32,
    status: []const u8,
    groupid: u32,
    plugins: []Plugin,
    timemodified: u64,

    fn download(self: Submission, allocator: std.mem.Allocator, groupid_mapping: std.AutoHashMap(u32, u32), base_dir: std.fs.Dir, moodle_config: config.MoodleConfig, sheet_num: u32) !void {
        for (self.plugins) |plugin| {
            if (plugin.fileareas != null) {
                const fileareas = plugin.fileareas orelse unreachable;
                const groupnumber = groupid_mapping.get(self.groupid) orelse return error.GroupIdNotFound;
                var dir = base_dir;
                if (moodle_config.make_subfolders_for_groups) {
                    const sub_path = std.fmt.allocPrint(allocator, "Group{}", .{groupnumber}) catch unreachable;
                    defer allocator.free(sub_path);
                    const sub_dir = base_dir.openDir(sub_path, .{});
                    if (sub_dir) |_| {
                        std.debug.print("Directory {s} already exists! Skipping this element.\n", .{sub_path});
                        return;
                    } else |_| {}
                    const new_dir_try = base_dir.makeDir(sub_path);
                    if (std.meta.isError(new_dir_try)) {
                        std.debug.print("Failed to create directory, aborting: {!}\n", .{new_dir_try});
                        return;
                    }
                    const new_dir = try base_dir.openDir(sub_path, .{});
                    dir = new_dir;
                }
                defer {
                    if (moodle_config.make_subfolders_for_groups) {
                        dir.close();
                    }
                }

                var seen_file_endings = std.StringHashMap(u32).init(allocator);
                defer seen_file_endings.deinit();

                for (fileareas) |filedata| {
                    for (filedata.files) |file| {
                        const file_ending = try file.getFileEnding();
                        const amt_seen = seen_file_endings.get(file_ending) orelse 0;
                        const postfix = if (amt_seen == 0) std.fmt.allocPrint(allocator, "", .{}) catch unreachable
                            else std.fmt.allocPrint(allocator, "-{}", .{amt_seen + 1}) catch unreachable;
                        seen_file_endings.put(file_ending, amt_seen + 1) catch unreachable;
                        defer allocator.free(postfix);
                        const file_name = std.fmt.allocPrint(allocator, "Group{:0>2}Sheet{:0>2}{s}{s}", .{groupnumber, sheet_num, postfix,file_ending}) catch unreachable;
                        defer allocator.free(file_name);
                        try file.download(allocator, dir, moodle_config, file_name);
                    }
                }
            }
        }
    }

    fn lessThan(_: void, first: Submission, second: Submission) bool {
        return first.timemodified < second.timemodified;
    }
};

const Plugin = struct {
    type: []const u8,
    name: []const u8,
    fileareas: ?[]FileData = null,
};

const FileData = struct {
    area: []const u8,
    files: []File,
};

const File = struct {
    filename: []const u8,
    fileurl: []const u8,

    fn download(self: File, allocator: std.mem.Allocator, directory: std.fs.Dir, moodle_config: config.MoodleConfig, file_name: []u8) !void {
        var url = Url.init(allocator, self.fileurl);
        url.addQuery("token", moodle_config.moodle_token);
        defer url.deinit();
        const download_data = http_req.urlRequest(allocator, url.getString()) catch return error.NoDownloadDataFound;
        defer download_data.deinit();
        const new_file = directory.createFile(file_name, .{});
        if (new_file) |file| {
            defer file.close();
            _ = try file.write(download_data.items);
        } else |err| {
            std.debug.print("Error creating file: {!}\n", .{err});
            return;
        }
    }

    fn getFileEnding(self: File) ![]const u8{
        const ending = std.mem.lastIndexOfScalar(u8, self.filename, '.');
        if (ending) |file_end| {
            return self.filename[file_end..];
        } else {
            return error.NoFileEndingFound;
        }
    }
};

pub fn getSubmissions(allocator: std.mem.Allocator, moodle_config: *config.MoodleConfig, course_id: []const u8) !void {
    const assignments = try getAssignmentIds(allocator, moodle_config, course_id);
    defer {
        for (assignments.items) |assign| {
            assign.deinit(allocator);
        }
        assignments.deinit();
    }
    std.debug.print("\n{} assignments found!\nChoose an assignment to download!\n", .{assignments.items.len});
    var options = allocator.alloc([]const u8, assignments.items.len + 1) catch unreachable;
    defer allocator.free(options);
    for (0.., assignments.items) |idx, assign| {
        options[idx] = assign.name;
    }
    options[options.len - 1] = "Cancel downloading";
    const choice = try terminal.getUserChoice(allocator, options);
    if (choice == options.len - 1) return;
    const chosen_assignment = assignments.items[choice];
    const id = chosen_assignment.id;
    const assignment_num = try chosen_assignment.getSheetNumberByNameOrUser(allocator);

    var mapping = try getGroupNumbers(allocator, moodle_config.*, course_id);
    defer mapping.deinit();
    const cd = std.fs.cwd();
    const sub_dir = cd.openDir(chosen_assignment.name, .{});
    if (sub_dir) |_| {
        std.debug.print("Directory {s} already exists! Skipping download. If you want to download anways, delete the old directory!\n", .{chosen_assignment.name});
        return;
    } else |_| {}

    var download_options = allocator.alloc([]const u8, 3) catch unreachable;
    defer allocator.free(download_options);
    download_options[0] = "Download all submissions";
    download_options[1] = "Download a range of submissions based on modification date";
    download_options[2] = "Cancel download";
    const download_choice = try terminal.getUserChoice(allocator, download_options);
    if (download_choice == 2) return;

    std.debug.print("Fetching submission data from moodle...\n", .{});
    var url = Url.init(allocator, moodle_base_link);
    defer url.deinit();
    url.addQuery("moodlewsrestformat", "json");
    url.addQuery("wsfunction", "mod_assign_get_submissions");
    var buffer: [10]u8 = undefined;
    url.addQuery("assignmentids[0]", try std.fmt.bufPrint(&buffer, "{}", .{id}));
    url.addQuery("wstoken", moodle_config.moodle_token);
    const submission_data = http_req.urlRequest(allocator, url.getString()) catch return error.SubmissionsNotFound;
    defer submission_data.deinit();
    const parsed = try std.json.parseFromSlice(SubmissionResponse, allocator, submission_data.items, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value.assignments.len <= 0) return error.NoSubmissionListFound;
    if (parsed.value.assignments.len > 1) return error.MoreThanOneSubmissionList;
    const submissions = parsed.value.assignments[0];

    var submission_list = submissions.submissions;
    if (download_choice == 1) {
        const first_num = try terminal.promptUserForNumber(allocator, "First group number:");
        const second_num = try terminal.promptUserForNumber(allocator, "Last group number:");

        std.mem.sort(Submission, submissions.submissions, {}, Submission.lessThan);
        var first_idx: ?usize = null;
        var second_idx: ?usize = null;
        for (0.., submissions.submissions) |i, sub| {
            if (sub.groupid != 0) {
                const group_num = mapping.get(sub.groupid) orelse return error.GroupIdNotFound;
                if (first_num == group_num) first_idx = i;
                if (second_num == group_num) second_idx = i;
            }
        }
        if (first_idx == null) {
            std.debug.print("No entry for group {} found! Aborting.\n", .{first_num});
            return;
        }
        if (second_idx == null) {
            std.debug.print("No entry for group {} found! Aborting.\n", .{second_num});
            return;
        }
        const first = first_idx orelse unreachable;
        const second = second_idx orelse unreachable;
        if (first > second) {
            std.debug.print("Group {} modified their submission after group {}! Aborting.", .{ first_num, second_num });
            return;
        }
        var count: u32 = 0;
        var group_nums = std.ArrayList(u32).init(allocator);
        defer group_nums.deinit();
        for (submissions.submissions[first .. second + 1]) |sub| {
            if (sub.groupid != 0) {
                count += 1;
                const group_num = mapping.get(sub.groupid) orelse return error.GroupIdNotFound;
                group_nums.append(group_num) catch unreachable;
            }
        }
        std.debug.print("Found {} submissions in range:\n   ", .{count});
        for (0.., group_nums.items) |i, num| {
            std.debug.print("{}", .{num});
            if (i != group_nums.items.len - 1) {
                std.debug.print(", ", .{});
            } else {
                std.debug.print("\n", .{});
            }
        }
        const proceed = try terminal.promptUserForBoolYN(allocator, "Proceed with downloading? (y/n)");
        if (!proceed) return;
        submission_list = submissions.submissions[first .. second + 1];
    }
    try cd.makeDir(chosen_assignment.name);
    var new_dir = try cd.openDir(chosen_assignment.name, .{});
    defer new_dir.close();
    for (submission_list) |sub| {
        if (sub.groupid != 0) {
            const group_num = mapping.get(sub.groupid) orelse return error.GroupIdNotFound;
            std.debug.print("Downloading submission from group {}...\n", .{group_num});
            try sub.download(allocator, mapping, new_dir, moodle_config.*, assignment_num);
        }
    }
}

const EnrolledUsers = struct {
    users: []UserData,
};

const UserData = struct {
    groups: []GroupData,
};

const GroupData = struct {
    id: u32,
    name: []const u8,
};

pub fn getGroupNumbers(allocator: std.mem.Allocator, moodle_config: config.MoodleConfig, course_id: []const u8) !std.AutoHashMap(u32, u32) {
    var mapping = std.AutoHashMap(u32, u32).init(allocator);
    var url = Url.init(allocator, moodle_base_link);
    defer url.deinit();
    url.addQuery("moodlewsrestformat", "json");
    url.addQuery("wsfunction", "core_enrol_get_enrolled_users");
    url.addQuery("courseid", course_id);
    url.addQuery("wstoken", moodle_config.moodle_token);
    const group_data = http_req.urlRequest(allocator, url.getString()) catch return error.GroupDataNotFound;
    defer group_data.deinit();
    const parsed = try std.json.parseFromSlice([]UserData, allocator, group_data.items, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value) |user| {
        std.debug.assert(user.groups.len < 2);
        for (user.groups) |group| {
            const idx = std.mem.indexOfScalar(u8, group.name, ' ') orelse return error.GroupDataParsingError;
            const group_num = try std.fmt.parseInt(u32, group.name[idx + 1 ..], 10);
            mapping.put(group.id, group_num) catch unreachable;
        }
    }
    return mapping;
}
