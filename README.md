# Functionality
Commmand line tool to download submissions from RWTH Moodle. Compile with zig 0.13.0. Does not work on all types of submissions, depends on how they are setup inside Moodle.

Debug Compilation:
```bash
zig build
```

Release Compilation:
```bash
zig build -Doptimize=ReleaseFast
```