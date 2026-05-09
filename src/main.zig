const std = @import("std");
const z = @import("zignal");
const Color = z.Rgba(u8);

const usage =
	\\Usage: txt2img "text to draw" [<options>]
	\\
	\\Options:
	\\    -o, --output <file> Name of the file to write to (default: image.png)
	\\    -s, --size <width>x<height> Set image dimensions (default: 512x512)
	\\    -w, --width <value> Set width only
	\\    -H, --height <value> Set height only
	\\    -p, --pos <x,y> Starting position of the text (default: 16,32)
	\\    -x <value> Set x position only
	\\    -y <value> Set y position only
	\\    -bg <color> Background color (default: white)
	\\    -fg <color> Foreground color (default: black)
	\\    -f, --font <path> BDF/PCF font file to use
	\\    -S, --scale <factor> Scale factor for the text (default: 1.0)
	\\    -d, --display Display the image in the terminal
	\\    -h, --help Display this help message
	\\
	\\Notes:
	\\    Colors accept names (white, black, red, etc.), #RRGGBB, or #RRGGBBAA
	\\
;

const Cli = struct {
	text: []const u8,
	output: []const u8 = "image.png",
	width: u32 = 512,
	height: u32 = 512,
	bg: Color = .white,
	fg: Color = .black,
	pos_x: u32 = 16,
	pos_y: u32 = 32,
	scale: f32 = 1,
	font: z.BitmapFont = z.font.font8x8.basic,
	display: bool = false,

	fn parse(io: std.Io, allocator: std.mem.Allocator, raw_args: std.process.Args) !Cli {
		var args = try raw_args.iterateAllocator(allocator);
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
			} else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--width")) {
				const value = args.next() orelse return error.MissingValue;
				cli.width = (try parseSize(value)).width;
			} else if (std.mem.eql(u8, arg, "-H") or std.mem.eql(u8, arg, "--height")) {
				const value = args.next() orelse return error.MissingValue;
				cli.height = (try parseSize(value)).height;
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
			} else if (std.mem.eql(u8, arg, "-x")) {
				const value = args.next() orelse return error.MissingValue;
				cli.pos_x = (try parsePos(value)).x;
			} else if (std.mem.eql(u8, arg, "-y")) {
				const value = args.next() orelse return error.MissingValue;
				cli.pos_y = (try parsePos(value)).y;
			} else if (std.mem.eql(u8, arg, "-S") or std.mem.eql(u8, arg, "--scale")) {
				const value = args.next() orelse return error.MissingValue;
				cli.scale = try std.fmt.parseFloat(f32, value);
			} else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--font")) {
				const value = args.next() orelse return error.MissingValue;
				cli.font = try z.BitmapFont.load(io, allocator, value, .all);
			} else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--display")) {
				cli.display = true;
			} else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
				try printUsage(io);
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

pub fn main(init: std.process.Init) !void {
	const allocator = init.gpa;
	const io = init.io;
	const cli = Cli.parse(io, allocator, init.minimal.args) catch |err| switch (err) {
		error.HelpRequested => return,
		else => {
			try printUsage(io);
			return err;
		},
	};
	defer allocator.free(cli.text);
	defer allocator.free(cli.output);
	if (cli.width == 0 or cli.height == 0) return error.InvalidDimensions;
	var image = try z.Image(Color).init(allocator, cli.height, cli.width);
	defer image.deinit(allocator);
	image.fill(cli.bg);
	var canvas = z.Canvas(Color).init(allocator, image);
	const position = z.Point(2, f32).init(.{
		@as(f32, @floatFromInt(cli.pos_x)),
		@as(f32, @floatFromInt(cli.pos_y)),
	});
	canvas.drawText(cli.text, position, cli.fg, cli.font, cli.scale, .fast);
	if (cli.display) {
		var buffer: [256]u8 = undefined;
		var stdout = std.Io.File.stdout().writer(io, &buffer);
		try stdout.interface.print("{f}\n", .{image.display(io, .{ .auto = .{} })});
		try stdout.interface.flush();
	}
	try image.save(io, allocator, cli.output);
}

fn parseSize(raw: []const u8) !struct { width: u32, height: u32 } {
	const sep = std.mem.indexOfScalar(u8, raw, 'x') orelse std.mem.indexOfScalar(u8, raw, 'X') orelse return error.InvalidDimensions;
	const width = try std.fmt.parseInt(u32, raw[0..sep], 10);
	const height = try std.fmt.parseInt(u32, raw[sep + 1 ..], 10);
	return .{ .width = width, .height = height };
}

fn parsePos(raw: []const u8) !struct { x: u32, y: u32 } {
	const sep = std.mem.indexOfScalar(u8, raw, ',') orelse return error.InvalidPosition;
	const x = try std.fmt.parseInt(u32, raw[0..sep], 10);
	const y = try std.fmt.parseInt(u32, raw[sep + 1 ..], 10);
	return .{ .x = x, .y = y };
}

fn parseColor(raw: []const u8) !Color {
	if (raw.len == 0) return error.InvalidColor;
	if (raw[0] == '#') {
		const hex = raw[1..];
		if (hex.len != 6 and hex.len != 8) return error.InvalidColor;
		const value = try std.fmt.parseInt(u32, hex, 16);
		if (hex.len == 6) {
			return .{
				.r = @intCast((value >> 16) & 0xff),
				.g = @intCast((value >> 8) & 0xff),
				.b = @intCast(value & 0xff),
			};
		} else {
			return .initHex(value);
		}
	}
	const named = [_]struct { name: []const u8, color: Color }{
		.{ .name = "white", .color = .initHex(0xffffffff) },
		.{ .name = "black", .color = .initHex(0x000000ff) },
		.{ .name = "red", .color = .initHex(0xff0000ff) },
		.{ .name = "green", .color = .initHex(0x00ff00ff) },
		.{ .name = "blue", .color = .initHex(0x0000ffff) },
		.{ .name = "gray", .color = .initHex(0x808080ff) },
		.{ .name = "grey", .color = .initHex(0x808080ff) },
		.{ .name = "yellow", .color = .initHex(0xffff00ff) },
		.{ .name = "cyan", .color = .initHex(0x00ffffff) },
		.{ .name = "magenta", .color = .initHex(0xff00ffff) },
	};
	for (named) |entry| {
		if (std.ascii.eqlIgnoreCase(raw, entry.name)) return entry.color;
	}
	return error.InvalidColor;
}

fn printUsage(io: std.Io) !void {
	var stdout_buffer: [256]u8 = undefined;
	var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
	try stdout.interface.print(usage, .{});
	try stdout.interface.flush();
}
