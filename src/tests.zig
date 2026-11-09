const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const utils = @import("utilities.zig");
const GridPDFInterpolator = @import("zoti.zig").GridPDFInterpolator;
const hdf5 = @import("hdf5.zig");
const stats = @import("stats.zig");
const Histogram = @import("histogram.zig").Histogram;

pub const std_options: std.Options = .{ .log_level = .info };

fn square(val: f64) f64 {
    return math.pow(f64, val, 2);
}

fn beta(allocator: Allocator, energy: []f64, endpoint: f64, m: f64) ![]f64 {
    const prob = try allocator.alloc(f64, energy.len);
    for (energy, 0..) |e, idx| {
        if (e >= endpoint) {
            prob[idx] = 0;
        } else {
            prob[idx] = math.sqrt(square(e) + 2 * m * e) * (e + m) * square(endpoint - e);
        }
    }
    return prob;
}

const BetaSampler = struct {
    pub const Options = struct {
        mass: f64 = 0.511,
        prob_steps: u64 = 10000,
    };

    qf: []f64,
    probs: []f64,
    endpoint: f64,

    pub fn init(allocator: Allocator, bins: []f64, endpoint: f64, options: Options) !BetaSampler {
        const energy = try utils.centers(f64, allocator, bins);

        const spectrum = try beta(allocator, energy, endpoint, options.mass);
        defer allocator.free(spectrum);

        stats.normalize(f64, bins, spectrum);
        const probs = try utils.linearSpacedBins(f64, allocator, 0, 1, options.prob_steps);
        const qf = try stats.pdfToQF(allocator, bins, spectrum, probs);
        return .{ .probs = probs, .qf = qf, .endpoint = endpoint };
    }

    pub fn sample(self: BetaSampler, value: f64) f64 {
        const interp = utils.interp(f64, self.probs, self.qf, value, .flat);
        return interp;
    }
    pub fn deinit(self: BetaSampler, allocator: Allocator) void {
        allocator.free(self.probs);
        allocator.free(self.qf);
    }
};

fn createInterp(allocator: Allocator, io: std.Io, outfile_name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var rand_buf: [8]u8 = undefined;
    io.random(&rand_buf);
    var rng: std.Random.DefaultPrng = .init(std.mem.readInt(u64, &rand_buf, .native));

    const gridx = try utils.linearSpacedBins(f64, arena.allocator(), -10, 10, 5);
    const gridy = try utils.linearSpacedBins(f64, arena.allocator(), 1, 5, 5);

    const pdf_bins_x = try utils.linearSpacedBins(f64, allocator, 0, 10, 100);
    defer allocator.free(pdf_bins_x);
    const pdf_bins_y = try utils.linearSpacedBins(f64, allocator, -20, 20, 100);
    defer allocator.free(pdf_bins_y);

    const interp: GridPDFInterpolator = try .init(
        allocator,
        &.{ gridx, gridy },
        &.{ pdf_bins_x, pdf_bins_y },
        .{ .probability_steps = 10000 },
    );
    defer interp.deinit(allocator);
    const data = try allocator.alloc([]f64, 2);
    defer allocator.free(data);
    const num_samples: u64 = 1e6;
    data[0] = try allocator.alloc(f64, num_samples);
    defer allocator.free(data[0]);
    data[1] = try allocator.alloc(f64, num_samples);
    defer allocator.free(data[1]);

    for (0..gridx.len) |i| {
        for (0..gridy.len) |j| {
            const sampler: BetaSampler = try .init(arena.allocator(), pdf_bins_x, gridy[j], .{});
            defer sampler.deinit(arena.allocator());
            for (0..data[0].len) |idx| {
                data[0][idx] = sampler.sample(rng.random().float(f64));
                data[1][idx] = rng.random().floatNorm(f64) * gridy[j] + gridx[i] + 3.0 * data[0][idx] / sampler.endpoint;
                // data[1][idx] = rng.random().floatNorm(f64) * gridy[j] + gridx[i];
            }
            try interp.setAtFromPoints(allocator, &.{ gridx[i], gridy[j] }, data);
        }
    }

    const interp_pts = [_][2]f64{
        [2]f64{ -5, 1.1 },
        [2]f64{ 0, 3.4 },
        [2]f64{ 5.4, 4.5 },
    };

    const outfile: hdf5.File = try .create(allocator, outfile_name, .{ .access = .H5F_ACC_TRUNC });
    defer outfile.close(allocator);
    _ = try outfile.openOrCreateGroup("output/");
    _ = try outfile.openOrCreateGroup("output/interps/");

    try outfile.writeArray(pdf_bins_x, "output/bins_x");
    try outfile.writeArray(pdf_bins_y, "output/bins_y");

    var test_hist: Histogram = try .init(allocator, &.{ pdf_bins_x, pdf_bins_y }, &.{}, .{});
    defer test_hist.deinit(allocator);

    var test_arena = std.heap.ArenaAllocator.init(allocator);
    defer test_arena.deinit();
    for (interp_pts) |pt| {
        defer _ = test_arena.reset(.retain_capacity);

        const grp_path = try std.fmt.allocPrint(test_arena.allocator(), "output/interps/{d}_{d}", .{ pt[0], pt[1] });
        _ = try outfile.openOrCreateGroup(grp_path);

        const interp_pdf = try interp.generatePDF(test_arena.allocator(), &pt);
        @memcpy(interp.root_pdf.contents, interp_pdf);

        const integral = interp.root_pdf.integral();
        if (!std.math.approxEqRel(f64, integral, 1, 1e-2)) {
            std.log.warn("Non-normalized interpolated PDF: {d}", .{integral});
        }

        const xscan = try utils.linearSpacedBins(f64, test_arena.allocator(), pt[0] - 0.01, pt[0] + 0.01, 21);
        const yscan = try utils.linearSpacedBins(f64, test_arena.allocator(), pt[1] - 0.05, pt[1] + 0.05, 21);
        var test_data: [][]f64 = try test_arena.allocator().alloc([]f64, 2);
        for (test_data) |*ct| {
            ct.* = try test_arena.allocator().alloc(f64, 100000);
        }

        const cs_dset_name_xs = try std.mem.concat(test_arena.allocator(), u8, &.{ grp_path, "/chi_sqr_scan_xs" });
        try outfile.writeArray(xscan, cs_dset_name_xs);

        const cs_dset_name_ys = try std.mem.concat(test_arena.allocator(), u8, &.{ grp_path, "/chi_sqr_scan_ys" });
        try outfile.writeArray(yscan, cs_dset_name_ys);

        var chisqrs: std.ArrayList(f64) = try .initCapacity(test_arena.allocator(), xscan.len * yscan.len);
        for (xscan) |x| {
            for (yscan) |y| {
                const sampler: BetaSampler = try .init(test_arena.allocator(), pdf_bins_x, y, .{});
                defer sampler.deinit(test_arena.allocator());
                for (0..test_data[0].len) |idx| {
                    test_data[0][idx] = sampler.sample(rng.random().float(f64));
                    test_data[1][idx] = rng.random().floatNorm(f64) * y + x + 3.0 * test_data[0][idx] / sampler.endpoint;
                }
                test_hist.clear();
                test_hist.loadNewPoints(test_data, .{ .density = true });

                var chisqr: f64 = 0;
                for (test_hist.contents, 0..) |c, idx| {
                    if (interp_pdf[idx] != 0) chisqr += square(interp_pdf[idx] - c) / interp_pdf[idx];
                }
                chisqrs.appendAssumeCapacity(chisqr);
            }
        }

        const cs_dset_name = try std.mem.concat(test_arena.allocator(), u8, &.{ grp_path, "/chisqrs" });
        try outfile.writeArray(chisqrs.items, cs_dset_name);

        const dset_name = try std.mem.concat(test_arena.allocator(), u8, &.{ grp_path, "/pdf" });
        try outfile.writeArray(interp_pdf, dset_name);
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.NoOutfileName;
    try createInterp(init.gpa, init.io, args[1]);
}
