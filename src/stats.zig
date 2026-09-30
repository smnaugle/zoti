const std = @import("std");
const Allocator = std.mem.Allocator;

const Histogram = @import("histogram.zig").Histogram;
const utils = @import("utilities.zig");

pub fn getCDF(allocator: Allocator, pdf: []f64, widths: []f64) ![]f64 {
    const cdf = try allocator.alloc(f64, pdf.len);
    cdf[0] = pdf[0];
    for (1..pdf.len) |idx| {
        cdf[idx] = cdf[idx - 1] + (pdf[idx] * widths[idx]);
    }
    return cdf;
}

test "cdf" {
    const samps = 10000;
    const allocator = std.testing.allocator;

    const bins = try utils.linearSpacedBins(f64, allocator, -5, 5, 20);
    defer allocator.free(bins);

    const widths = try utils.diff(f64, allocator, bins);
    defer allocator.free(widths);

    var hist = try Histogram.init(allocator, &.{bins}, null, .{});
    defer hist.deinit(allocator);

    var rng_gen = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..samps) |_| {
        hist.addPoint(&[_]f64{rng_gen.random().floatNorm(f64)});
    }
    hist.normalize();

    const cdf = try getCDF(allocator, hist.contents, widths);
    defer allocator.free(cdf);
    try std.testing.expect(std.math.approxEqRel(f64, cdf[cdf.len - 1], 1.0, 1e-4));
}
