const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Histogram = @import("histogram.zig").Histogram;

const GridPDFInterpolator = struct {
    grid: []const []const f64 = &.{},
    pdf_map: std.HashMapUnmanaged([]const f64, Histogram, utils.SliceHashContext, 80) = .empty,
    // The map should link points in the interpolation space to marginal CDFs, indexed by the dimension
    cdf_map: std.HashMapUnmanaged([]const f64, []const []const f64, utils.SliceHashContext, 80) = .empty,

    pub fn init(allocator: Allocator, grid: []const []const f64, ) !GridPDFInterpolator {}
};

const stats = @import("stats.zig");
const utils = @import("utilities.zig");
const histogram = @import("histogram.zig");

test {
    _ = PDFInterpolator{};

    _ = histogram;
    _ = stats;
    _ = utils;
}
