# frozen_string_literal: true

require "English"
require "json"
require "tempfile"

# Measures sizes, memory, and speed on the machine it runs on, and rewrites the table between the measurement markers in README.md.
module Measure
  ROOT = File.expand_path("..", __dir__)

  README = "README.md"
  WASM = "wasm/pozeiden.wasm"
  GENERATED = "lib/dewasm/pozeiden/wasm_module.rb"
  BEGIN_MARKER = "<!-- measurements:begin -->"
  END_MARKER = "<!-- measurements:end -->"

  RUNS = 3

  FLOWCHART = <<~MERMAID
    flowchart LR
      A[Start] --> B[Done]
  MERMAID

  PIE = <<~MERMAID
    pie title Pets
      "Dogs" : 3
      "Cats" : 2
  MERMAID

  module_function

  def rows
    process = process_measurements
    in_process = in_process_measurements
    gem_file = Dir["*.gem"].max_by { |path| File.mtime(path) }

    rows = [
      ["`#{WASM}` after `wasm-opt -Oz`", bytes(File.size(WASM))],
      ["Generated `#{File.basename(GENERATED)}`", bytes(File.size(GENERATED))]
    ]
    rows << ["Packaged `.gem`", bytes(File.size(gem_file))] if gem_file
    rows << ["`require \"dewasm/pozeiden\"`", seconds(process["require"])]
    rows << ["Resident memory after `require`", bytes(process["rss"])]
    rows << ["`render`, flowchart", seconds(in_process["render_flowchart"])]
    rows << ["`render`, pie chart", seconds(in_process["render_pie"])]
    rows << ["`render_with_metadata`, flowchart", seconds(in_process["render_with_metadata"])]
    rows << ["`detect_diagram_type`", seconds(in_process["detect_diagram_type"])]
    rows
  end

  def block
    table = rows.map { |name, value| "| #{name} | #{value} |" }
    [
      "Measured on #{machine}.",
      "",
      "| Quantity | Value |",
      "| --- | --- |",
      *table
    ].join("\n")
  end

  def rewrite_readme
    text = File.read(README)
    pattern = /^#{Regexp.escape(BEGIN_MARKER)}\n.*?^#{Regexp.escape(END_MARKER)}$/m
    unless text.match?(pattern)
      raise "#{README} has no #{BEGIN_MARKER} ... #{END_MARKER} block to rewrite"
    end

    replacement = "#{BEGIN_MARKER}\n#{block}\n#{END_MARKER}"
    File.write(README, text.sub(pattern) { replacement })
  end

  # One child process per run: the require time and the resident memory that holds the loaded code are only observable before anything else runs.
  def process_measurements
    script = <<~'RUBY'
      require "json"

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      require "dewasm/pozeiden"
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      rss = `ps -o rss= -p #{Process.pid}`.to_i * 1024

      puts JSON.generate({ "require" => elapsed, "rss" => rss })
    RUBY
    samples = Array.new(RUNS + 1) { JSON.parse(run_ruby(script)) }.drop(1)
    {
      "require" => median(samples.map { |sample| sample["require"] }),
      "rss" => median(samples.map { |sample| sample["rss"] })
    }
  end

  def in_process_measurements
    script = <<~RUBY
      require "json"
      require "dewasm/pozeiden"

      FLOWCHART = #{FLOWCHART.dump}
      PIE = #{PIE.dump}

      def timed(runs)
        yield
        samples = Array.new(runs) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end
        samples.sort[samples.size / 2]
      end

      puts JSON.generate({
        "render_flowchart" => timed(#{RUNS}) { Dewasm::Pozeiden.render(FLOWCHART) },
        "render_pie" => timed(#{RUNS}) { Dewasm::Pozeiden.render(PIE) },
        "render_with_metadata" => timed(#{RUNS}) { Dewasm::Pozeiden.render_with_metadata(FLOWCHART) },
        "detect_diagram_type" => timed(#{RUNS}) { Dewasm::Pozeiden.detect_diagram_type(FLOWCHART) }
      })
    RUBY
    JSON.parse(run_ruby(script))
  end

  def run_ruby(script)
    Tempfile.create(["measure", ".rb"]) do |file|
      file.write(script)
      file.flush
      output = IO.popen([RbConfig.ruby, "-Ilib", file.path], &:read)
      raise "measurement child process failed" unless $CHILD_STATUS.success?

      output
    end
  end

  def median(samples)
    samples.sort[samples.size / 2]
  end

  def machine
    [os, cpu, "Ruby #{RUBY_VERSION}"].join(", ")
  end

  def os
    if RbConfig::CONFIG["host_os"].include?("darwin")
      "macOS #{command("sw_vers -productVersion")}"
    else
      command("uname -sr")
    end
  end

  def cpu
    if RbConfig::CONFIG["host_os"].include?("darwin")
      command("sysctl -n machdep.cpu.brand_string")
    else
      cpuinfo = "/proc/cpuinfo"
      model = File.readlines(cpuinfo).grep(/^model name/).first if File.exist?(cpuinfo)
      model ? model.split(":", 2).last.strip : RbConfig::CONFIG["host_cpu"]
    end
  end

  def command(line)
    output = `#{line}`.strip
    $CHILD_STATUS.success? && !output.empty? ? output : RbConfig::CONFIG["host_os"]
  end

  def bytes(size)
    size < 1_000_000 ? format("%d KB", (size / 1000.0).round) : format("%.1f MB", size / 1_000_000.0)
  end

  # A call below a millisecond still has to read as a number, so the sub-millisecond range keeps one decimal.
  def seconds(elapsed)
    case elapsed
    when ...0.01 then format("%.1f ms", elapsed * 1000)
    when ...1.0 then format("%d ms", (elapsed * 1000).round)
    else format("%.1f s", elapsed)
    end
  end
end

Dir.chdir(Measure::ROOT) { Measure.rewrite_readme }
