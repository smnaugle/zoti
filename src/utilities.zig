const std = @import("std");
const Allocator = std.mem.Allocator;

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
