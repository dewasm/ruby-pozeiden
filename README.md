# dewasm-pozeiden

**Mermaid** diagram rendering in **pure Ruby**.

[pozeiden](https://github.com/sc2in/pozeiden) is a mermaid renderer written in Zig.
This gem compiles it to `wasm32-wasi` and converts that WebAssembly module to Ruby source with [dewasm](https://github.com/dewasm/dewasm), so rendering runs on plain Ruby.
There is *no browser*, *no native extension*, and *no wasm runtime* involved: the gem is Ruby code that a stock `ruby` executes.

The gem is built from pozeiden 0.4.1 at commit `071fbbb85fb73a06994c163c6093123bd3ac11f6`, pinned in `wasm/build.zig.zon` and surfaced as `Dewasm::Pozeiden::POZEIDEN_VERSION`.

Seventeen diagram types are supported, the ones pozeiden implements: pie, flowchart, sequence, gitgraph, class, state, er, gantt, timeline, xychart, quadrant, mindmap, sankey, c4, block, requirement, and kanban.

> [!NOTE]
> This gem **cannot be used commercially**: the rendering core derives from pozeiden, which is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE-POZEIDEN).
>
> [dewasm-merman](https://github.com/dewasm/ruby-merman) is licensed under MIT and covers more diagram types, but is much larger.

## Install

```console
$ gem install dewasm-pozeiden
```

Or in `Gemfile`:

```ruby
gem "dewasm-pozeiden"
```

Ruby 3.4 or newer is required, because the converted module stores WebAssembly linear memory in an `IO::Buffer`.

## Usage

Render a diagram to an SVG string:

```ruby
require "dewasm/pozeiden"

svg = Dewasm::Pozeiden.render(<<~MERMAID)
  flowchart LR
    A[Start] --> B{Choice}
    B --> C[End]
MERMAID

File.write("flowchart.svg", svg)
```

Unrecognised input renders pozeiden's fallback SVG and counts as success.
Pass `strict: true` to get an error instead:

```ruby
Dewasm::Pozeiden.render("this is not a diagram at all")
# => "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"120\"> ..."

Dewasm::Pozeiden.render("this is not a diagram at all", strict: true)
# raises Dewasm::Pozeiden::Error: pozeiden returned error.UnknownDiagramType
```

`render_with_metadata` also returns the detected diagram type and the accessibility metadata declared in the source:

```ruby
result = Dewasm::Pozeiden.render_with_metadata(<<~MERMAID)
  flowchart LR
    accTitle: Build pipeline
    accDescr: How a build flows
    A --> B
MERMAID

result.diagram_type   # => :flowchart
result.title          # => "Build pipeline"
result.descr          # => "How a build flows"
result.svg            # => "<svg ...>"
```

`detect_diagram_type` classifies the source without rendering it:

```ruby
Dewasm::Pozeiden.detect_diagram_type("pie title Pets\n")   # => :pie
Dewasm::Pozeiden.detect_diagram_type("nothing here\n")     # => :unknown
```

Rendering options are keyword arguments of `render` and `render_with_metadata`:

```ruby
Dewasm::Pozeiden.render(source, max_width: 800, theme_override: { node_fill: "#ffe4b5" })
```

| Keyword | Meaning |
| --- | --- |
| `strict:` | Raise on unrecognised input instead of rendering the fallback SVG. Default `false`. |
| `max_width:` | Scale the SVG so its width does not exceed this many user units. `0` disables. |
| `max_height:` | Scale the SVG so its height does not exceed this many user units. `0` disables. |
| `scale:` | Uniform scale factor for the SVG `viewBox`, ignored when `max_width` or `max_height` is set. |
| `theme_override:` | Theme values to override for this call. |
| `random:` | Source of random bytes for the module's `random_get` import, anything responding to `bytes(count)`. Default `Random`. |

The accepted `theme_override` keys are pozeiden's `ThemeOverride` fields: `background`, `text_color`, `node_fill`, `node_stroke`, `edge_color`, `font_size`, `font_size_small`, and `font_family`.
The first five and the last take a string, the two font sizes take an integer.
Any other key raises `Dewasm::Pozeiden::Error` with `zig_error` `:UnknownField`; unknown keys are never ignored.

Errors that pozeiden itself reports carry its Zig error name:

```ruby
begin
  Dewasm::Pozeiden.render(source, strict: true)
rescue Dewasm::Pozeiden::Error => e
  e.zig_error   # => :UnknownDiagramType
end
```

Input larger than 4 MiB raises `Dewasm::Pozeiden::Error` before the WebAssembly module is called.
That is the size of the module's input buffer, chosen to match pozeiden's own `max_input_bytes` default.

## API

Every call instantiates the converted module, runs, and drops it.
WebAssembly linear memory is not retained between calls, so no state carries over from one render to the next.

| Ruby | pozeiden |
| --- | --- |
| `Dewasm::Pozeiden.render(text, **options)` | `renderWithOptions(allocator, text, RenderOptions)` |
| `Dewasm::Pozeiden.render_with_metadata(text, **options)` | `renderWithMetadata(allocator, text, RenderOptions)` |
| `Dewasm::Pozeiden.detect_diagram_type(text)` | `detectDiagramType(text)` |
| `Dewasm::Pozeiden::RenderResult` | `RenderResult` |
| `Dewasm::Pozeiden::Error#zig_error` | the `@errorName` of the returned error |
| `Dewasm::Pozeiden::POZEIDEN_VERSION` | the pinned upstream revision |

`Dewasm::Pozeiden.render` maps to `renderWithOptions` rather than to the two-argument `render`, because the options are always sent; the defaults are pozeiden's own, so `Dewasm::Pozeiden.render(text)` renders what `render(allocator, text)` renders.

## How it is built

`wasm/` is a self-contained Zig project: it depends on pozeiden pinned by commit in `wasm/build.zig.zon`, fetched by the Zig package manager into the gitignored `wasm/zig-pkg/`, and `wasm/src/shim.zig` is this project's own WebAssembly interface over pozeiden's public API, not upstream's playground shim.
The module is built for `wasm32-wasi` in `ReleaseSmall`, single threaded, with the entry point disabled and `rdynamic` set, post-processed with `wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int`, and converted to Ruby by dewasm at the revision recorded in `DEWASM_REVISION`.

Neither build product is committed: `wasm/pozeiden.wasm` and `lib/dewasm/pozeiden/wasm_module.rb` are produced by the build, and the generated Ruby is shipped in the gem.

## Size, memory, and speed

<!-- measurements:begin -->
Measured on macOS 26.5.2, Apple M1 Pro, Ruby 4.0.4.

| Quantity | Value |
| --- | --- |
| `wasm/pozeiden.wasm` after `wasm-opt -Oz` | 479 KB |
| Generated `wasm_module.rb` | 2.6 MB |
| Packaged `.gem` | 366 KB |
| `require "dewasm/pozeiden"` | 381 ms |
| Resident memory after `require` | 126.6 MB |
| `render`, flowchart | 5.2 ms |
| `render`, pie chart | 38 ms |
| `render_with_metadata`, flowchart | 4.3 ms |
| `detect_diagram_type` | 0.4 ms |
<!-- measurements:end -->

The rows fall into three groups.
The first ones are what ships: the WebAssembly module, the Ruby source dewasm generates from it, and the packaged gem.
The next two are the one-time cost of loading that source, in time and in resident memory.
The rest are per-call costs, one call of each function on a small diagram.

Three facts hold whatever the magnitudes are.
Resident memory after `require` is dominated by the instruction sequences of the loaded code, not by rendering, so it is paid once and does not grow with the number of calls.
Each call allocates the module's linear memory, which holds the 4 MiB input buffer, the 8 MiB scratch arena, and the 4 MiB output buffer, and drops it when the call returns.
Rendering is deterministic: two renders of the same source produce byte-identical SVGs, both with the default random source and with a fixed one.

The numbers move with the pinned pozeiden commit and with the dewasm revision used to generate the module, so rerun `rake measure` after changing either.

## Tasks

The Rakefile drives everything.
`rake generate` does not build the WebAssembly module itself, so a clean checkout runs `rake wasm:build` first; from there `rake test` runs what it needs.

### `rake wasm:build`

```console
$ rake wasm:build
```

Builds `wasm/` with `zig build` and post-processes it into `wasm/pozeiden.wasm` with `wasm-opt -Oz`.
It needs Zig 0.16 and `wasm-opt` from Binaryen.

### `rake generate`

```console
$ rake generate
```

Converts that module into the Ruby the gem ships.
It needs `wasm/pozeiden.wasm`, and a dewasm binary, its path in `DEWASM_BIN`.

### `rake test`

```console
$ rake test
```

Runs `test/` against the generated module.
It needs `rake generate`.

### `rake measure`

```console
$ rake measure
```

Refreshes the measurements table in `README.md` with numbers from this machine.
It needs `rake generate`, and a built gem in the checkout for the `.gem` row.

### `rake build`

```console
$ rake build
```

Packages the gem.
It needs `rake generate`.

### `rake clean`

```console
$ rake clean
```

Removes the build products, `wasm/zig-out`, and `wasm/.zig-cache`.
It needs nothing.

## License

The code in this repository (the shim, the wrapper, the tools, and the tests) is Copyright (c) 2026 Hiroya Fujinami, under the [MIT License](LICENSE).

The generated `wasm_module.rb` derives from pozeiden and stays under the [PolyForm Noncommercial License 1.0.0](LICENSE-POZEIDEN), whose required notice is preserved there: Copyright © 2025 Star City Security Consulting, LLC (SC2).
Every render runs that module, so use of the gem as a whole is bound by the noncommercial restriction.
