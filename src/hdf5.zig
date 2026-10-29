const std = @import("std");

pub const hid_t = i64;
pub const htri_t = c_int;
pub const herr_t = c_int;
pub const hsize_t = usize;
pub const hssize_t = i64;

pub const H5F_ACC_CODE = enum(hid_t) {
    H5F_ACC_RDONLY = 0x0000,
    H5F_ACC_RDWR = 0x0001,
    H5F_ACC_TRUNC = 0x0002,
    H5F_ACC_EXCL = 0x0004,
    H5F_ACC_CREAT = 0x0010,
    H5F_ACC_SWMR_WRITE = 0x0020,
    H5F_ACC_SWMR_READ = 0x0040,
};

// File functions
pub extern fn H5Fcreate(filename: [*c]const u8, flags: H5F_ACC_CODE, fcpl_id: PropListAcc, fapl_id: PropListAcc) callconv(.c) hid_t;
pub extern fn H5Fopen(filename: [*c]const u8, flags: H5F_ACC_CODE, fapl_id: PropListAcc) hid_t;
pub extern fn H5Fclose(file_id: hid_t) herr_t;

// Group function
pub extern fn H5Gcreate2(loc_id: hid_t, name: [*c]const u8, lcpl_id: PropListAcc, gcpl_id: PropListAcc, gapl_id: PropListAcc) hid_t;
pub fn H5Gcreate(loc_id: hid_t, name: [*c]const u8, lcpl_id: PropListAcc, gcpl_id: PropListAcc, gapl_id: PropListAcc) hid_t {
    return H5Gcreate2(loc_id, name, lcpl_id, gcpl_id, gapl_id);
}
pub extern fn H5Gclose(group_id: hid_t) herr_t;
pub extern fn H5Gopen2(group_id: hid_t, name: [*c]const u8, gapl_id: PropListAcc) hid_t;
pub fn H5Gopen(group_id: hid_t, name: [*c]const u8, gapl_id: PropListAcc) hid_t {
    return H5Gopen2(group_id, name, gapl_id);
}

// Dataset functions
pub extern fn H5Dopen2(file_id: hid_t, name: [*c]const u8, dapl_id: PropListAcc) hid_t;
pub fn H5Dopen(file_id: hid_t, name: [*c]const u8, dapl_id: PropListAcc) hid_t {
    return H5Dopen2(file_id, name, dapl_id);
}
pub extern fn H5Dread(dset_id: hid_t, mem_type_id: hid_t, mem_space_id: hid_t, file_space_id: hid_t, fapl_id: PropListAcc, buf: *anyopaque) herr_t;
pub extern fn H5Dcreate2(loc_id: hid_t, name: [*c]const u8, type_id: hid_t, space_id: hid_t, lcpl_id: hid_t, dcpl_id: PropListAcc, dapl_id: PropListAcc) hid_t;
pub fn H5Dcreate(loc_id: hid_t, name: [*c]const u8, type_id: hid_t, space_id: hid_t, lcpl_id: hid_t, dcpl_id: PropListAcc, dapl_id: PropListAcc) hid_t {
    return H5Dcreate2(loc_id, name, type_id, space_id, lcpl_id, dcpl_id, dapl_id);
}
pub extern fn H5Dwrite(dset_id: hid_t, mem_type_id: hid_t, mem_space_id: hid_t, file_space_id: hid_t, dxpl_id: hid_t, buf: *const anyopaque) herr_t;
pub extern fn H5Dget_type(dset_id: hid_t) hid_t;
pub extern fn H5Dget_space(dset_id: hid_t) hid_t;
pub extern fn H5Dclose(dset_id: hid_t) herr_t;

// Dataspace functions
pub const H5S_ALL: c_int = 0;
pub const H5S_seloper_t = enum(c_int) {
    H5S_SELECT_NOOP = -1,
    H5S_SELECT_SET = 0,
    H5S_SELECT_OR,
    H5S_SELECT_AND,
    H5S_SELECT_XOR,
    H5S_SELECT_NOTB,
    H5S_SELECT_NOTA,
    H5S_SELECT_APPEND,
    H5S_SELECT_PREPEND,
    H5S_SELECT_INVALID,
};
pub extern fn H5Sselect_hyperslab(
    space_id: hid_t,
    op: H5S_seloper_t,
    start: [*c]const hsize_t,
    stride: [*c]const hsize_t,
    count: [*c]const hsize_t,
    block: [*c]const hsize_t,
) herr_t;
pub extern fn H5Screate_simple(rank: c_int, dims: [*c]const hsize_t, max_dims: [*c]const hsize_t) hid_t;
pub extern fn H5Sclose(space_id: hid_t) herr_t;
pub extern fn H5Sget_simple_extent_dims(space_id: hid_t, dims: [*c]const hsize_t, max_dims: [*c]const hsize_t) c_int;
pub extern fn H5Sget_simple_extent_npoints(space_id: hid_t) hssize_t;

// Types
// global types
pub const H5Types = struct {
    pub extern const H5T_NATIVE_SCHAR_g: hid_t;
    pub extern const H5T_NATIVE_UCHAR_g: hid_t;
    pub extern const H5T_NATIVE_SHORT_g: hid_t;
    pub extern const H5T_NATIVE_USHORT_g: hid_t;
    pub extern const H5T_NATIVE_INT_g: hid_t;
    pub extern const H5T_NATIVE_UINT_g: hid_t;
    pub extern const H5T_NATIVE_LONG_g: hid_t;
    pub extern const H5T_NATIVE_ULONG_g: hid_t;
    pub extern const H5T_NATIVE_LLONG_g: hid_t;
    pub extern const H5T_NATIVE_ULLONG_g: hid_t;
    pub extern const H5T_NATIVE_FLOAT16_g: hid_t;
    pub extern const H5T_NATIVE_FLOAT_g: hid_t;
    pub extern const H5T_NATIVE_DOUBLE_g: hid_t;
    pub extern const H5T_NATIVE_LDOUBLE_g: hid_t;
    pub extern const H5T_NATIVE_FLOAT_COMPLEX_g: hid_t;
    pub extern const H5T_NATIVE_DOUBLE_COMPLEX_g: hid_t;
    pub extern const H5T_NATIVE_LDOUBLE_COMPLEX_g: hid_t;
    pub extern const H5T_NATIVE_B8_g: hid_t;
    pub extern const H5T_NATIVE_B16_g: hid_t;
    pub extern const H5T_NATIVE_B32_g: hid_t;
    pub extern const H5T_NATIVE_B64_g: hid_t;
    pub extern const H5T_NATIVE_OPAQUE_g: hid_t;
    pub extern const H5T_NATIVE_HADDR_g: hid_t;
    pub extern const H5T_NATIVE_HSIZE_g: hid_t;
    pub extern const H5T_NATIVE_HSSIZE_g: hid_t;
    pub extern const H5T_NATIVE_HERR_g: hid_t;
    pub extern const H5T_NATIVE_HBOOL_g: hid_t;
    pub extern const H5T_C_S1_g: hid_t;

    pub fn getType(t_id: hid_t) []const u8 {
        inline for (@typeInfo(@This()).@"struct".decls) |field| {
            if (comptime std.mem.eql(u8, field.name, "getType")) continue;
            const t_val: hid_t = @field(H5Types, field.name);
            if (H5Tequal(t_id, t_val) == 1) {
                return field.name;
            }
        }
        unreachable;
    }
};

pub const H5T_VARIABLE: usize = std.math.maxInt(usize);
pub const H5T_STR_NULLTERM: usize = 0;

const H5T_class_t = enum(c_int) {
    H5T_NO_CLASS = -1,
    H5T_INTEGER = 0,
    H5T_FLOAT = 1,
    H5T_TIME = 2,
    H5T_STRING = 3,
    H5T_BITFIELD = 4,
    H5T_OPAQUE = 5,
    H5T_COMPOUND = 6,
    H5T_REFERENCE = 7,
    H5T_ENUM = 8,
    H5T_VLEN = 9,
    H5T_ARRAY = 10,
    H5T_COMPLEX = 11,

    H5T_NCLASSES,
};
pub extern fn H5Tget_native_type(type_id: hid_t, direction: c_int) hid_t;
pub extern fn H5Tget_class(type_id: hid_t) hid_t;
pub extern fn H5Tget_super(type_id: hid_t) hid_t;
pub extern fn H5Tequal(type1_id: hid_t, type2_id: hid_t) hid_t;
pub extern fn H5Tcopy(type_id: hid_t) hid_t;
pub extern fn H5Tset_size(type_id: hid_t, size: usize) herr_t;
pub extern fn H5Tset_strpad(type_id: hid_t, size: usize) herr_t;

// Object related information
pub const H5OInfoTypes = enum(c_uint) {
    H5O_INFO_BASIC = 0x0001,
};
pub const H5OToken = extern struct {
    __token: [16]u8 = undefined,
};
pub const H5OType = enum(c_int) {
    H5O_TYPE_UNKNOWN = -1,
    H5O_TYPE_GROUP,
    H5O_TYPE_DATASET,
    H5O_TYPE_NAMED_DATATYPE,
    H5O_TYPE_MAP,
    H5O_TYPE_NTYPES,
};
pub const H5OInfo = extern struct {
    fileno: c_ulong = 0,
    token: H5OToken = .{},
    type: H5OType = .H5O_TYPE_UNKNOWN,
    rc: c_uint = 0,
    atime: std.c.time_t = 0,
    mtime: std.c.time_t = 0,
    ctime: std.c.time_t = 0,
    btime: std.c.time_t = 0,
    num_attrs: hsize_t = 0,
};
pub extern fn H5Oget_info_by_name3(loc_id: hid_t, name: [*c]const u8, info: *H5OInfo, fields: H5OInfoTypes, fapl_id: PropListAcc) herr_t;
pub fn H5Oget_info_by_name(loc_id: hid_t, name: [*c]const u8, info: *H5OInfo, fields: H5OInfoTypes, fapl_id: PropListAcc) herr_t {
    return H5Oget_info_by_name3(loc_id, name, info, fields, fapl_id);
}
// Link related information
pub const H5TCset = enum(c_int) {
    H5T_CSET_ERROR = -1,
    H5T_CSET_ASCII,
    H5T_CSET_UTF8,
};
pub const H5LType = enum(c_int) {
    H5L_TYPE_ERROR = -1,
    H5L_TYPE_HARD,
    H5L_TYPE_SOFT,
    H5L_TYPE_EXTERNAL,
    H5L_TYPE_MAX,
};

const H5LInfoUnion = extern union {
    token: H5OToken,
    val_size: isize,
};
pub const H5LInfo = extern struct {
    corder: i64 = 0,
    corder_valid: bool = false,
    cset: H5TCset = .H5T_CSET_ERROR,
    type: H5LType = .H5L_TYPE_ERROR,
    u: H5LInfoUnion = .{ .val_size = 0 },
};
pub const IterCallback = *const fn (hid_t, [*c]const u8, ?*H5LInfo, ?*anyopaque) callconv(.c) herr_t;
pub extern fn H5Literate_by_name2(hid_t, [*c]const u8, H5Index_Type, H5IterOrder, ?*hsize_t, IterCallback, ?*anyopaque, PropListAcc) hid_t;
pub fn H5Literate_by_name(lock_id: hid_t, group_name: [*c]const u8, idx_type: H5Index_Type, order: H5IterOrder, idx: ?*hsize_t, op: IterCallback, op_data: ?*anyopaque, lapl_id: PropListAcc) hid_t {
    return H5Literate_by_name2(lock_id, group_name, idx_type, order, idx, op, op_data, lapl_id);
}
pub extern fn H5Lexists(file_id: hid_t, link_name: [*c]const u8, access: PropListAcc) htri_t;
pub const H5Index_Type = enum(c_int) {
    H5_INDEX_UNKNOWN = -1,
    H5_INDEX_NAME,
    H5_INDEX_CRT_ORDER,
    H5_INDEX_N,
};
pub const H5IterOrder = enum(c_int) {
    H5_ITER_UNKNOWN = -1,
    H5_ITER_INC,
    H5_ITER_DEC,
    H5_ITER_NATIVE,
    H5_ITER_N,
};

// Links
pub const PropListAcc = enum(hid_t) {
    H5P_DEFAULT = 0x0,
};
pub extern const H5P_CLS_LINK_CREATE_ID_g: hid_t;
pub extern fn H5Pcreate(cls_id: hid_t) hid_t;
pub extern fn H5Pclose(plist_id: hid_t) herr_t;

// Better bindings
pub const File = struct {
    id: hid_t,
    is_open: bool = false,
    open_groups: std.ArrayList(hid_t) = .empty,

    arena: *std.heap.ArenaAllocator,

    pub const OpenOptions = struct {
        access: H5F_ACC_CODE,
    };

    pub fn create(allocator: std.mem.Allocator, filename: []const u8, options: OpenOptions) !File {
        const arena_ptr = try allocator.create(std.heap.ArenaAllocator);
        arena_ptr.* = .init(allocator);
        errdefer {
            arena_ptr.deinit();
            allocator.destroy(arena_ptr);
        }
        const filename_cstr = try arena_ptr.allocator().dupeSentinel(u8, filename, 0x00);
        const file = H5Fcreate(filename_cstr, options.access, PropListAcc.H5P_DEFAULT, PropListAcc.H5P_DEFAULT);
        if (file < 0) return error.FileOpenError;
        return .{ .id = file, .is_open = true, .open_groups = .empty, .arena = arena_ptr };
    }

    pub fn open(allocator: std.mem.Allocator, filename: []const u8, options: OpenOptions) !File {
        const arena_ptr = try allocator.create(std.heap.ArenaAllocator);
        arena_ptr.* = .init(allocator);
        const filename_cstr = try arena_ptr.allocator().dupeSentinel(u8, filename, 0x00);
        const file = H5Fopen(filename_cstr, options.access, .H5P_DEFAULT);
        if (file < 0) return error.FileOpenError;
        return .{ .id = file, .is_open = true, .open_groups = .empty, .arena = arena_ptr };
    }

    pub fn close(self: File, allocator: std.mem.Allocator) void {
        self.arena.deinit();
        allocator.destroy(self.arena);
        if (self.is_open) {
            const err = H5Fclose(self.id);
            if (err != 0) std.debug.panic("Could not close file, error code: {d}", .{err});
        }
    }

    pub fn getDataset(self: File, field: []const u8, root: []const u8) !H5Dataset {
        return try H5Dataset.init(self, field, root);
    }

    pub fn openOrCreateGroup(self: File, group_name: []const u8) !hid_t {
        const group_name_cstr = try self.arena.allocator().dupeSentinel(u8, group_name, 0x00);
        const group_link = H5Lexists(self.id, group_name_cstr, .H5P_DEFAULT);
        var gid: hid_t = 0;
        if (group_link == 0) {
            gid = H5Gcreate(self.id, group_name_cstr, .H5P_DEFAULT, .H5P_DEFAULT, .H5P_DEFAULT);
        } else if (group_link > 0) {
            gid = H5Gopen(self.id, group_name_cstr, .H5P_DEFAULT);
        }
        return gid;
    }

    pub fn closeGroup(self: File, gid: hid_t) void {
        _ = self;
        if (H5Gclose(gid) < 0) std.log.err("Could not close group\n", .{});
    }

    pub fn writeStringArray(self: File, group_name: []const u8, dataset_name: []const u8, strings: [][]const u8) !void {
        const loc_id = try self.openOrCreateGroup(group_name);
        defer self.closeGroup(loc_id);

        const dataset_name_cstr = try self.arena.allocator().dupeSentinel(u8, dataset_name, 0x00);

        const type_id = H5Tcopy(H5Types.H5T_C_S1_g);
        if (H5Tset_size(type_id, H5T_VARIABLE) < 0) return error.HDF5Error;
        if (H5Tset_strpad(type_id, H5T_STR_NULLTERM) < 0) return error.HDF5Error;

        const space_id = H5Screate_simple(1, &strings.len, null);
        if (space_id < 0) std.log.err("Could not create data space", .{});
        defer if (H5Sclose(space_id) < 0) std.log.err("Could not delete space", .{});

        const dset_id = H5Dcreate(
            loc_id,
            dataset_name_cstr,
            type_id,
            space_id,
            @backingInt(PropListAcc.H5P_DEFAULT),
            .H5P_DEFAULT,
            .H5P_DEFAULT,
        );
        if (dset_id < 0) {
            std.log.err("Could not open dataset", .{});
            return error.HDF5Error;
        }
        defer if (H5Dclose(dset_id) < 0) std.log.err("Could not close dataset", .{});

        const strings_cstr = try self.arena.allocator().alloc([*:0]const u8, strings.len);
        for (strings, 0..) |s, idx| {
            const s_cstr = try self.arena.allocator().dupeSentinel(u8, s, 0x00);
            strings_cstr[idx] = s_cstr.ptr;
        }

        const write_err = H5Dwrite(
            dset_id,
            type_id,
            H5S_ALL,
            H5S_ALL,
            @backingInt(PropListAcc.H5P_DEFAULT),
            @ptrCast(strings_cstr.ptr),
        );
        if (write_err < 0) {
            std.log.err("Could write data counts", .{});
            return error.HDF5Error;
        }
    }

    pub fn writeArray(self: File, array: []const f64, name: []const u8) !void {
        const space_id = H5Screate_simple(1, &array.len, null);
        if (space_id < 0) std.log.err("Could not create data space", .{});
        defer if (H5Sclose(space_id) < 0) std.log.err("Could not delete space", .{});

        const grp_name_end = std.mem.findLast(u8, name, "/");
        const grp_name = try self.arena.allocator().dupeSentinel(u8, name[0 .. grp_name_end.? + 1], 0x00);
        _ = try self.openOrCreateGroup(grp_name);

        const dset_name = try self.arena.allocator().dupeSentinel(u8, name, 0x00);
        const dset_id = H5Dcreate(
            self.id,
            dset_name.ptr,
            H5Types.H5T_NATIVE_DOUBLE_g,
            space_id,
            @backingInt(PropListAcc.H5P_DEFAULT),
            .H5P_DEFAULT,
            .H5P_DEFAULT,
        );
        if (dset_id < 0) {
            std.log.err("Could not open dataset", .{});
            return error.HDF5Error;
        }
        defer if (H5Dclose(dset_id) < 0) std.log.err("Could not close dataset", .{});

        const write_err = H5Dwrite(
            dset_id,
            H5Types.H5T_NATIVE_DOUBLE_g,
            H5S_ALL,
            H5S_ALL,
            @backingInt(PropListAcc.H5P_DEFAULT),
            @ptrCast(array),
        );
        if (write_err < 0) {
            std.log.err("Could write data counts", .{});
            return error.HDF5Error;
        }
    }
};

pub const H5Dataset = struct {
    dataset_id: hid_t = 0,
    dataset_type: hid_t = 0,
    dataset_len: hssize_t = 0,
    dataspace_id: hid_t = 0,
    dataset_field: []const u8 = "",
    dataset_root: []const u8 = "",

    pub fn init(file: File, field: []const u8, root: []const u8) !H5Dataset {
        var buf: [1024]u8 = undefined;
        const full_field = try std.fmt.bufPrintZ(&buf, "/{s}/{s}", .{ root, field });

        const dset = H5Dopen(file.id, full_field[0..(full_field.len)].ptr, .H5P_DEFAULT);
        if (dset < 0) {
            std.log.err("Could not open dataset {s}", .{full_field});
            return error.H5DOpenError;
        }
        const dtype = H5Dget_type(dset);
        const dspace = H5Dget_space(dset);
        const dlen = H5Sget_simple_extent_npoints(dspace);
        return .{ .dataset_id = dset, .dataset_type = dtype, .dataset_len = dlen, .dataspace_id = dspace, .dataset_field = field, .dataset_root = root };
    }

    pub fn deinit(self: H5Dataset) void {
        const setid_err = H5Dclose(self.dataset_id);
        if (setid_err != 0) {
            std.log.err("Error closing dataset: {d}", .{setid_err});
        }
        const spaceid_err = H5Sclose(self.dataspace_id);
        if (spaceid_err != 0) {
            std.log.err("Error closing dataset: {d}", .{spaceid_err});
        }
    }

    pub fn readChunk(self: H5Dataset, allocator: std.mem.Allocator, comptime T: type, beg: hsize_t, chunk_size: hsize_t) ![]T {
        const slab_err = H5Sselect_hyperslab(self.dataspace_id, .H5S_SELECT_SET, &beg, null, &chunk_size, null);
        if (slab_err != 0) return error.HDF5SlabError;

        const buf = try allocator.alloc(T, chunk_size);
        errdefer allocator.free(buf);

        const memspace_id = H5Screate_simple(1, &(buf.len), null);
        defer std.debug.assert(H5Sclose(memspace_id) == 0);

        const read_err = H5Dread(self.dataset_id, self.dataset_type, memspace_id, self.dataspace_id, .H5P_DEFAULT, buf.ptr);
        if (read_err != 0) return error.HDF5ReadError;

        return buf;
    }
};
