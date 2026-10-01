const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utilities.zig");

pub fn linearSpacedBins(comptime T: type, allocator: Allocator, start: T, stop: T, nbins: usize) ![]T {
    switch (@typeInfo(T)) {
        .float => {},
        inline else => @compileError("Cannot create bins from non-float inputs"),
    }
    if (nbins == 0) return &.{};
    var bins = try allocator.alloc(T, nbins);
    const step = (stop - start) / @as(T, @floatFromInt(nbins - 1));
    for (0..nbins) |idx| {
        bins[idx] = start + @as(f64, @floatFromInt(idx)) * step;
    }
    return bins;
}

pub fn diff(comptime T: type, allocator: Allocator, array: []const T) ![]T {
    var diffs = try allocator.alloc(T, array.len - 1);
    for (0..array.len - 1) |idx| {
        diffs[idx] = array[idx + 1] - array[idx];
    }
    return diffs;
}

pub fn centers(comptime T: type, allocator: Allocator, array: []const T) ![]T {
    var diffs = try allocator.alloc(T, array.len - 1);
    for (0..array.len - 1) |idx| {
        diffs[idx] = (array[idx + 1] + array[idx]) / 2;
    }
    return diffs;
}

pub fn cmpCtx(comptime T: type) type {
    return struct {
        pub fn compFn(a: T, b: T) std.math.Order {
            return std.math.order(a, b);
        }
    };
}
/// Linear interpolation with interpolation past the edges
const EdgeBehavior = enum {
    flat,
    linear,
};
pub fn interp(comptime T: type, xs: []const T, ys: []const T, pt: T, edge: EdgeBehavior) T {
    const cmp = cmpCtx(T);
    if (edge == .flat) {
        if (pt > xs[xs.len - 1]) return ys[ys.len - 1];
        if (pt < xs[0]) return ys[0];
    }
    var ub = std.sort.lowerBound(T, xs, pt, cmp.compFn);
    if (ub == xs.len) ub -= 1;
    if (ub == 0) ub += 1;
    if (xs[ub] == xs[ub - 1]) {
        if (@abs(pt - xs[0]) < @abs(xs[xs.len - 1] - pt)) {
            return ys[0];
        } else {
            return ys[ys.len - 1];
        }
    }
    const t = (pt - xs[ub - 1]) / (xs[ub] - xs[ub - 1]);
    const lerp = std.math.lerp(ys[ub - 1], ys[ub], t);
    if (!std.math.isFinite(lerp)) {
        std.log.err("Non-finite lerp: {d}", .{lerp});
        std.log.err("\t{d}, {d}, {d}, {d}, {d},", .{ pt, xs[ub - 1], xs[ub], ys[ub - 1], ys[ub] });
    }
    return lerp;
}

test "interp" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const xs = try utils.linearSpacedBins(f64, allocator, 0, 10, 11);
    const ys = try utils.linearSpacedBins(f64, allocator, 0, 10, 11);

    var t = interp(f64, xs, ys, -0.5, .linear);
    std.testing.expect(t == -0.5) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, -0.5, .flat);
    std.testing.expect(t == 0.0) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, 0.0, .linear);
    std.testing.expect(t == 0.0) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, 0.5, .linear);
    std.testing.expect(t == 0.5) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, 9.5, .linear);
    std.testing.expect(t == 9.5) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, 10.5, .linear);
    std.testing.expect(t == 10.5) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
    t = interp(f64, xs, ys, 10.5, .flat);
    std.testing.expect(t == 10.0) catch |e| {
        std.log.err("Got {d}", .{t});
        return e;
    };
}

test "diffs" {
    const allocator = std.testing.allocator;
    const a = [_]f64{ 1, 2, 4, 40 };
    const res = try diff(f64, allocator, &a);
    defer allocator.free(res);
    try std.testing.expect(std.mem.eql(f64, res, &[_]f64{ 1, 2, 36 }));
}

test "centers" {
    const allocator = std.testing.allocator;
    const a = [_]f64{ 1, 2, 4, 40 };
    const res = try centers(f64, allocator, &a);
    defer allocator.free(res);
    const exp = &[_]f64{ 1.5, 3, 22 };
    std.testing.expect(std.mem.eql(f64, res, exp)) catch |e| {
        std.log.err("Got {any} and expected {any}", .{ res, exp });
        return e;
    };
}

pub const SliceHashContext = struct {
    pub fn hash(self: @This(), slice: []const f64) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        for (slice) |val| {
            const bits: u64 = @bitCast(val);
            hasher.update(std.mem.asBytes(&bits));
        }

        return hasher.final();
    }

    pub fn eql(self: @This(), a: []const f64, b: []const f64) bool {
        _ = self;
        return std.mem.eql(f64, a, b);
    }
};
