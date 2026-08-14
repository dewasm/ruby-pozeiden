//! WebAssembly shim over pozeiden's public root API.
//!
//! The host writes the mermaid source into the input buffer and the options JSON into the options buffer, then calls one of `render`, `render_with_metadata`, or `detect`.
//!
//! Every entry point returns an i32: a non-negative value is the result (a byte length in the output buffer, or an enum ordinal for `detect`), and -1 means the pozeiden call returned a Zig error whose `@errorName` is readable at `error_name_ptr()` for `error_name_len()` bytes.
//!
//! Results only stay valid until the next call.
const std = @import("std");
const pozeiden = @import("pozeiden");

/// The host writes UTF-8 mermaid source here.
/// The size matches pozeiden's own `max_input_bytes` default, so this buffer never rejects input that the library would have accepted.
var input_buf: [4 * 1024 * 1024]u8 = undefined;

/// The host writes the options JSON here.
var options_buf: [64 * 1024]u8 = undefined;

/// Parse trees, layout data, and SVG building all allocate here, from a fresh FixedBufferAllocator per call that leaves no state between calls.
var scratch_buf: [8 * 1024 * 1024]u8 = undefined;

/// Receives the rendered SVG, or the diagram type name for `detect`.
var output_buf: [4 * 1024 * 1024]u8 = undefined;

var error_name_buf: [128]u8 = undefined;
var error_name_size: u32 = 0;

var meta_diagram_type: []const u8 = "";
var meta_title_buf: [4096]u8 = undefined;
var meta_title_size: u32 = 0;
var meta_descr_buf: [4096]u8 = undefined;
var meta_descr_size: u32 = 0;

export fn get_input_ptr() [*]u8 {
    return &input_buf;
}

export fn get_options_ptr() [*]u8 {
    return &options_buf;
}

export fn get_output_ptr() [*]u8 {
    return &output_buf;
}

export fn input_capacity() u32 {
    return input_buf.len;
}

export fn options_capacity() u32 {
    return options_buf.len;
}

export fn error_name_ptr() [*]u8 {
    return &error_name_buf;
}

export fn error_name_len() u32 {
    return error_name_size;
}

export fn meta_diagram_type_ptr() [*]const u8 {
    return meta_diagram_type.ptr;
}

export fn meta_diagram_type_len() u32 {
    return @intCast(meta_diagram_type.len);
}

export fn meta_title_ptr() [*]u8 {
    return &meta_title_buf;
}

export fn meta_title_len() u32 {
    return meta_title_size;
}

export fn meta_descr_ptr() [*]u8 {
    return &meta_descr_buf;
}

export fn meta_descr_len() u32 {
    return meta_descr_size;
}

/// Returns the SVG length written to the output buffer, or -1 on error.
export fn render(text_len: u32, options_len: u32) i32 {
    return renderImpl(text_len, options_len, false);
}

/// Like `render`, and additionally exposes the diagram type, the accessible title, and the accessible description through the `meta_*` accessors.
/// The title and the description are empty when the diagram declares none.
export fn render_with_metadata(text_len: u32, options_len: u32) i32 {
    return renderImpl(text_len, options_len, true);
}

/// Returns the ordinal of `pozeiden.DiagramType` for the input buffer's text, whose name is readable through the `meta_diagram_type` accessors.
export fn detect(text_len: u32) i32 {
    const diagram_type = pozeiden.detectDiagramType(input_buf[0..text_len]);
    meta_diagram_type = @tagName(diagram_type);
    return @intCast(@intFromEnum(diagram_type));
}

fn renderImpl(text_len: u32, options_len: u32, with_metadata: bool) i32 {
    error_name_size = 0;
    meta_diagram_type = "";
    meta_title_size = 0;
    meta_descr_size = 0;

    var fba = std.heap.FixedBufferAllocator.init(&scratch_buf);
    var arena = std.heap.ArenaAllocator.init(fba.allocator());
    const allocator = arena.allocator();

    const options = parseOptions(allocator, options_buf[0..options_len]) catch |err| return fail(err);
    const text = input_buf[0..text_len];

    if (!with_metadata) {
        const svg = pozeiden.renderWithOptions(allocator, text, options) catch |err| return fail(err);
        return emit(svg);
    }

    const result = pozeiden.renderWithMetadata(allocator, text, options) catch |err| return fail(err);
    meta_diagram_type = @tagName(result.diagram_type);
    if (result.title) |title| meta_title_size = copyInto(&meta_title_buf, title);
    if (result.descr) |descr| meta_descr_size = copyInto(&meta_descr_buf, descr);
    return emit(result.svg);
}

/// pozeiden's `RenderOptions` is parsed straight from JSON, so the accepted keys are its field names and an unknown key is `error.UnknownField`.
fn parseOptions(allocator: std.mem.Allocator, json: []const u8) !pozeiden.RenderOptions {
    if (json.len == 0) return .{};
    return std.json.parseFromSliceLeaky(pozeiden.RenderOptions, allocator, json, .{});
}

fn emit(svg: []const u8) i32 {
    if (svg.len > output_buf.len) return fail(error.OutputTooLarge);
    @memcpy(output_buf[0..svg.len], svg);
    return @intCast(svg.len);
}

fn copyInto(buf: []u8, text: []const u8) u32 {
    const len = @min(buf.len, text.len);
    @memcpy(buf[0..len], text[0..len]);
    return @intCast(len);
}

fn fail(err: anyerror) i32 {
    error_name_size = copyInto(&error_name_buf, @errorName(err));
    return -1;
}
