const std = @import("std");
const Allocator = std.mem.Allocator;

const Histogram = @import("histogram.zig").Histogram;
const utils = @import("utilities.zig");

pub fn mean(comptime T: type, xs: []T, pdf: []T) T {
    std.debug.assert(xs.len == pdf.len);
    var m: T = 0;
    for (0..xs.len) |idx| {
        m += xs[idx] * pdf[idx];
    }
    return m;
}

/// Calculate the CDF for 1d PDF. Assumes PDF is normalized.
pub fn getCDF(allocator: Allocator, pdf: []const f64, bins: []const f64) ![]f64 {
    const cdf = try allocator.alloc(f64, pdf.len);
    cdf[0] = pdf[0] * (bins[1] - bins[0]);
    for (1..pdf.len) |idx| {
        const width = bins[idx + 1] - bins[idx];
        cdf[idx] = cdf[idx - 1] + (pdf[idx] * width);
    }
    return cdf;
}

pub fn cdfToPDF(allocator: Allocator, bins: []const f64, cdf: []const f64) ![]f64 {
    const pdf = try allocator.alloc(f64, cdf.len);
    pdf[0] = cdf[0] / (bins[1] - bins[0]);
    for (pdf[1..], 1..pdf.len) |*p, idx| p.* = (cdf[idx] - cdf[idx - 1]) / (bins[idx + 1] - bins[idx]);
    return pdf;
}

pub fn cdfToQF(allocator: Allocator, bins: []const f64, cdf: []const f64, probs: []const f64) ![]f64 {
    const centers = try utils.centers(f64, allocator, bins);
    defer allocator.free(centers);

    const qf = try allocator.alloc(f64, probs.len);

    std.log.debug("cdf: {any}", .{cdf});
    std.log.debug("centers: {any}", .{centers});

    for (0..probs.len) |idx| {
        qf[idx] = utils.interp(f64, cdf, centers, probs[idx], .flat);
        std.log.debug("{d} to {d}", .{ probs[idx], qf[idx] });
    }
    return qf;
}

pub fn pdfToQF(allocator: Allocator, bins: []const f64, pdf: []const f64, probs: []const f64) ![]f64 {
    const cdf = try getCDF(allocator, pdf, bins);
    if (!std.math.approxEqRel(f64, cdf[cdf.len - 1], 1, 1e-6)) {
        for (cdf) |*c| c.* /= cdf[cdf.len - 1];
    }
    defer allocator.free(cdf);
    return cdfToQF(allocator, bins, cdf, probs);
}

pub fn qfToCDF(allocator: Allocator, bins: []const f64, probs: []const f64, qf: []const f64) ![]f64 {
    const cdf = try allocator.alloc(f64, bins.len - 1);
    for (0..cdf.len) |idx| {
        const center = (bins[idx + 1] + bins[idx]) / 2;
        if (center < qf[0]) {
            cdf[idx] = 0;
        } else if (center > qf[qf.len - 1]) {
            cdf[idx] = 1;
        } else {
            cdf[idx] = utils.interp(f64, qf, probs, center, .flat);
        }
    }
    for (cdf) |*c| {
        c.* /= cdf[cdf.len - 1];
    }
    return cdf;
}

pub fn qfToPDF(allocator: Allocator, bins: []const f64, probs: []const f64, qf: []const f64) ![]f64 {
    const cdf = try qfToCDF(allocator, bins, probs, qf);
    defer allocator.free(cdf);
    const pdf = cdfToPDF(allocator, bins, cdf);
    return pdf;
}

test "cdf" {
    const samps = 10000;
    const allocator = std.testing.allocator;

    const bins = try utils.linearSpacedBins(f64, allocator, -5, 5, 20);
    defer allocator.free(bins);

    var hist = try Histogram.init(allocator, &.{bins}, null, .{});
    defer hist.deinit(allocator);

    var rng_gen = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..samps) |_| {
        hist.addPoint(&[_]f64{rng_gen.random().floatNorm(f64)});
    }
    hist.normalize();

    const cdf = try getCDF(allocator, hist.contents, bins);
    defer allocator.free(cdf);
    try std.testing.expect(std.math.approxEqRel(f64, cdf[cdf.len - 1], 1.0, 1e-4));

    const pdf = try cdfToPDF(allocator, bins, cdf);
    defer allocator.free(pdf);

    const diffs = try allocator.alloc(f64, pdf.len);
    allocator.free(diffs);

    var pass: bool = true;
    for (0..pdf.len) |idx| {
        if (!std.math.approxEqAbs(f64, pdf[idx], hist.contents[idx], 5e-3)) {
            pass = false;
        }
        diffs[idx] = pdf[idx] - hist.contents[idx];
    }

    std.testing.expect(pass) catch |e| {
        std.log.err("Unequal PDFs", .{});
        for (0..diffs.len) |idx| {
            std.log.err("{d:.4} - {d:.4} = {d:.4}", .{
                pdf[idx],
                hist.contents[idx],
                diffs[idx],
            });
        }
        return e;
    };
}

test "qf" {
    const samps = 10000;
    const allocator = std.testing.allocator;

    const bins = try utils.linearSpacedBins(f64, allocator, -5, 5, 40);
    defer allocator.free(bins);

    var hist = try Histogram.init(allocator, &.{bins}, null, .{});
    defer hist.deinit(allocator);

    var rng_gen = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..samps) |_| {
        hist.addPoint(&[_]f64{rng_gen.random().floatNorm(f64)});
    }
    // hist.zeroPad(1e-6);
    hist.normalize();

    const cdf = try getCDF(allocator, hist.contents, bins);
    defer allocator.free(cdf);

    const probs_edges = try utils.linearSpacedBins(f64, allocator, 0, 1, 1000);
    defer allocator.free(probs_edges);
    const probs = try utils.centers(f64, allocator, probs_edges);
    defer allocator.free(probs);

    const qf = try pdfToQF(allocator, bins, hist.contents, probs);
    defer allocator.free(qf);
    const test_pdf = try qfToPDF(allocator, bins, probs, qf);
    defer allocator.free(test_pdf);

    const diffs = try allocator.alloc(f64, test_pdf.len);
    defer allocator.free(diffs);
    var total_diff: f64 = 0;

    var pass: bool = true;
    for (0..test_pdf.len) |idx| {
        if (!std.math.approxEqAbs(f64, test_pdf[idx], hist.contents[idx], 5e-3)) {
            pass = false;
        }
        diffs[idx] = test_pdf[idx] - hist.contents[idx];
        total_diff += diffs[idx];
    }

    std.testing.expect(pass) catch |e| {
        std.log.err("Unequal PDFs - total diff: {d}", .{total_diff});
        for (0..diffs.len) |idx| {
            std.log.err("{d:.4} - {d:.4} = {d:.4}", .{
                test_pdf[idx],
                hist.contents[idx],
                diffs[idx],
            });
        }
        return e;
    };

    try std.testing.expect(std.math.approxEqRel(f64, cdf[cdf.len - 1], 1.0, 1e-4));
}
