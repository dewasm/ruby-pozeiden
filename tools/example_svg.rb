# frozen_string_literal: true

# Renders the README's example diagram and writes it under examples/, where the README displays it as an image.

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "dewasm/pozeiden"

module ExampleSvg
  ROOT = File.expand_path("..", __dir__)

  PATH = "examples/flowchart.svg"
  TEXT = <<~MERMAID
    flowchart TD
      A[Commit] --> B{CI passes?}
      B -->|Yes| C[Merge]
      B -->|No| D[Fix]
  MERMAID

  module_function

  def render
    Dewasm::Pozeiden.render(TEXT)
  end

  def write
    File.write(File.join(ROOT, PATH), render)
  end
end

ExampleSvg.write if $PROGRAM_NAME == __FILE__
