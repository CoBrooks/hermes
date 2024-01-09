const std = @import("std");
const Chameleon = @import("chameleon").Chameleon;

const color = Chameleon.init(.Auto);

const Span = struct {
    start: usize,
    end: usize,

    pub fn contains(self: Span, other: Span) bool {
        return self.start <= other.start and self.end >= other.end;
    }
};

pub const Source = struct {
    gpa: std.mem.Allocator,
    source: []const u8,

    filepath: []const u8,
    lines: []const Span,

    const ByteOffset = usize;

    pub fn fromFile(gpa: std.mem.Allocator, filepath: []const u8) !Source {
        const file = try std.fs.cwd().openFile(filepath, .{});
        const stat = try file.stat();

        const source = try file.readToEndAlloc(gpa, stat.size);
        var lines_arr = std.ArrayListUnmanaged(Span){};

        try lines_arr.append(gpa, .{ .start = 0, .end = 0 });

        // Get the start of each line
        for (source, 0..) |char, i| {
            if (char == '\n') {
                var prev = lines_arr.pop();
                prev.end = i;
                try lines_arr.append(gpa, prev);
                try lines_arr.append(gpa, .{ .start = i + 1, .end = 0 });
            }
        }

        var prev = lines_arr.pop();
        prev.end = source.len;
        try lines_arr.append(gpa, prev);

        const lines = try lines_arr.toOwnedSlice(gpa);

        return Source{
            .gpa = gpa,
            .source = source,
            .filepath = filepath,
            .lines = lines,
        };
    }

    pub fn deinit(self: *Source) void {
        defer self.gpa.free(self.lines);
        defer self.gpa.free(self.source);
    }

    pub fn lineContainingSpan(self: *const Source, span: Span) ?struct { line_idx: usize, inner_span: Span } {
        for (self.lines, 0..) |line, i| {
            if (line.contains(span)) {
                return .{
                    .line_idx = i,
                    .inner_span = Span{
                        .start = span.start - line.start,
                        .end = span.end - line.start,
                    },
                };
            }
        } else return null;
    }
};

pub const Report = struct {
    source: *const Source,
    labels: []const Label,

    const Label = struct {
        span: Span,
        message: []const u8,
        level: Level = .Error,
    };

    const Level = enum {
        Error,
        Warning,
        Help,
    };

    fn printLabel(self: Report, label: Label, comptime level: Level) void {
        const i = self.source.lineContainingSpan(label.span).?;
        const line_span = self.source.lines[i.line_idx];
        const line = self.source.source[line_span.start..line_span.end];

        const start = line[0..i.inner_span.start];
        const match = line[i.inner_span.start..i.inner_span.end];
        const end = line[i.inner_span.end..];

        const main_color = switch (level) {
            .Error => color.red(),
            .Warning => color.yellow(),
            .Help => color.green(),
        };

        const level_text = switch (level) {
            .Error => "error",
            .Warning => "warn",
            .Help => "help",
        };

        std.debug.print(color.fmt("{s}:{d}:{d}: ") ++ main_color.fmt("{s}: ") ++ color.reset().fmt("{s}\n"), .{
            self.source.filepath,
            i.line_idx + 1,
            i.inner_span.start + 1,
            level_text,
            label.message,
        });

        const offset = start.len + (match.len / 2);

        std.debug.print(color.gray().dim().fmt("...│\n"), .{});

        std.debug.print(color.gray().fmt("{d:>3}│ ") ++ color.reset().fmt("{s}") ++ main_color.fmt("{s}") ++ color.reset().fmt("{s}\n"), .{
            i.line_idx + 1,
            start,
            match,
            end,
        });

        std.debug.print(color.gray().dim().fmt("...│ {s:[1]}") ++ main_color.dim().fmt("│    \n"), .{ "", offset });
        std.debug.print(color.gray().dim().fmt("...│ {s:[2]}") ++ main_color.dim().fmt("└╴") ++ main_color.fmt("{s}\n\n"), .{ "", label.message, offset });
    }

    pub fn print(self: Report) void {
        for (self.labels) |label| switch (label.level) {
            // Comptime trickery
            inline else => |level| self.printLabel(label, level),
        };
    }
};

test "fails in order to display output" {
    var source = try Source.fromFile(std.testing.allocator, "build.zig");
    defer source.deinit();

    const err = Report{
        .source = &source,
        .labels = &.{
            .{ .span = .{ .start = 29, .end = 32 }, .message = "function should not be marked 'pub'", .level = .Help },
            .{ .span = .{ .start = 36, .end = 41 }, .message = "function 'build' is never called", .level = .Warning },
            .{ .span = .{ .start = 46, .end = 55 }, .message = "unrecognized type 'std.Build'", .level = .Error },
        },
    };

    err.print();

    try std.testing.expect(false);
}
