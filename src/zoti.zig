const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Histogram = @import("histogram.zig").Histogram;

const GridPDFInterpolator = struct {
    grid: []const []const f64,
    // pdf_map: std.HashMapUnmanaged([]const f64, Histogram, utils.SliceHashContext, 80) = .empty,
    pdfs: [][]const f64,
    marginal_cdfs: [][][]const f64,
    marginal_qfs: [][][]const f64,
    // pdf_bins: []const []const f64,
    root_pdf: *Histogram,
    // The map should link points in the interpolation space to marginal CDFs, indexed by the dimension
    // cdf_map: std.HashMapUnmanaged([]const f64, []const []const f64, utils.SliceHashContext, 80) = .empty,

    pub fn init(allocator: Allocator, grid: []const []const f64, pdf_bins: []const []const f64) !GridPDFInterpolator {
        var owned_grid = try allocator.alloc([]f64, grid.len);
        var tot_size: usize = 1;
        for (0..grid.len) |dim| {
            owned_grid[dim] = try allocator.dupe(f64, grid[dim]);
            tot_size *= grid[dim].len;
        }

        const pdfs = try allocator.alloc([]const f64, tot_size);
        const marginal_cdfs = try allocator.alloc([][]const f64, tot_size);
        const marginal_qfs = try allocator.alloc([][]const f64, tot_size);

        const root_hist = try allocator.create(Histogram);
        root_hist.* = try .init(allocator, pdf_bins, null, .{});
        return .{
            .grid = owned_grid,
            .pdfs = pdfs,
            .root_pdf = root_hist,
            .marginal_cdfs = marginal_cdfs,
            .marginal_qfs = marginal_qfs,
        };
    }

    pub fn deinit(self: GridPDFInterpolator, allocator: Allocator) void {
        for (self.marginal_cdfs) |cdfs| {
            for (cdfs) |cdf| allocator.free(cdf);
            allocator.free(cdfs);
        }
        allocator.free(self.marginal_cdfs);

        for (self.marginal_qfs) |qfs| {
            for (qfs) |qf| allocator.free(qf);
            allocator.free(qfs);
        }
        allocator.free(self.marginal_qfs);

        for (self.pdfs) |pdf| allocator.free(pdf);
        allocator.free(self.pdfs);
        for (self.grid) |g| allocator.free(g);
        allocator.free(self.grid);
        self.root_pdf.deinit(allocator);
        allocator.destroy(self.root_pdf);
    }

    fn gridPointToFlatIdx(grid: []const []const f64, interp_point: []const f64) ?usize {
        var flat_idx: usize = 0;

        var stride: usize = 1;
        for (0..interp_point.len) |dim| {
            const idx = std.mem.find(f64, grid[dim], &.{interp_point[dim]});
            if (idx) |id| {
                flat_idx += stride * id;
            } else {
                return null;
            }
            stride *= grid[dim].len;
        }
        return flat_idx;
    }

    pub fn calculateFlatIdx(self: GridPDFInterpolator, interp_point: []const f64) !usize {
        const flat_idx = gridPointToFlatIdx(self.grid, interp_point);
        if (flat_idx) |idx| {
            return idx;
        }
        return error.GridError;
    }

    pub fn setAtFromPoints(
        self: GridPDFInterpolator,
        allocator: Allocator,
        interp_point: []const f64,
        points: []const []const f64,
    ) !void {
        // Just to be extra safe
        self.root_pdf.clear();
        defer self.root_pdf.clear();

        const flat_idx = try self.calculateFlatIdx(interp_point);

        // TODO: Take options
        self.root_pdf.loadNewPoints(points, .{ .density = true, .zero_pad = 1e-32 });

        self.pdfs[flat_idx] = try allocator.dupe(f64, self.root_pdf.contents);

        var marginal_cdfs = try allocator.alloc([]const f64, self.root_pdf.bins.len);
        var marginal_qfs = try allocator.alloc([]const f64, self.root_pdf.bins.len);
        for (0..self.root_pdf.bins.len) |pdf_dim| {
            const marginal = try self.root_pdf.project(allocator, pdf_dim);
            defer allocator.free(marginal);

            const probabilities = try utils.linearSpacedBins(f64, allocator, 0, 1, self.root_pdf.bins[pdf_dim].len);
            defer allocator.free(probabilities);

            marginal_cdfs[pdf_dim] = try stats.getCDF(allocator, marginal, self.root_pdf.bins[pdf_dim]);
            marginal_qfs[pdf_dim] = try stats.pdfToQF(allocator, self.root_pdf.bins[pdf_dim], marginal, probabilities);
        }
        self.marginal_cdfs[flat_idx] = marginal_cdfs;
        self.marginal_qfs[flat_idx] = marginal_qfs;
    }

    const BoundingBox = struct {
        /// The coordinates of the point
        points: []const []const f64,
        /// The flat indices that can be used to index flat arrays of CDFs and QFs
        idxs: []const usize,
    };
    pub fn boundingBox(self: GridPDFInterpolator, allocator: Allocator, point: []const f64) !BoundingBox {
        const edges = self.grid;
        const num_points = std.math.pow(usize, 2, edges.len);
        const points = try allocator.alloc([]f64, num_points);

        const idxs = try allocator.alloc(usize, num_points);

        const lbs = try allocator.alloc(usize, edges.len);
        defer allocator.free(lbs);

        for (edges, 0..) |edge, idx| {
            if (point[idx] > edges[idx][edges[idx].len - 1] or point[idx] < edges[idx][0]) return error.GridError;
            // lb is first eq or gt entry -> lb - 1 is lower and lb is upper
            lbs[idx] = std.sort.lowerBound(f64, edge, point[idx], utils.cmpCtx(f64).compFn);
        }

        var mask: u64 = 0x00;
        for (0..num_points) |pt| {
            points[pt] = try allocator.alloc(f64, edges.len);
            for (0..edges.len) |dim_idx| {
                const t: u64 = mask & std.math.pow(usize, 2, dim_idx);
                if (t == 0) {
                    points[pt][dim_idx] = edges[dim_idx][lbs[dim_idx] - 1];
                } else {
                    points[pt][dim_idx] = edges[dim_idx][lbs[dim_idx]];
                }
            }
            idxs[pt] = try calculateFlatIdx(self, points[pt]);
            mask += 1;
        }
        return .{ .idxs = idxs, .points = points };
    }

    pub fn getWeights(allocator: Allocator, interp_point: []const f64, points: []const []const f64) ![]f64 {
        // FIXME: Dumb average
        _ = interp_point;
        const weights = try allocator.alloc(f64, points.len);
        for (weights) |*w| w.* = @as(f64, @floatFromInt(1 / points.len));
        return weights;
    }

    pub fn calculateBarycenters(
        self: GridPDFInterpolator,
        allocator: Allocator,
        bounding_box: BoundingBox,
        weights: []const f64,
    ) ![][]f64 {
        //
        const barycenters = try allocator.alloc([]f64, self.root_pdf.bins.len);
        for (0..barycenters.len) |dim_idx| {
            const barycenter = try allocator.alloc(f64, self.root_pdf.bins[dim_idx].len);
            for (barycenter) |*b| b.* = 0;
            barycenters[dim_idx] = barycenter;
        }

        for (0..bounding_box.idxs.len) |point_idx| {
            for (0..barycenters.len) |dim_idx| {
                for (barycenters[dim_idx], 0..) |*b, pdf_idx| {
                    b.* += weights[point_idx] * self.marginal_qfs[point_idx][dim_idx][pdf_idx];
                }
            }
        }
        return barycenters;
    }

    pub fn generatePDF(self: GridPDFInterpolator, allocator: Allocator, interp_point: []const f64) ![]f64 {
        const bounding_box = try self.boundingBox(allocator, interp_point);
        defer {
            for (bounding_box.points) |pt| allocator.free(pt);
            allocator.free(bounding_box.points);
            allocator.free(bounding_box.idxs);
        }

        const weights = try getWeights(allocator, interp_point, bounding_box.points);
        defer allocator.free(weights);

        const barycenters = try self.calculateBarycenters(allocator, bounding_box, weights);
        defer {
            for (barycenters) |b| allocator.free(b);
            allocator.free(barycenters);
        }
        if (true) return error.TODO;

        // const qf = try allocator.alloc(f64, self.marginal_qfs[0].len);
        // for (qf) |*q| q.* = 0;
        // // Mixed up dims below... remember that we need qf for each marginal
        // for (points, 0..) |pt, pt_idx| {
        //     const idx = gridPointToFlatIdx(self.grid, pt).?;
        //     for (self.marginal_qfs[idx]) |c| {
        //         for (qf.len) |i| {
        //             qf[idx] += weights[pt_idx] * c;
        //         }
        //     }
        // }
        return &.{};
    }
};

fn createInterp(allocator: Allocator, seed: u64) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var rng: std.Random.DefaultPrng = .init(seed);

    const gridx = try utils.linearSpacedBins(f64, arena.allocator(), -10, 10, 10);
    const gridy = try utils.linearSpacedBins(f64, arena.allocator(), 1, 10, 10);

    const pdf_bins = try utils.linearSpacedBins(f64, allocator, -20, 20, 100);
    defer allocator.free(pdf_bins);

    const interp: GridPDFInterpolator = try .init(allocator, &.{ gridx, gridy }, &.{pdf_bins});
    defer interp.deinit(allocator);
    const data = try allocator.alloc(f64, 1000);
    defer allocator.free(data);
    for (0..gridx.len) |i| {
        for (0..gridy.len) |j| {
            for (0..data.len) |idx| {
                data[idx] = rng.random().floatNorm(f64) * gridy[j] + gridx[i];
            }
            try interp.setAtFromPoints(allocator, &.{ gridx[i], gridy[j] }, &.{data});
        }
    }
    _ = try interp.generatePDF(allocator, &.{ 0.2, 1.5 });
}

const stats = @import("stats.zig");
const utils = @import("utilities.zig");
const histogram = @import("histogram.zig");

test {
    // const allocator = std.testing.allocator;
    // try createInterp(allocator, std.testing.random_seed);

    _ = histogram;
    _ = stats;
    _ = utils;
}
