const std = @import("std");
const z = @import("zignal");

const usage =
    \\Usage: txt2img "text to draw" [<options>]
    \\
    \\Options:
    \\    -o, --output name of the file to write to. Defaults to output.png
    \\    -s, --size <width>x<height> specifies the size, in pixels, of the generated image. Defaults to 512x512
    \\    -bg <color> specifies the background color of the image, see below for details on valid colors. Defaults to white
    \\    -fg <color> specifies the foreground color of the image, see below for details on valid colors. Defaults to black
    \\    -p, --pos <X,Y> specifies the starting position of the text in the image. Defaults to 16,32
    \\
    \\Notes:
    \\    Colors accept names (white, black, red, etc.), #RRGGBB, or #RRGGBBAA
    \\
;

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

const Cli = struct {
    text: []const u8,
    output: []const u8 = "image.png",
    width: usize = 512,
    height: usize = 512,
    bg: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    fg: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    pos_x: usize = 16,
    pos_y: usize = 32,

    fn parse(allocator: std.mem.Allocator) !Cli {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();
        if (!args.skip()) return error.MissingProgramName;
        var cli = Cli{ .text = "" };
        var seen_output = false;
        var seen_text = false;
        errdefer if (seen_text) allocator.free(cli.text);
        errdefer if (seen_output) allocator.free(cli.output);
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
                const value = args.next() orelse return error.MissingOutputFile;
                cli.output = try allocator.dupe(u8, value);
                seen_output = true;
            } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--size")) {
                const value = args.next() orelse return error.MissingValue;
                const dims = try parseSize(value);
                cli.width = dims.width;
                cli.height = dims.height;
            } else if (std.mem.eql(u8, arg, "-bg")) {
                const value = args.next() orelse return error.MissingValue;
                cli.bg = try parseColor(value);
            } else if (std.mem.eql(u8, arg, "-fg")) {
                const value = args.next() orelse return error.MissingValue;
                cli.fg = try parseColor(value);
            } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--pos")) {
                const value = args.next() orelse return error.MissingValue;
                const pos = try parsePos(value);
                cli.pos_x = pos.x;
                cli.pos_y = pos.y;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                try printUsage();
                return error.HelpRequested;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return error.UnknownOption;
            } else {
                if (seen_text) return error.TooManyArguments;
                cli.text = try allocator.dupe(u8, arg);
                seen_text = true;
            }
        }
        if (cli.text.len == 0) return error.MissingValue;
        if (!seen_output) {
            cli.output = try allocator.dupe(u8, "image.png");
            seen_output = true;
        }
        return cli;
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const cli = Cli.parse(allocator) catch |err| switch (err) {
        error.HelpRequested => return,
        else => {
            try printUsage();
            return err;
        },
    };
    defer allocator.free(cli.text);
    defer allocator.free(cli.output);
    if (cli.width == 0 or cli.height == 0) return error.InvalidDimensions;
    var image = try z.Image(z.Rgba(u8)).init(allocator, cli.height, cli.width);
    defer image.deinit(allocator);
    image.fill(toRgba(cli.bg));
    var canvas = z.Canvas(z.Rgba(u8)).init(allocator, image);
    const position = z.Point(2, f32).init(.{
        @as(f32, @floatFromInt(cli.pos_x)),
        @as(f32, @floatFromInt(cli.pos_y)),
    });
    canvas.drawText(cli.text, position, toRgba(cli.fg), z.font.font8x8.basic, 1.0, .soft);
    try image.save(allocator, cli.output);
}

fn parseSize(raw: []const u8) !struct { width: usize, height: usize } {
    const sep = std.mem.indexOfScalar(u8, raw, 'x') orelse std.mem.indexOfScalar(u8, raw, 'X') orelse return error.InvalidDimensions;
    const width = try std.fmt.parseInt(usize, raw[0..sep], 10);
    const height = try std.fmt.parseInt(usize, raw[sep + 1 ..], 10);
    return .{ .width = width, .height = height };
}

fn parsePos(raw: []const u8) !struct { x: usize, y: usize } {
    const sep = std.mem.indexOfScalar(u8, raw, ',') orelse return error.InvalidPosition;
    const x = try std.fmt.parseInt(usize, raw[0..sep], 10);
    const y = try std.fmt.parseInt(usize, raw[sep + 1 ..], 10);
    return .{ .x = x, .y = y };
}

fn parseColor(raw: []const u8) !Color {
    if (raw.len == 0) return error.InvalidColor;
    if (raw[0] == '#') {
        const hex = raw[1..];
        if (hex.len != 6 and hex.len != 8) return error.InvalidColor;
        const value = try std.fmt.parseInt(u32, hex, 16);
        if (hex.len == 6) {
            return Color{
                .r = @as(u8, @intCast((value >> 16) & 0xff)),
                .g = @as(u8, @intCast((value >> 8) & 0xff)),
                .b = @as(u8, @intCast(value & 0xff)),
            };
        } else {
            return Color{
                .r = @as(u8, @intCast((value >> 24) & 0xff)),
                .g = @as(u8, @intCast((value >> 16) & 0xff)),
                .b = @as(u8, @intCast((value >> 8) & 0xff)),
                .a = @as(u8, @intCast(value & 0xff)),
            };
        }
    }
    const named = [_]struct { name: []const u8, color: Color }{
        .{ .name = "white", .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
        .{ .name = "black", .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 } },
        .{ .name = "red", .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } },
        .{ .name = "green", .color = .{ .r = 0, .g = 128, .b = 0, .a = 255 } },
        .{ .name = "blue", .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } },
        .{ .name = "gray", .color = .{ .r = 128, .g = 128, .b = 128, .a = 255 } },
        .{ .name = "grey", .color = .{ .r = 128, .g = 128, .b = 128, .a = 255 } },
        .{ .name = "yellow", .color = .{ .r = 255, .g = 255, .b = 0, .a = 255 } },
        .{ .name = "cyan", .color = .{ .r = 0, .g = 255, .b = 255, .a = 255 } },
        .{ .name = "magenta", .color = .{ .r = 255, .g = 0, .b = 255, .a = 255 } },
    };
    for (named) |entry| {
        if (std.ascii.eqlIgnoreCase(raw, entry.name)) return entry.color;
    }
    return error.InvalidColor;
}

fn printUsage() !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    try stdout.interface.print(usage, .{});
    try stdout.interface.flush();
}

fn toRgba(color: Color) z.Rgba(u8) {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}
