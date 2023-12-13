const std = @import("std");
const c = @import("c.zig");

pub const Position = struct {
    x: usize,
    y: usize,
    floor: usize,
};

const Tile = struct {
    x: i32,
    z: i32,
    floor: i32,
};

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var db: ?*c.sqlite3 = undefined;
    if (c.sqlite3_open("db.db", &db) != c.SQLITE_OK) {
        // if (c.sqlite3_open_v2("db.db", &db, c.SQLITE_OPEN_MEMORY | c.SQLITE_OPEN_NOMUTEX | c.SQLITE_OPEN_READWRITE, null) != c.SQLITE_OK) {
        std.debug.print("Can't open database: {s}\n", .{c.sqlite3_errmsg(db)});
        return error.CannotOpenDatabase;
    }

    var err_msg: [*c]u8 = undefined;
    _ = c.sqlite3_exec(db, "pragma journal_mode = WAL;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma synchronous = normal;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma journal_size_limit = 6144000;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma journal_mode = WAL;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma temp_store = memory;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma mmap_size = 30000000000;", null, null, &err_msg);
    _ = c.sqlite3_exec(db, "pragma page_size = 32768;", null, null, &err_msg);

    const create_tiles_table_sql =
        \\CREATE VIRTUAL TABLE IF NOT EXISTS tiles USING rtree(
        \\  id,
        \\  min_x, max_x,
        \\  min_z, max_z,
        \\  +x INTEGER NOT NULL,
        \\  +z INTEGER NOT NULL,
        \\  +floor INTEGER NOT NULL,
        \\);
    ;

    if (c.sqlite3_exec(db, create_tiles_table_sql, null, null, &err_msg) != c.SQLITE_OK) {
        std.debug.print("SQL Error: {s}\n", .{err_msg});
        c.sqlite3_free(err_msg);
        return error.SqlError;
    }

    const insert_tile_sql =
        \\ INSERT INTO tiles (min_x, max_x, min_z, max_z, x, z, floor) VALUES (?, ?, ?, ?,  ?, ?, ?);
    ;
    _ = insert_tile_sql;

    // for (0..1000) |x| {
    //     for (0..1000) |z| {
    //         var stmt: ?*c.sqlite3_stmt = undefined;
    //         if (c.sqlite3_prepare(db, insert_tile_sql, -1, &stmt, 0) != c.SQLITE_OK) {
    //             std.debug.print("SQL Error: {s}\n", .{c.sqlite3_errmsg(db)});
    //             return error.SqlError;
    //         }
    //         const tile = Tile{
    //             .x = @intCast(x),
    //             .z = @intCast(z),
    //             .floor = 0,
    //         };
    //         const fx: f64 = @floatFromInt(tile.x);
    //         const fz: f64 = @floatFromInt(tile.z);
    //         _ = c.sqlite3_bind_double(stmt, 1, fx - 0.5);
    //         _ = c.sqlite3_bind_double(stmt, 2, fx + 0.5);
    //         _ = c.sqlite3_bind_double(stmt, 3, fz - 0.5);
    //         _ = c.sqlite3_bind_double(stmt, 4, fz + 0.5);
    //         _ = c.sqlite3_bind_int(stmt, 5, tile.x);
    //         _ = c.sqlite3_bind_int(stmt, 6, tile.z);
    //         _ = c.sqlite3_bind_int(stmt, 7, tile.floor);
    //
    //         if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
    //             std.debug.print("SQL Error: {s}\n", .{c.sqlite3_errmsg(db)});
    //             return error.SqlError;
    //         }
    //
    //         _ = c.sqlite3_finalize(stmt);
    //     }
    // }

    const start = std.time.microTimestamp();
    var read_tile: Tile = undefined;
    const select_tiles_sql =
        \\ SELECT x, z, floor FROM tiles 
        \\ WHERE  (min_x >= ?1 AND min_x <= ?2 and min_z >= ?1 AND min_z <= ?2)
        \\ OR     (max_x >= ?1 AND max_x <= ?2 and max_z >= ?1 AND max_z <= ?2)
        \\ OR     (min_x >= ?1 AND min_x <= ?2 and max_z >= ?1 AND max_z <= ?2)
        \\ OR     (max_x >= ?1 AND max_x <= ?2 and min_z >= ?1 AND min_z <= ?2)
        \\ ORDER BY z DESC, x DESC;
    ;
    var stmt: ?*c.sqlite3_stmt = undefined;
    if (c.sqlite3_prepare_v2(db, select_tiles_sql, -1, &stmt, 0) != c.SQLITE_OK) {
        std.debug.print("SQL Error: {s}\n", .{c.sqlite3_errmsg(db)});
        return error.SqlError;
    }

    _ = c.sqlite3_bind_double(stmt, 1, 0.0);
    _ = c.sqlite3_bind_double(stmt, 2, 10.0);

    var tiles = std.ArrayList(Tile).init(allocator);
    var rc: i32 = 0;
    _ = rc;
    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        read_tile = .{
            .x = c.sqlite3_column_int(stmt, 0),
            .z = c.sqlite3_column_int(stmt, 1),
            .floor = c.sqlite3_column_int(stmt, 2),
        };

        try tiles.append(read_tile);
    }

    _ = c.sqlite3_finalize(stmt);

    const end = std.time.microTimestamp();
    std.debug.print("microseconds took: {}\n", .{end - start});

    for (tiles.items) |tile| {
        std.debug.print("{}\n", .{tile});
    }
    _ = c.sqlite3_close(db);
}

pub fn day1Part1() !void {
    const file = try std.fs.cwd().openFile("input-day-1.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var sum: u32 = 0;
    var first_number: ?u32 = null;
    var last_number: ?u32 = null;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        // std.debug.print("{s}\n", .{line});
        first_number = null;
        last_number = null;
        for (line) |char| {
            if (char >= 48 and char <= 57) {
                if (first_number == null) {
                    first_number = char - 48;
                    last_number = first_number;
                } else {
                    last_number = char - 48;
                }
            }
        }
        if (first_number) |n| {
            sum += n * 10 + last_number.?;
        }
    }

    std.debug.print("Result Day 1 Part 1: {}\n", .{sum});
}

pub fn day1Part2() !void {
    const file = try std.fs.cwd().openFile("input-day-1.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var sum: u32 = 0;
    var first_number: ?u32 = null;
    var last_number: ?u32 = null;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        // std.debug.print("{s}\n", .{line});
        first_number = null;
        last_number = null;
        for (line, 0..) |char, i| {
            switch (char) {
                '0'...'9' => {
                    if (first_number == null) {
                        first_number = char - '0';
                        last_number = first_number;
                    } else {
                        last_number = char - '0';
                    }
                },
                'o' => {
                    if (line.len > 3 and
                        i < line.len - 2 and
                        line[i + 1] == 'n' and
                        line[i + 2] == 'e')
                    {
                        if (first_number == null) {
                            first_number = 1;
                            last_number = first_number;
                        } else {
                            last_number = 1;
                        }
                    }
                },
                't' => {
                    if (line.len > 3 and
                        i < line.len - 2 and
                        line[i + 1] == 'w' and
                        line[i + 2] == 'o')
                    {
                        if (first_number == null) {
                            first_number = 2;
                            last_number = first_number;
                        } else {
                            last_number = 2;
                        }
                    } else if (line.len > 5 and
                        i < line.len - 4 and
                        line[i + 1] == 'h' and
                        line[i + 2] == 'r' and
                        line[i + 3] == 'e' and
                        line[i + 4] == 'e')
                    {
                        if (first_number == null) {
                            first_number = 3;
                            last_number = first_number;
                        } else {
                            last_number = 3;
                        }
                    }
                },
                'f' => {
                    if (line.len > 4 and
                        i < line.len - 3 and
                        line[i + 1] == 'o' and
                        line[i + 2] == 'u' and
                        line[i + 3] == 'r')
                    {
                        if (first_number == null) {
                            first_number = 4;
                            last_number = first_number;
                        } else {
                            last_number = 4;
                        }
                    } else if (line.len > 4 and
                        i < line.len - 3 and
                        line[i + 1] == 'i' and
                        line[i + 2] == 'v' and
                        line[i + 3] == 'e')
                    {
                        if (first_number == null) {
                            first_number = 5;
                            last_number = first_number;
                        } else {
                            last_number = 5;
                        }
                    }
                },
                's' => {
                    if (line.len > 3 and
                        i < line.len - 2 and
                        line[i + 1] == 'i' and
                        line[i + 2] == 'x')
                    {
                        if (first_number == null) {
                            first_number = 6;
                            last_number = first_number;
                        } else {
                            last_number = 6;
                        }
                    } else if (line.len > 5 and
                        i < line.len - 4 and
                        line[i + 1] == 'e' and
                        line[i + 2] == 'v' and
                        line[i + 3] == 'e' and
                        line[i + 4] == 'n')
                    {
                        if (first_number == null) {
                            first_number = 7;
                            last_number = first_number;
                        } else {
                            last_number = 7;
                        }
                    }
                },
                'e' => {
                    if (line.len > 5 and
                        i < line.len - 4 and
                        line[i + 1] == 'i' and
                        line[i + 2] == 'g' and
                        line[i + 3] == 'h' and
                        line[i + 4] == 't')
                    {
                        if (first_number == null) {
                            first_number = 8;
                            last_number = first_number;
                        } else {
                            last_number = 8;
                        }
                    }
                },
                'n' => {
                    if (line.len > 4 and
                        i < line.len - 3 and
                        line[i + 1] == 'i' and
                        line[i + 2] == 'n' and
                        line[i + 3] == 'e')
                    {
                        if (first_number == null) {
                            first_number = 9;
                            last_number = first_number;
                        } else {
                            last_number = 9;
                        }
                    }
                },
                else => {},
            }
        }
        if (first_number) |n| {
            sum += n * 10 + last_number.?;
        }
    }

    std.debug.print("Result Day 1 Part 2: {}\n", .{sum});
}

pub fn day2Part1() !void {
    const file = try std.fs.cwd().openFile("input-day-2.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var sum: u32 = 0;
    const red_limit = 12;
    const green_limit = 13;
    const blue_limit = 14;
    var index: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        // reading ID
        var id: ?u32 = null;
        for (5..line.len) |i| {
            const char = line[i];
            if (char == ':') {
                index = i + 2;
                break;
            }

            if (id != null) {
                id = id.? * 10;
            } else {
                id = 0;
            }

            id = id.? + (char - '0');
        }

        std.debug.print("Id: {}\n", .{id.?});

        var valid: bool = true;
        blk: {
            while (index < line.len) {
                // Read a number.
                var num: ?u32 = null;
                for (index..line.len) |i| {
                    const char = line[i];
                    if (char == ' ') {
                        index = i + 1;
                        break;
                    }

                    if (num != null) {
                        num = num.? * 10;
                    } else {
                        num = 0;
                    }

                    num = num.? + (char - '0');
                }

                // validate number.
                switch (line[index]) {
                    'r' => {
                        if (num.? > red_limit) {
                            valid = false;
                            break :blk;
                        }
                        index += 5;
                    },
                    'b' => {
                        if (num.? > blue_limit) {
                            valid = false;
                            break :blk;
                        }
                        index += 6;
                    },
                    'g' => {
                        if (num.? > green_limit) {
                            valid = false;
                            break :blk;
                        }
                        index += 7;
                    },
                    else => {},
                }
            }
        }

        if (valid) {
            sum += id.?;
        }
    }

    std.debug.print("Result Day 2 Part 1: {}\n", .{sum});
}

pub fn day2Part2() !void {
    const file = try std.fs.cwd().openFile("input-day-2.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var sum: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var max_red: usize = 0;
        var max_green: usize = 0;
        var max_blue: usize = 0;
        var index: usize = 0;
        for (5..line.len) |i| {
            const char = line[i];
            if (char == ':') {
                index = i + 2;
                break;
            }
        }

        while (index < line.len) {
            // Read a number.
            var num: ?u32 = null;
            for (index..line.len) |i| {
                const char = line[i];
                if (char == ' ') {
                    index = i + 1;
                    break;
                }

                if (num != null) {
                    num = num.? * 10;
                } else {
                    num = 0;
                }

                num = num.? + (char - '0');
            }

            switch (line[index]) {
                'r' => {
                    if (num.? > max_red) {
                        max_red = num.?;
                    }
                    index += 5;
                },
                'b' => {
                    if (num.? > max_blue) {
                        max_blue = num.?;
                    }
                    index += 6;
                },
                'g' => {
                    if (num.? > max_green) {
                        max_green = num.?;
                    }
                    index += 7;
                },
                else => {},
            }
        }

        const power = max_red * max_green * max_blue;
        sum += power;
    }

    std.debug.print("Result Day 2 Part 2: {}\n", .{sum});
}

pub fn day3Part1() !void {
    const file = try std.fs.cwd().openFile("input-day-3.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    const map_size = 140;

    var number_map: [map_size][map_size]?*u32 = .{.{null} ** map_size} ** map_size;
    var symbol_map: [map_size][map_size]bool = .{.{false} ** map_size} ** map_size;

    var i: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |char, j| {
            switch (char) {
                '.' => continue,
                '0'...'9' => {
                    const n = c - '0';

                    if (j > 0 and number_map[i][j - 1] != null) {
                        var ptr = number_map[i][j - 1];
                        ptr.?.* *= 10;
                        ptr.?.* += n;
                        number_map[i][j] = ptr;
                    } else {
                        number_map[i][j] = try std.heap.page_allocator.create(u32);
                        number_map[i][j].?.* = n;
                    }
                },
                else => {
                    symbol_map[i][j] = true;
                },
            }
        }

        i += 1;
    }

    std.debug.print("finish making the maps\n", .{});

    var sum: usize = 0;
    for (0..map_size) |y| {
        for (0..map_size) |x| {
            if (symbol_map[y][x]) {
                if (y > 0) {
                    if (number_map[y - 1][x]) |ptr| {
                        sum += ptr.*;
                        ptr.* = 0;
                    } else {
                        if (x > 0 and number_map[y - 1][x - 1] != null) {
                            var ptr = number_map[y - 1][x - 1];
                            sum += ptr.?.*;
                            ptr.?.* = 0;
                        }

                        if (x < map_size - 1 and number_map[y - 1][x + 1] != null) {
                            var ptr = number_map[y - 1][x + 1];
                            sum += ptr.?.*;
                            ptr.?.* = 0;
                        }
                    }
                }

                if (x > 0 and number_map[y][x - 1] != null) {
                    var ptr = number_map[y][x - 1];
                    sum += ptr.?.*;
                    ptr.?.* = 0;
                }

                if (x < map_size - 1 and number_map[y][x + 1] != null) {
                    var ptr = number_map[y][x + 1];
                    sum += ptr.?.*;
                    ptr.?.* = 0;
                }

                if (y < map_size - 1) {
                    if (number_map[y + 1][x] != null) {
                        var ptr = number_map[y + 1][x];
                        sum += ptr.?.*;
                        ptr.?.* = 0;
                    } else {
                        if (x > 0 and number_map[y + 1][x - 1] != null) {
                            var ptr = number_map[y + 1][x - 1];
                            sum += ptr.?.*;
                            ptr.?.* = 0;
                        }

                        if (x < map_size - 1 and number_map[y + 1][x + 1] != null) {
                            var ptr = number_map[y + 1][x + 1];
                            sum += ptr.?.*;
                            ptr.?.* = 0;
                        }
                    }
                }
            }
        }
    }

    std.debug.print("{}\n", .{number_map[0][2].?.*});
    std.debug.print("Result Day 3 Part 1: {}\n", .{sum});
}

pub fn day3Part2() !void {
    const file = try std.fs.cwd().openFile("input-day-3.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    const map_size = 140;

    var number_map: [map_size][map_size]?*u32 = .{.{null} ** map_size} ** map_size;
    var symbol_map: [map_size][map_size]bool = .{.{false} ** map_size} ** map_size;

    var i: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        for (line, 0..) |char, j| {
            switch (char) {
                '.' => continue,
                '0'...'9' => {
                    const n = c - '0';

                    if (j > 0 and number_map[i][j - 1] != null) {
                        var ptr = number_map[i][j - 1];
                        ptr.?.* *= 10;
                        ptr.?.* += n;
                        number_map[i][j] = ptr;
                    } else {
                        number_map[i][j] = try std.heap.page_allocator.create(u32);
                        number_map[i][j].?.* = n;
                    }
                },
                '*' => {
                    symbol_map[i][j] = true;
                },
                else => {},
            }
        }

        i += 1;
    }

    std.debug.print("finish making the maps\n", .{});

    var sum: usize = 0;
    for (0..map_size) |y| {
        for (0..map_size) |x| {
            if (symbol_map[y][x]) {
                var adjacent_numbers_length: usize = 0;
                var adjacent_numbers: [2]usize = .{0} ** 2;

                if (y > 0) {
                    if (number_map[y - 1][x]) |ptr| {
                        adjacent_numbers[adjacent_numbers_length] = ptr.*;
                        adjacent_numbers_length += 1;
                    } else {
                        if (x > 0 and number_map[y - 1][x - 1] != null) {
                            var ptr = number_map[y - 1][x - 1];
                            adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                            adjacent_numbers_length += 1;
                        }

                        if (x < map_size - 1 and number_map[y - 1][x + 1] != null) {
                            var ptr = number_map[y - 1][x + 1];
                            adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                            adjacent_numbers_length += 1;
                        }
                    }
                }

                if (x > 0 and number_map[y][x - 1] != null) {
                    var ptr = number_map[y][x - 1];
                    if (adjacent_numbers_length == 2) {
                        continue;
                    }
                    adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                    adjacent_numbers_length += 1;
                }

                if (x < map_size - 1 and number_map[y][x + 1] != null) {
                    var ptr = number_map[y][x + 1];
                    if (adjacent_numbers_length == 2) {
                        continue;
                    }
                    adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                    adjacent_numbers_length += 1;
                }

                if (y < map_size - 1) {
                    if (number_map[y + 1][x] != null) {
                        var ptr = number_map[y + 1][x];
                        if (adjacent_numbers_length == 2) {
                            continue;
                        }
                        adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                        adjacent_numbers_length += 1;
                    } else {
                        if (x > 0 and number_map[y + 1][x - 1] != null) {
                            var ptr = number_map[y + 1][x - 1];
                            if (adjacent_numbers_length == 2) {
                                continue;
                            }
                            adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                            adjacent_numbers_length += 1;
                        }

                        if (x < map_size - 1 and number_map[y + 1][x + 1] != null) {
                            var ptr = number_map[y + 1][x + 1];
                            if (adjacent_numbers_length == 2) {
                                continue;
                            }
                            adjacent_numbers[adjacent_numbers_length] = ptr.?.*;
                            adjacent_numbers_length += 1;
                        }
                    }
                }

                if (adjacent_numbers_length == 2) {
                    sum += adjacent_numbers[0] * adjacent_numbers[1];
                }
            }
        }
    }

    std.debug.print("Result Day 3 Part 2: {}\n", .{sum});
}

pub fn day4Part1() !void {
    const file = try std.fs.cwd().openFile("input-day-4.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    var sum: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var numbers: [10]usize = .{0} ** 10;
        for (&numbers, 0..) |*n, i| {
            for (0..2) |j| {
                var char = line[10 + i * 3 + j];
                switch (char) {
                    '0'...'9' => n.* += (c - '0') * std.math.pow(usize, 10, (1 - j)),
                    else => {},
                }
            }
        }

        var wins: usize = 0;
        for (0..25) |i| {
            var n: usize = 0;
            for (0..2) |j| {
                var char = line[42 + i * 3 + j];
                switch (char) {
                    '0'...'9' => n += (c - '0') * std.math.pow(usize, 10, (1 - j)),
                    else => {},
                }
            }

            for (numbers) |winning_num| {
                if (winning_num == n) {
                    wins += 1;
                    break;
                }
            }
        }

        if (wins > 0) {
            sum += std.math.pow(usize, 2, wins - 1);
        }
    }

    std.debug.print("Result Day 4 Part 1: {}\n", .{sum});
}

pub fn day4Part2() !void {
    const file = try std.fs.cwd().openFile("input-day-4.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var cards: [219]usize = .{1} ** 219;

    var sum: usize = 0;
    var card: usize = 0;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var numbers: [10]usize = .{0} ** 10;
        for (&numbers, 0..) |*n, i| {
            for (0..2) |j| {
                var char = line[10 + i * 3 + j];
                switch (char) {
                    '0'...'9' => n.* += (c - '0') * std.math.pow(usize, 10, (1 - j)),
                    else => {},
                }
            }
        }

        var wins: usize = 0;
        for (0..25) |i| {
            var n: usize = 0;
            for (0..2) |j| {
                var char = line[42 + i * 3 + j];
                switch (char) {
                    '0'...'9' => n += (c - '0') * std.math.pow(usize, 10, (1 - j)),
                    else => {},
                }
            }

            for (numbers) |winning_num| {
                if (winning_num == n) {
                    wins += 1;
                    break;
                }
            }
        }

        for (0..wins) |i| {
            cards[card + i + 1] += cards[card];
        }

        card += 1;
    }

    for (cards) |n| {
        sum += n;
    }

    std.debug.print("Result Day 4 Part 2: {}\n", .{sum});
}

pub fn day5Part1() !void {
    const file = try std.fs.cwd().openFile("input-day-5.txt", .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;

    var sum: usize = 0;

    const Range = struct {
        start: usize,
        end: usize,
    };
    _ = Range;

    const seeds_line = try in_stream.readUntilDelimiterOrEof(&buf, '\n');
    var seeds: usize[20] = undefined;
    _ = seeds;
    var seed: usize = 0;
    _ = seed;
    _ = seeds_line;

    // for (7..) |c| {
    //
    // }
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        _ = line;
    }

    std.debug.print("Result Day 5 Part 1: {}\n", .{sum});
}

fn Table(comptime T: type) type {
    return struct {
        const Self = @This();

        columns: std.MultiArrayList(T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .columns = .{},
            };
        }

        pub fn append(self: *Self, item: T) !usize {
            const id = self.columns.len;
            try self.columns.append(self.allocator, item);
            return id;
        }

        pub fn getById(self: *Self, id: usize) T {
            return self.columns.get(id);
        }

        pub fn select(self: *Self, comptime field: anytype) void {
            return self.columns.items(field);
        }
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
