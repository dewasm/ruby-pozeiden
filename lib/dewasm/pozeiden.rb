# frozen_string_literal: true

require "json"

require_relative "pozeiden/version"
require_relative "pozeiden/wasm_module"

module Dewasm
  # Mermaid diagram rendering by the pozeiden renderer, compiled to WebAssembly and converted to Ruby by dewasm.
  module Pozeiden
    # Raised when pozeiden returns a Zig error, and for input this gem rejects before calling into the WebAssembly module.
    class Error < StandardError
      # The `@errorName` reported by pozeiden, or nil for a local rejection.
      attr_reader :zig_error

      def initialize(message, zig_error: nil)
        super(message)
        @zig_error = zig_error
      end
    end

    RenderResult = Data.define(:svg, :diagram_type, :title, :descr)

    # The input buffer compiled into the WebAssembly module, which is also pozeiden's own `max_input_bytes` default.
    MAX_INPUT_BYTES = 4 * 1024 * 1024

    module_function

    # The SVG is self-contained.
    def render(
      text,
      strict: false,
      max_width: 0,
      max_height: 0,
      scale: 1.0,
      theme_override: {},
      random: Random
    )
      options = options_json(strict:, max_width:, max_height:, scale:, theme_override:)
      instance, length = call("render", text, options, random:)
      read_output(instance, length)
    end

    # The metadata is the diagram type and the accessibility title and description pozeiden extracted from the source.
    def render_with_metadata(
      text,
      strict: false,
      max_width: 0,
      max_height: 0,
      scale: 1.0,
      theme_override: {},
      random: Random
    )
      options = options_json(strict:, max_width:, max_height:, scale:, theme_override:)
      instance, length = call("render_with_metadata", text, options, random:)
      RenderResult.new(
        svg: read_output(instance, length),
        diagram_type: read_text(instance, "meta_diagram_type").to_sym,
        title: presence(read_text(instance, "meta_title")),
        descr: presence(read_text(instance, "meta_descr"))
      )
    end

    # Unrecognised input is `:unknown`.
    def detect_diagram_type(text)
      instance, = call("detect", text, nil, random: Random)
      read_text(instance, "meta_diagram_type").to_sym
    end

    def call(export, text, options, random:)
      bytes = String(text).b
      if bytes.bytesize > MAX_INPUT_BYTES
        raise Error,
              "input is #{bytes.bytesize} bytes, over the #{MAX_INPUT_BYTES} byte limit " \
                "compiled into the WebAssembly module (pozeiden's own max_input_bytes default)"
      end

      instance = instantiate(random)
      write(instance, instance.invoke("get_input_ptr"), bytes)
      result =
        if options.nil?
          signed(instance.invoke(export, bytes.bytesize))
        else
          json = options.b
          write(instance, instance.invoke("get_options_ptr"), json)
          signed(instance.invoke(export, bytes.bytesize, json.bytesize))
        end
      raise_zig_error(instance) if result.negative?
      [instance, result]
    end
    private_class_method :call

    def instantiate(random)
      holder = {}
      random_get =
        lambda do |buf_ptr, len|
          write(holder[:instance], buf_ptr, random.bytes(len).b)
          0
        end
      holder[:instance] = WasmModule.new(
        { "wasi_snapshot_preview1" => { "random_get" => random_get } }
      )
    end
    private_class_method :instantiate

    def options_json(strict:, max_width:, max_height:, scale:, theme_override:)
      theme = theme_override.to_h { |key, value| [key.to_s, value] }
      JSON.generate(
        "strict" => strict,
        "max_width" => max_width,
        "max_height" => max_height,
        "scale" => Float(scale),
        "theme_override" => theme
      )
    end
    private_class_method :options_json

    def write(instance, pointer, bytes)
      instance.memory.init(pointer, bytes, 0, bytes.bytesize)
    end
    private_class_method :write

    def read_output(instance, length)
      instance
        .memory
        .read_string(instance.invoke("get_output_ptr"), length)
        .force_encoding(Encoding::UTF_8)
    end
    private_class_method :read_output

    def read_text(instance, name)
      pointer = instance.invoke("#{name}_ptr")
      length = instance.invoke("#{name}_len")
      instance.memory.read_string(pointer, length).force_encoding(Encoding::UTF_8)
    end
    private_class_method :read_text

    def presence(text)
      text.empty? ? nil : text
    end
    private_class_method :presence

    def raise_zig_error(instance)
      name = read_text(instance, "error_name")
      raise Error.new("pozeiden returned error.#{name}", zig_error: name.to_sym)
    end
    private_class_method :raise_zig_error

    # Exported i32 results arrive masked unsigned, so the error sentinel needs the signed reading.
    def signed(value)
      value >= 0x8000_0000 ? value - 0x1_0000_0000 : value
    end
    private_class_method :signed
  end
end
