const std = @import("std");
const c = @cImport({
    @cInclude("stb_easy_font_wrapper.h");
});

const usage =
    \\Usage: txt2img "text to draw" [<options>]
    \\
    \\Options:
    \\    -o, --output name of the file to write to. Defaults to output.png.
    \\    -s, --size <width>x<height> specifies the size, in pixels, of the generated image. Defaults to 512x512.
    \\    -bg <color> specifies the background color of the image, see below for details on valid colors. Defaults to white.
    \\    -fg <color> specifies the foreground color of the image, see below for details on valid colors. Defaults to black.
    \\    -p, --pos <X,Y> specifies the starting position of the text in the image. Defaults to 16,24.
    \\
    \\Notes:
    \\    Colors accept names (white, black, red, etc.), #RRGGBB, or #RRGGBBAA.
    \\
;

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    color: [4]u8,
};

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

const Vec2 = struct {
    x: f32,
    y: f32,
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
        var seen_text = false;
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
                cli.output = args.next() orelse return error.MissingOutputFile;
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
                cli.text = arg;
                seen_text = true;
            }
        }
        if (cli.text.len == 0) return error.MissingValue;
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
    if (cli.width == 0 or cli.height == 0) return error.InvalidDimensions;
    const pixel_count = try std.math.mul(usize, cli.width, cli.height);
    const pixel_bytes = try std.math.mul(usize, pixel_count, 4);
    const pixels = try allocator.alloc(u8, pixel_bytes);
    defer allocator.free(pixels);
    fillBackground(pixels, cli.bg);
    try drawText(allocator, pixels, cli);
    try writePng(allocator, cli.output, cli.width, cli.height, pixels);
}

fn printUsage() !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    try stdout.interface.print(usage, .{});
    try stdout.interface.flush();
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

fn fillBackground(pixels: []u8, color: Color) void {
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i + 0] = color.r;
        pixels[i + 1] = color.g;
        pixels[i + 2] = color.b;
        pixels[i + 3] = color.a;
    }
}

fn drawText(allocator: std.mem.Allocator, pixels: []u8, cli: Cli) !void {
    if (cli.text.len == 0) return;
    const text_buf = try allocator.alloc(u8, cli.text.len + 1);
    defer allocator.free(text_buf);
    @memcpy(text_buf[0..cli.text.len], cli.text);
    text_buf[cli.text.len] = 0;
    // stb_easy_font_print averages ~270 bytes per character; add slack for safety.
    const vertex_bytes = try std.math.mul(usize, cli.text.len + 8, 300);
    const vertex_buf = try allocator.alignedAlloc(u8, std.mem.Alignment.of(Vertex), vertex_bytes);
    defer allocator.free(vertex_buf);
    var fg_bytes = [_]u8{ cli.fg.r, cli.fg.g, cli.fg.b, cli.fg.a };
    const quad_count = c.stb_easy_font_print_wrapper(
        @as(f32, @floatFromInt(cli.pos_x)),
        @as(f32, @floatFromInt(cli.pos_y)),
        @ptrCast(text_buf.ptr),
        &fg_bytes,
        vertex_buf.ptr,
        @as(c_int, @intCast(vertex_buf.len)),
    );
    const quads = @as(usize, @intCast(quad_count));
    if (quads == 0) return;
    const stride = @sizeOf(Vertex);
    var q: usize = 0;
    while (q < quads) : (q += 1) {
        var verts: [4]Vec2 = undefined;
        var v: usize = 0;
        while (v < 4) : (v += 1) {
            const offset = (q * 4 + v) * stride;
            const vert = @as(*const Vertex, @ptrCast(@alignCast(vertex_buf.ptr + offset)));
            verts[v] = .{ .x = vert.x, .y = vert.y };
        }
        drawTriangle(pixels, cli.width, cli.height, verts[0], verts[1], verts[2], cli.fg);
        drawTriangle(pixels, cli.width, cli.height, verts[0], verts[2], verts[3], cli.fg);
    }
}

fn drawTriangle(
    pixels: []u8,
    width: usize,
    height: usize,
    a: Vec2,
    b: Vec2,
    c_vec: Vec2,
    color: Color,
) void {
    const min_x_f = @min(a.x, @min(b.x, c_vec.x));
    const max_x_f = @max(a.x, @max(b.x, c_vec.x));
    const min_y_f = @min(a.y, @min(b.y, c_vec.y));
    const max_y_f = @max(a.y, @max(b.y, c_vec.y));
    const min_x = std.math.clamp(@as(i32, @intFromFloat(@floor(min_x_f))), 0, @as(i32, @intCast(width)));
    const max_x = std.math.clamp(@as(i32, @intFromFloat(@ceil(max_x_f))), 0, @as(i32, @intCast(width)));
    const min_y = std.math.clamp(@as(i32, @intFromFloat(@floor(min_y_f))), 0, @as(i32, @intCast(height)));
    const max_y = std.math.clamp(@as(i32, @intFromFloat(@ceil(max_y_f))), 0, @as(i32, @intCast(height)));
    if (max_x <= min_x or max_y <= min_y) return;
    const denom = ((b.y - c_vec.y) * (a.x - c_vec.x)) + ((c_vec.x - b.x) * (a.y - c_vec.y));
    if (denom == 0) return;
    const inv_denom = 1.0 / denom;
    var y = min_y;
    while (y < max_y) : (y += 1) {
        var x = min_x;
        while (x < max_x) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            const l1 = ((b.y - c_vec.y) * (px - c_vec.x) + (c_vec.x - b.x) * (py - c_vec.y)) * inv_denom;
            const l2 = ((c_vec.y - a.y) * (px - c_vec.x) + (a.x - c_vec.x) * (py - c_vec.y)) * inv_denom;
            const l3 = 1.0 - l1 - l2;
            if (l1 >= 0 and l2 >= 0 and l3 >= 0) {
                const idx = (@as(usize, @intCast(y)) * width + @as(usize, @intCast(x))) * 4;
                pixels[idx + 0] = color.r;
                pixels[idx + 1] = color.g;
                pixels[idx + 2] = color.b;
                pixels[idx + 3] = color.a;
            }
        }
    }
}

fn writePng(allocator: std.mem.Allocator, path: []const u8, width: usize, height: usize, pixels: []const u8) !void {
    const path_c = try allocator.alloc(u8, path.len + 1);
    defer allocator.free(path_c);
    @memcpy(path_c[0..path.len], path);
    path_c[path.len] = 0;
    const result = c.stbi_write_png(
        @ptrCast(path_c.ptr),
        @as(c_int, @intCast(width)),
        @as(c_int, @intCast(height)),
        4,
        @ptrCast(pixels.ptr),
        @as(c_int, @intCast(width * 4)),
    );
    if (result == 0) return error.WriteFailed;
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
