const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.zoti);

pub const Histogram = @import("histogram.zig").Histogram;

pub const GridPDFInterpolatorOptions = struct {
    probability_steps: usize = 1e5,
};
pub const GridPDFInterpolator = struct {
    grid: []const []const f64,
    // pdf_map: std.HashMapUnmanaged([]const f64, Histogram, utils.SliceHashContext, 80) = .empty,
    pdfs: [][]const f64,
    marginal_cdfs: [][][]const f64,
    marginal_qfs: [][][]const f64,
    probabilities: []const f64,
    // pdf_bins: []const []const f64,
    root_pdf: *Histogram,
    options: GridPDFInterpolatorOptions = .{},
    // The map should link points in the interpolation space to marginal CDFs, indexed by the dimension
    // cdf_map: std.HashMapUnmanaged([]const f64, []const []const f64, utils.SliceHashContext, 80) = .empty,

    pub fn init(
        allocator: Allocator,
        grid: []const []const f64,
        pdf_bins: []const []const f64,
        options: GridPDFInterpolatorOptions,
    ) !GridPDFInterpolator {
        var owned_grid = try allocator.alloc([]f64, grid.len);
        var tot_size: usize = 1;
        for (0..grid.len) |dim| {
            owned_grid[dim] = try allocator.dupe(f64, grid[dim]);
            tot_size *= grid[dim].len;
        }

        const pdfs = try allocator.alloc([]const f64, tot_size);
        const marginal_cdfs = try allocator.alloc([][]const f64, tot_size);
        const marginal_qfs = try allocator.alloc([][]const f64, tot_size);

        const prob_bins = try utils.linearSpacedBins(f64, allocator, 0, 1, options.probability_steps);
        defer allocator.free(prob_bins);
        const probs = try utils.centers(f64, allocator, prob_bins);

        const root_hist = try allocator.create(Histogram);
        root_hist.* = try .init(allocator, pdf_bins, null, .{});
        return .{
            .grid = owned_grid,
            .pdfs = pdfs,
            .root_pdf = root_hist,
            .marginal_cdfs = marginal_cdfs,
            .marginal_qfs = marginal_qfs,
            .probabilities = probs,
            .options = options,
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

        allocator.free(self.probabilities);

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
        log.debug("Loading PDF for {any}: {any}", .{ interp_point, self.pdfs[flat_idx] });

        var marginal_cdfs = try allocator.alloc([]const f64, self.root_pdf.bins.len);
        var marginal_qfs = try allocator.alloc([]const f64, self.root_pdf.bins.len);
        for (0..self.root_pdf.bins.len) |pdf_dim| {
            const marginal = try self.root_pdf.project(allocator, pdf_dim);
            log.debug("Marginal: {any}", .{marginal});
            defer allocator.free(marginal);

            marginal_cdfs[pdf_dim] = try stats.getCDF(allocator, marginal, self.root_pdf.bins[pdf_dim]);
            for (marginal_cdfs[pdf_dim]) |*c| @constCast(c).* /= marginal_cdfs[pdf_dim][marginal_cdfs[pdf_dim].len - 1];
            marginal_qfs[pdf_dim] = try stats.pdfToQF(allocator, self.root_pdf.bins[pdf_dim], marginal, self.probabilities);
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

    pub fn getWeights(allocator: std.mem.Allocator, points: []const []const f64, interp_point: []const f64) ![]f64 {
        var total: f64 = 0;
        var weights = try allocator.alloc(f64, points.len);

        for (points, 0..) |pt, pt_idx| {
            var area: f64 = 1;
            for (pt, 0..) |p, dim_idx| {
                area *= @abs(interp_point[dim_idx] - p);
            }
            weights[pt_idx] = area;
            total += area;
        }

        for (weights) |*w| w.* /= total;

        switch (weights.len) {
            2 => {
                const w0 = weights[0];
                const w1 = weights[1];
                weights[0] = w1;
                weights[1] = w0;
            },
            4 => {
                const w0 = weights[0];
                const w1 = weights[1];
                const w2 = weights[2];
                const w3 = weights[3];
                weights[0] = w3;
                weights[1] = w2;
                weights[2] = w1;
                weights[3] = w0;
            },
            else => @panic("Cannot get weights for dimension of problem."),
        }

        return weights;
    }

    pub fn calculateBarycenters(
        self: GridPDFInterpolator,
        allocator: Allocator,
        bounding_box: BoundingBox,
        weights: []const f64,
    ) ![][]f64 {
        const barycenters = try allocator.alloc([]f64, self.root_pdf.bins.len);
        for (0..barycenters.len) |dim_idx| {
            const barycenter = try allocator.alloc(f64, self.probabilities.len);
            for (barycenter) |*b| b.* = 0;
            barycenters[dim_idx] = barycenter;
        }

        for (0..bounding_box.idxs.len) |point_idx| {
            const flat_idx = bounding_box.idxs[point_idx];
            for (0..barycenters.len) |dim_idx| {
                for (barycenters[dim_idx], 0..) |*b, b_idx| {
                    b.* += weights[point_idx] * self.marginal_qfs[flat_idx][dim_idx][b_idx];
                }
            }
        }
        return barycenters;
    }

    // pub fn transportSlice(slice: []f64, map: []const f64) void {}

    pub fn generatePDF(self: GridPDFInterpolator, allocator: Allocator, interp_point: []const f64) ![]f64 {
        const bounding_box = try self.boundingBox(allocator, interp_point);
        defer {
            for (bounding_box.points) |pt| allocator.free(pt);
            allocator.free(bounding_box.points);
            allocator.free(bounding_box.idxs);
        }

        const weights = try getWeights(allocator, bounding_box.points, interp_point);
        defer allocator.free(weights);

        const barycenters = try self.calculateBarycenters(allocator, bounding_box, weights);
        defer {
            for (barycenters) |b| allocator.free(b);
            allocator.free(barycenters);
        }

        const pushed_pdfs = try allocator.alloc([]f64, bounding_box.idxs.len);
        for (pushed_pdfs) |*p| {
            p.* = try allocator.alloc(f64, self.root_pdf.contents.len);
            for (p.*) |*c| c.* = 0;
        }
        defer {
            for (pushed_pdfs) |p| allocator.free(p);
            allocator.free(pushed_pdfs);
        }

        for (0..self.root_pdf.bins.len) |pdf_dim| {
            const centers = try utils.centers(f64, allocator, self.root_pdf.bins[pdf_dim]);
            defer allocator.free(centers);
            for (0..bounding_box.points.len) |point_idx| {
                const bary_cdf = try stats.qfToCDF(allocator, self.root_pdf.bins[pdf_dim], self.probabilities, barycenters[pdf_dim]);
                log.debug("Barycenter CDF: {any}", .{bary_cdf});
                defer allocator.free(bary_cdf);
                const flat_idx = bounding_box.idxs[point_idx];
                const qf = self.marginal_qfs[flat_idx][pdf_dim];
                log.debug("QF: {any}", .{qf});
                const map = try allocator.alloc(f64, centers.len);
                defer allocator.free(map);

                for (map, 0..) |*m, idx| {
                    if (bary_cdf[idx] < self.probabilities[0]) {
                        m.* = centers[0];
                    } else if (bary_cdf[idx] > self.probabilities[self.probabilities.len - 1]) {
                        m.* = centers[centers.len - 1];
                    } else {
                        m.* = utils.interp(f64, self.probabilities, qf, bary_cdf[idx], .flat);
                    }
                }

                log.debug("Map: {any}", .{map});

                const slice_pdf = try allocator.alloc(f64, centers.len);
                defer allocator.free(slice_pdf);
                const pushed_cdf = try allocator.alloc(f64, centers.len);
                defer allocator.free(pushed_cdf);
                @memcpy(self.root_pdf.contents, self.pdfs[flat_idx]);
                var iter = try self.root_pdf.sliceIterator(allocator, pdf_dim);
                defer iter.deinit(allocator);
                while (iter.next()) |slice| {
                    for (slice, 0..) |s, i| slice_pdf[i] = s.*;
                    const slice_cdf = try stats.getCDF(allocator, slice_pdf, self.root_pdf.bins[pdf_dim]);
                    log.debug("Slice CDF: {any}", .{slice_cdf});
                    defer allocator.free(slice_cdf);
                    for (0..pushed_cdf.len) |idx| {
                        if (map[0] == map[1] and map[idx] == map[0]) {
                            pushed_cdf[idx] = 0;
                        } else if (centers[idx] > map[map.len - 1]) {
                            pushed_cdf[idx] = slice_cdf[slice_cdf.len - 1];
                        } else {
                            pushed_cdf[idx] = utils.interp(f64, centers, slice_cdf, map[idx], .flat);
                        }
                        log.debug("Pushed CDF interp: {d}, {d}", .{ map[idx], pushed_cdf[idx] });
                    }
                    const pushed_pdf = try stats.cdfToPDF(allocator, self.root_pdf.bins[pdf_dim], pushed_cdf);
                    defer allocator.free(pushed_pdf);
                    for (iter.slice_true_idxs, 0..) |true_idx, idx| pushed_pdfs[point_idx][true_idx] += pushed_pdf[idx];
                }
            }
        }

        const result_pdf = try allocator.alloc(f64, self.root_pdf.contents.len);
        for (result_pdf) |*c| c.* = 0;

        for (0..bounding_box.points.len) |point_idx| {
            for (pushed_pdfs[point_idx], 0..) |p, idx| {
                result_pdf[idx] += p * weights[point_idx];
            }
        }

        return result_pdf;
    }
};

const stats = @import("stats.zig");
const utils = @import("utilities.zig");
const histogram = @import("histogram.zig");

test {
    _ = histogram;
    _ = stats;
    _ = utils;
}
