const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utilities.zig");
const GridPDFInterpolator = @import("zoti.zig").GridPDFInterpolator;

pub const std_options: std.Options = .{ .log_level = .info };

fn createInterp(allocator: Allocator, io: std.Io, seed: u64) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var rng: std.Random.DefaultPrng = .init(seed);

    const gridx = try utils.linearSpacedBins(f64, arena.allocator(), -10, 10, 10);
    const gridy = try utils.linearSpacedBins(f64, arena.allocator(), 1, 20, 10);

    const pdf_bins = try utils.linearSpacedBins(f64, allocator, -20, 20, 100);
    defer allocator.free(pdf_bins);

    const interp: GridPDFInterpolator = try .init(
        allocator,
        &.{ gridx, gridy },
        &.{pdf_bins},
        .{ .probability_steps = 10000 },
    );
    defer interp.deinit(allocator);
    const data = try allocator.alloc(f64, 100000);
    defer allocator.free(data);
    for (0..gridx.len) |i| {
        for (0..gridy.len) |j| {
            for (0..data.len) |idx| {
                data[idx] = rng.random().floatNorm(f64) * gridy[j] + gridx[i];
            }
            try interp.setAtFromPoints(allocator, &.{ gridx[i], gridy[j] }, &.{data});
        }
    }

    var interp_pdf = try interp.generatePDF(arena.allocator(), &.{ -5, 1.1 });
    std.log.info("{any}", .{interp_pdf});
    interp_pdf = try interp.generatePDF(arena.allocator(), &.{ 0, 3 });
    std.log.info("{any}", .{interp_pdf});
    interp_pdf = try interp.generatePDF(arena.allocator(), &.{ 5, 10 });
    std.log.info("{any}", .{interp_pdf});
    _ = io;
}

pub fn main(init: std.process.Init) !void {
    try createInterp(init.gpa, init.io, @intCast(std.posix.getppid()));
}
