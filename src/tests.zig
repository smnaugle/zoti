const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const utils = @import("utilities.zig");
const GridPDFInterpolator = @import("zoti.zig").GridPDFInterpolator;
const hdf5 = @import("hdf5.zig");
const stats = @import("stats.zig");

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
    qf: []f64,
    probs: []f64,

    pub fn init(allocator: Allocator, bins: []f64, endpoint: f64) !BetaSampler {
        const electron_mass = 0.511;
        const energy = try utils.centers(f64, allocator, bins);
        const spectrum = try beta(allocator, energy, endpoint, electron_mass);
        defer allocator.free(spectrum);
        // for (spectrum) |*s| s.* += 1e-6;
        stats.normalize(f64, bins, spectrum);
        const probs = try utils.linearSpacedBins(f64, allocator, 0, 1, 10000);
        const qf = try stats.pdfToQF(allocator, bins, spectrum, probs);
        return .{ .probs = probs, .qf = qf };
    }

    pub fn sample(self: BetaSampler, value: f64) f64 {
        const interp = utils.interp(f64, self.probs, self.qf, value, .linear);
        return interp;
    }
    pub fn deinit(self: BetaSampler, allocator: Allocator) void {
        allocator.free(self.probs);
        allocator.free(self.qf);
    }
};

fn createInterp(allocator: Allocator, io: std.Io) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var rand_buf: [8]u8 = undefined;
    io.random(&rand_buf);
    var rng: std.Random.DefaultPrng = .init(std.mem.readInt(u64, &rand_buf, .native));

    const gridx = try utils.linearSpacedBins(f64, arena.allocator(), -10, 10, 21);
    const gridy = try utils.linearSpacedBins(f64, arena.allocator(), 1, 5, 20);

    const pdf_bins_x = try utils.linearSpacedBins(f64, allocator, 0, 10, 100);
    defer allocator.free(pdf_bins_x);
    const pdf_bins_y = try utils.linearSpacedBins(f64, allocator, -10, 10, 100);
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
    data[0] = try allocator.alloc(f64, 50000);
    defer allocator.free(data[0]);
    data[1] = try allocator.alloc(f64, 50000);
    defer allocator.free(data[1]);
    for (0..gridx.len) |i| {
        for (0..gridy.len) |j| {
            const sampler: BetaSampler = try .init(arena.allocator(), pdf_bins_x, gridy[j]);
            defer sampler.deinit(arena.allocator());
            for (0..data[0].len) |idx| {
                // data[idx] = rng.random().floatExp(f64) * gridy[j] + gridx[i];
                data[0][idx] = sampler.sample(rng.random().float(f64));
                data[1][idx] = rng.random().floatNorm(f64) * gridy[j] + gridx[i];
                // const sample = rng.random().float(f64);
                // data[idx] = sample;
            }
            try interp.setAtFromPoints(allocator, &.{ gridx[i], gridy[j] }, data);
        }
    }

    const interp_pts = [_][2]f64{
        [2]f64{ -5, 1.1 },
        [2]f64{ 0, 3 },
        [2]f64{ 5.4, 4 },
    };

    const outfile: hdf5.File = try .create(allocator, "test.hdf5", .{ .access = .H5F_ACC_TRUNC });
    defer outfile.close(allocator);
    _ = try outfile.openOrCreateGroup("output/");
    _ = try outfile.openOrCreateGroup("output/interps/");

    try outfile.writeArray(pdf_bins_x, "output/bins_x");
    try outfile.writeArray(pdf_bins_y, "output/bins_y");

    for (interp_pts) |pt| {
        const grp_path = try std.fmt.allocPrint(arena.allocator(), "output/interps/{d}_{d}", .{ pt[0], pt[1] });
        _ = try outfile.openOrCreateGroup(grp_path);
        const interp_pdf = try interp.generatePDF(arena.allocator(), &pt);
        const dset_name = try std.mem.concat(arena.allocator(), u8, &.{ grp_path, "/pdf" });
        try outfile.writeArray(interp_pdf, dset_name);
    }
}

pub fn main(init: std.process.Init) !void {
    try createInterp(init.gpa, init.io);
}
