# frozen_string_literal: true

require "minitest/autorun"

require_relative "../tools/example_svg"

class TestExampleSvg < Minitest::Test
  def test_committed_example_svg_matches_a_regenerated_one
    committed = File.read(File.join(ExampleSvg::ROOT, ExampleSvg::PATH))

    assert_equal ExampleSvg.render,
                 committed,
                 "#{ExampleSvg::PATH} is stale; run `rake example_svg`"
  end

  def test_readme_shows_the_example_svg
    readme = File.read(File.join(ExampleSvg::ROOT, "README.md"))

    assert_includes readme,
                    "(#{ExampleSvg::PATH})",
                    "README.md does not display #{ExampleSvg::PATH}"
  end
end
