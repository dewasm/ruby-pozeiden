# frozen_string_literal: true

require "minitest/autorun"
require "dewasm/pozeiden"

class TestPozeiden < Minitest::Test
  DIAGRAMS = {
    pie: "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2\n",
    flowchart: "flowchart LR\n  A[Start] --> B{Choice}\n  B --> C[End]\n",
    sequence: "sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi\n",
    class: "classDiagram\n  class Animal {\n    +String name\n    +eat()\n  }\n  Animal <|-- Dog\n",
    state: "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Running\n  Running --> [*]\n",
    gantt: "gantt\n  title Plan\n  section Work\n  Design :a1, 2026-01-01, 3d\n  Build :after a1, 5d\n",
    mindmap: "mindmap\n  root((core))\n    first\n    second\n",
    gitgraph: "gitGraph\n  commit\n  branch develop\n  commit\n  checkout main\n  merge develop\n"
  }.freeze

  DIAGRAMS.each do |type, source|
    define_method(:"test_render_#{type}") do
      svg = Dewasm::Pozeiden.render(source)
      assert_kind_of String, svg
      assert svg.start_with?("<svg"), "expected an SVG document, got #{svg[0, 40].inspect}"
      assert svg.end_with?("</svg>\n") || svg.end_with?("</svg>"), "expected a closed SVG document"
      assert_equal type, Dewasm::Pozeiden.detect_diagram_type(source)
    end
  end

  # A class diagram used to convert into code that produced the fallback SVG.
  def test_class_diagram_renders_the_declared_members
    svg = Dewasm::Pozeiden.render(DIAGRAMS[:class])
    assert_includes svg, ">Animal<"
    assert_includes svg, ">Dog<"
    assert_includes svg, ">+eat()<"
  end

  def test_lenient_mode_returns_the_fallback_svg_for_nonsense
    svg = Dewasm::Pozeiden.render("this is not a diagram at all")
    assert svg.start_with?("<svg"), "expected the fallback SVG, got #{svg[0, 40].inspect}"
  end

  def test_strict_mode_raises_for_nonsense
    error = assert_raises(Dewasm::Pozeiden::Error) do
      Dewasm::Pozeiden.render("this is not a diagram at all", strict: true)
    end
    assert_equal :UnknownDiagramType, error.zig_error
  end

  def test_render_with_metadata_returns_the_diagram_type_and_svg
    result = Dewasm::Pozeiden.render_with_metadata(DIAGRAMS[:pie])
    assert_equal :pie, result.diagram_type
    assert result.svg.start_with?("<svg")
    assert_nil result.title
    assert_nil result.descr
  end

  def test_render_with_metadata_returns_the_accessibility_metadata
    source = "flowchart LR\n  accTitle: Build pipeline\n  accDescr: How a build flows\n  A --> B\n"
    result = Dewasm::Pozeiden.render_with_metadata(source)
    assert_equal :flowchart, result.diagram_type
    assert_equal "Build pipeline", result.title
    assert_equal "How a build flows", result.descr
  end

  def test_detect_diagram_type_on_a_pie_header
    assert_equal :pie, Dewasm::Pozeiden.detect_diagram_type("pie title Pets\n")
  end

  def test_detect_diagram_type_on_nonsense
    assert_equal :unknown, Dewasm::Pozeiden.detect_diagram_type("nothing to see here\n")
  end

  def test_oversized_input_is_rejected_before_the_wasm_call
    oversized = "flowchart LR\n" + ("  A --> B\n" * 1)
    oversized += "%% " + ("x" * Dewasm::Pozeiden::MAX_INPUT_BYTES)
    error = assert_raises(Dewasm::Pozeiden::Error) { Dewasm::Pozeiden.render(oversized) }
    assert_nil error.zig_error
    assert_includes error.message, "over the #{Dewasm::Pozeiden::MAX_INPUT_BYTES} byte limit"
  end

  def test_max_input_bytes_matches_the_buffer_compiled_into_the_module
    instance = Dewasm::Pozeiden::WasmModule.new
    assert_equal Dewasm::Pozeiden::MAX_INPUT_BYTES, instance.invoke("input_capacity")
  end

  def test_theme_override_changes_the_rendered_colors
    svg = Dewasm::Pozeiden.render(DIAGRAMS[:flowchart], theme_override: { node_fill: "#ff0000" })
    assert_includes svg, "#ff0000"
  end

  def test_unknown_theme_override_key_is_an_error
    error = assert_raises(Dewasm::Pozeiden::Error) do
      Dewasm::Pozeiden.render(DIAGRAMS[:flowchart], theme_override: { nope: "#ff0000" })
    end
    assert_equal :UnknownField, error.zig_error
  end

  def test_scale_changes_the_svg_dimensions
    plain = Dewasm::Pozeiden.render(DIAGRAMS[:pie])
    scaled = Dewasm::Pozeiden.render(DIAGRAMS[:pie], scale: 0.5)
    refute_equal plain, scaled
    assert scaled.start_with?("<svg")
  end

  def test_renders_are_byte_identical_with_a_fixed_random_source
    fixed = Object.new
    def fixed.bytes(count) = "\x00".b * count

    first = Dewasm::Pozeiden.render(DIAGRAMS[:flowchart], random: fixed)
    second = Dewasm::Pozeiden.render(DIAGRAMS[:flowchart], random: fixed)
    assert_equal first, second
  end

  def test_renders_are_byte_identical_with_the_default_random_source
    assert_equal Dewasm::Pozeiden.render(DIAGRAMS[:flowchart]),
                 Dewasm::Pozeiden.render(DIAGRAMS[:flowchart])
  end
end
