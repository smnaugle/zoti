const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utilities.zig");

// ND is hard, lets just do everything flat under the hood
pub const Histogram = struct {
    bins: [][]f64 = &.{},
    bin_volumes: []f64 = &.{},
    nentries: u64 = 0,
    contents: []f64 = &.{},

    scratch_coord: []u64 = &.{},
    scratch_point: []f64 = &.{},

    options: Options = .{},

    pub const Options = struct {
        density: bool = false,
        zero_pad: ?f64 = null,
        points_limit: usize = std.math.maxInt(usize),
    };

    pub fn init(allocator: std.mem.Allocator, bins: []const []const f64, points_opt: ?[]const []const f64, options: Histogram.Options) !Histogram {
        var hist: Histogram = .{};
        hist.bins = try allocator.alloc([]f64, bins.len);
        var total_bins: usize = 1;
        for (bins, 0..) |b, di| {
            hist.bins[di] = try allocator.dupe(f64, b);
            total_bins *= (b.len - 1);
        }
        hist.contents = try allocator.alloc(f64, total_bins);
        for (hist.contents) |*bin| {
            bin.* = 0;
        }
        hist.scratch_coord = try allocator.alloc(u64, bins.len);
        hist.scratch_point = try allocator.alloc(f64, bins.len);
        try hist.createBinVolumes(allocator);
        if (points_opt) |points| {
            if (points.len != 0) {
                for (0..points[0].len) |idx| {
                    for (0..points.len) |dim_idx| {
                        hist.scratch_point[dim_idx] = points[dim_idx][idx];
                    }
                    hist.addPoint(hist.scratch_point);
                    if (hist.nentries > options.points_limit) break;
                }
            }
        }
        hist.options = options;
        if (options.zero_pad) |pad| {
            hist.zeroPad(pad);
        }
        if (options.density) {
            hist.normalize();
        }
        return hist;
    }

    pub fn clone(self: Histogram, allocator: std.mem.Allocator) !Histogram {
        var copy: Histogram = try .init(allocator, self.bins, &.{}, self.options);
        @memcpy(copy.bin_volumes, self.bin_volumes);
        @memcpy(copy.contents, self.contents);
        copy.nentries = self.nentries;
        copy.options = self.options;
        const og_int = self.integral();
        if (!std.math.approxEqAbs(f64, og_int, copy.integral(), std.math.floatEpsAt(f64, og_int))) {
            std.log.err("Copy with different integral: {d} vs {d}", .{ og_int, copy.integral() });
        }
        return copy;
    }

    pub fn loadNewPoints(self: *Histogram, points: []const []const f64, options: Histogram.Options) void {
        self.nentries = 0;
        if (points.len != self.bins.len) {
            std.debug.panic("Cannot load histogram with points" ++
                " of different dimension than bins: {d}, {d}", .{ points.len, self.bins.len });
        }
        for (0..self.contents.len) |ci| self.contents[ci] = 0;
        for (0..points[0].len) |idx| {
            for (0..points.len) |dim_idx| {
                self.scratch_point[dim_idx] = points[dim_idx][idx];
            }
            self.addPoint(self.scratch_point);
            if (self.nentries > options.points_limit) break;
        }
        if (options.zero_pad) |pad| {
            self.zeroPad(pad);
        }
        if (options.density) {
            self.normalize();
        }
    }

    pub fn zeroPad(self: *Histogram, pad: f64) void {
        for (self.contents) |*b| {
            if (b.* <= 0) {
                b.* = pad;
            }
        }
    }

    fn createBinVolumes(self: *Histogram, allocator: Allocator) !void {
        self.bin_volumes = try allocator.alloc(f64, self.contents.len);
        for (0..self.contents.len) |idx| {
            self.bin_volumes[idx] = 1;
            const coord = try self.flatIndexToBin(idx);
            for (0..self.bins.len) |dim_idx| {
                const bin_low = (self.bins[dim_idx])[coord[dim_idx]];
                const bin_high = (self.bins[dim_idx])[coord[dim_idx] + 1];
                self.bin_volumes[idx] *= (bin_high - bin_low);
            }
        }
    }

    pub fn normalize(self: *Histogram) void {
        const tot: f64 = self.integral();
        for (0..self.contents.len) |idx| {
            self.contents[idx] = (self.contents[idx]) / tot;
        }
    }

    pub fn integral(self: Histogram) f64 {
        const bin_vols = self.bin_volumes;
        var sum: f64 = 0;
        for (0..bin_vols.len) |idx| {
            sum += self.contents[idx] * bin_vols[idx];
        }
        return sum;
    }

    pub fn flatIndexToBin(self: Histogram, idx: usize) ![]usize {
        if (idx > self.contents.len) {
            std.log.warn("Trying to access a bin out of the range of _flat_counts: {} and {}", .{ idx, self.contents.len });
            return error.BinOutOfRange;
        }
        for (self.bins, 0..) |b, dim_idx| {
            if (dim_idx == 0) {
                self.scratch_coord[dim_idx] = idx % (b.len - 1);
            } else {
                var bins_to_cover: usize = 1;
                for (0..dim_idx) |remaining_dim_idx| {
                    bins_to_cover *= (self.bins[remaining_dim_idx].len - 1);
                }
                self.scratch_coord[dim_idx] = @divFloor(idx, bins_to_cover) % (b.len - 1);
            }
        }
        return self.scratch_coord;
    }

    pub fn coordinateToIndex(self: Histogram, coordinate: []const usize) !usize {
        if (coordinate.len != self.bins.len) {
            return error.MismatchedDimensions;
        }
        var idx: usize = 0;
        var preceding_bins: usize = 1;
        for (coordinate, 0..) |c, dim_idx| {
            // -2 because 0 indexing and bin edges to bins
            if (c > (self.bins[dim_idx].len - 1 - 1)) {
                return error.MismatchedDimensions;
            }
            idx += c * preceding_bins;
            preceding_bins *= (self.bins[dim_idx].len - 1);
        }
        return idx;
    }

    pub fn addPoint(self: *Histogram, value: []const f64) void {
        // var bin_coordinate = try self._allocator.alloc(usize, self.bins.len);
        // defer self._allocator.free(bin_coordinate);
        var coord_counts: u64 = 0;
        for (self.bins, 0..) |b, dim_idx| {
            const bin_spacing = b[1] - b[0];
            const float_coord = (value[dim_idx] - b[0]) / bin_spacing;
            if (float_coord < 0 or float_coord >= @as(f64, @floatFromInt(b.len - 1))) {
                return;
            }
            self.scratch_coord[dim_idx] = @intFromFloat(@trunc(float_coord));
            coord_counts += 1;

            // if (dim_idx == 0) {}
            // for (0..(b.len - 1)) |bin_idx| {
            //     if (value[dim_idx] >= b[bin_idx] and value[dim_idx] < b[bin_idx + 1]) {
            //         bin_coordinate[dim_idx] = bin_idx;
            //         coord_counts += 1;
            //     }
            // }
        }
        // if (coord_counts != self.bins.len) {
        //     return;
        // }
        const index = self.coordinateToIndex(self.scratch_coord) catch |err| {
            std.log.err("{}\n", .{err});
            std.debug.panic("Cannot convert coordinate to index {any}\n", .{self.scratch_coord});
        };
        self.nentries += 1;
        self.contents[index] += 1;
    }

    pub const SliceIterator = struct {
        histogram: *const Histogram,
        slice: []*f64,
        slice_true_idxs: []usize,
        slice_idx: usize = 0,
        stride: usize = 0,
        num_slices: usize,
        pub fn next(iter: *SliceIterator) ?[]*f64 {
            if (iter.slice_idx >= iter.num_slices) return null;
            const nbins = iter.slice.len;
            for (0..nbins) |bin_idx| {
                const true_idx = iter.stride * bin_idx + iter.slice_idx % iter.stride + @divTrunc(iter.slice_idx, iter.stride) * iter.stride * nbins;
                iter.slice_true_idxs[bin_idx] = true_idx;
                iter.slice[bin_idx] = &iter.histogram.contents[true_idx];
            }
            iter.slice_idx += 1;
            return iter.slice;
        }
        pub fn init(allocator: std.mem.Allocator, histogram: *const Histogram, dimension: usize) !SliceIterator {
            var stride: usize = 1;
            for (0..dimension) |idx| stride *= (histogram.bins[idx].len - 1);
            var num_slices: usize = 1;
            for (0..histogram.bins.len) |idx| {
                if (idx == dimension) continue;
                num_slices *= (histogram.bins[idx].len - 1);
            }

            const slice = try allocator.alloc(*f64, histogram.bins[dimension].len - 1);
            const slice_true_idxs = try allocator.alloc(usize, histogram.bins[dimension].len - 1);
            return .{
                .slice = slice,
                .histogram = histogram,
                .num_slices = num_slices,
                .stride = stride,
                .slice_true_idxs = slice_true_idxs,
            };
        }
        pub fn deinit(self: *SliceIterator, allocator: std.mem.Allocator) void {
            allocator.free(self.slice);
            allocator.free(self.slice_true_idxs);
        }
    };

    pub fn sliceIterator(self: *const Histogram, allocator: std.mem.Allocator, dimension: usize) !SliceIterator {
        return try .init(allocator, self, dimension);
    }

    pub fn project(self: Histogram, allocator: Allocator, dimension: usize) ![]f64 {
        const projection = try allocator.alloc(f64, self.bins[dimension].len - 1);
        if (self.bins.len == 1) {
            if (dimension != 0) @panic("Cannot project");
            @memcpy(projection, self.contents);
            return projection;
        }
        for (projection) |*el| el.* = 0;
        var iter = try self.sliceIterator(allocator, dimension);
        defer iter.deinit(allocator);
        while (iter.next()) |slice| {
            for (slice, 0..) |el, idx| {
                const bin_volume = self.bin_volumes[iter.slice_true_idxs[idx]];
                projection[idx] += el.* * bin_volume;
            }
        }
        return projection;
    }

    pub fn clear(self: *Histogram) void {
        for (self.contents) |*c| c.* = 0;
        self.nentries = 0;
    }

    pub fn deinit(self: Histogram, allocator: Allocator) void {
        for (self.bins) |*b| {
            allocator.free(b.*);
        }
        allocator.free(self.bins);
        allocator.free(self.bin_volumes);
        allocator.free(self.contents);
        allocator.free(self.scratch_coord);
        allocator.free(self.scratch_point);
    }
};

fn createFromNormal(allocator: Allocator, nsamps: usize, hist_opts: Histogram.Options) !Histogram {
    const bins = try utils.linearSpacedBins(f64, allocator, -5, 5, 20);
    defer allocator.free(bins);

    var samps: std.ArrayList(f64) = try .initCapacity(allocator, nsamps);
    defer samps.deinit(allocator);

    var rng_gen = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..nsamps) |_| {
        samps.appendAssumeCapacity(rng_gen.random().floatNorm(f64));
    }

    const hist = try Histogram.init(allocator, &.{bins}, &.{samps.items}, hist_opts);
    return hist;
}

test "make histogram" {
    const allocator = std.testing.allocator;

    const points: [1][]const f64 = .{&[_]f64{ -1, 2, 4, 5, 1.2, 5.6, 9, 10, 11 }};
    const bins: []const f64 = try utils.linearSpacedBins(f64, allocator, 0, 10, 11);
    defer allocator.free(bins);

    const histogram: Histogram = try .init(allocator, &.{bins}, &points, .{ .density = false });
    defer histogram.deinit(allocator);

    const test_str = try std.fmt.allocPrint(allocator, "{any}", .{histogram.contents});
    defer allocator.free(test_str);

    std.testing.expect(std.mem.eql(u8, test_str, "{ 0, 1, 1, 0, 1, 2, 0, 0, 0, 1 }")) catch |e| {
        std.debug.print("{s}\n", .{test_str});
        return e;
    };

    try std.testing.expect(histogram.nentries == 6);

    const norm_histogram: Histogram = try .init(allocator, &.{bins}, &points, .{ .density = true });
    defer norm_histogram.deinit(allocator);

    const norm_str = try std.fmt.allocPrint(allocator, "{any}", .{norm_histogram.contents});
    defer allocator.free(norm_str);

    try std.testing.expect(std.mem.eql(u8, norm_str, "{ 0, 0.16666666666666666, 0.16666666666666666, 0, 0.16666666666666666, 0.3333333333333333, 0, 0, 0, 0.16666666666666666 }"));
}

test "clear" {
    const allocator = std.testing.allocator;
    var norm_histogram = try createFromNormal(allocator, 1000, .{});
    defer norm_histogram.deinit(allocator);
    norm_histogram.clear();
    try std.testing.expect(norm_histogram.nentries == 0);
    var allzero: bool = true;
    for (norm_histogram.contents) |c| {
        if (c != 0) allzero = false;
    }
    try std.testing.expect(allzero);
}

test "2d" {
    const allocator = std.testing.allocator;

    const xbins: []const f64 = try utils.linearSpacedBins(f64, allocator, -10, 0, 11);
    defer allocator.free(xbins);

    const ybins: []const f64 = try utils.linearSpacedBins(f64, allocator, 0, 10, 11);
    defer allocator.free(ybins);

    const pts: [2][]const f64 = .{
        &[_]f64{ -1, -2, -3, -4, -8, -3, -1, -8 },
        &[_]f64{ 1, 4, 4, 4, 4, 4, 4, 4 },
    };
    const histogram: Histogram = try .init(allocator, &.{ xbins, ybins }, &pts, .{});
    defer histogram.deinit(allocator);
    const p0 = try histogram.project(allocator, 0);
    defer allocator.free(p0);
    const p1 = try histogram.project(allocator, 1);
    defer allocator.free(p1);

    try std.testing.expect(std.mem.eql(f64, &.{ 0, 0, 2, 0, 0, 0, 1, 2, 1, 2 }, p0));
    try std.testing.expect(std.mem.eql(f64, &.{ 0, 1, 0, 0, 7, 0, 0, 0, 0, 0 }, p1));
}

test "clone" {
    const allocator = std.testing.allocator;
    const hist = try createFromNormal(allocator, 1000, .{});
    defer hist.deinit(allocator);

    const clone = try hist.clone(allocator);
    defer clone.deinit(allocator);
}
