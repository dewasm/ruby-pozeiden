# frozen_string_literal: true

require "rake/testtask"

WASM_DIR = File.expand_path("wasm", __dir__)
WASM_FILE = File.join(WASM_DIR, "pozeiden.wasm")
GENERATED_FILE = File.expand_path("lib/dewasm/pozeiden/wasm_module.rb", __dir__)
DEWASM_BIN = ENV.fetch("DEWASM_BIN", File.expand_path("../dewasm/target/release/dewasm", __dir__))
DEWASM_REVISION = File.read(File.expand_path("DEWASM_REVISION", __dir__)).strip

namespace :wasm do
  desc "Build wasm/pozeiden.wasm with zig and wasm-opt"
  task :build do
    sh "zig", "build", "--build-file", File.join(WASM_DIR, "build.zig")
    sh "wasm-opt",
       "-Oz",
       "--enable-bulk-memory",
       "--enable-sign-ext",
       "--enable-nontrapping-float-to-int",
       File.join(WASM_DIR, "zig-out/bin/pozeiden_shim.wasm"),
       "-o",
       WASM_FILE
  end
end

desc "Convert the wasm module to Ruby with dewasm"
task :generate do
  unless File.executable?(DEWASM_BIN)
    raise "dewasm binary not found at #{DEWASM_BIN}; set DEWASM_BIN"
  end
  raise "#{WASM_FILE} not found; run rake wasm:build" unless File.exist?(WASM_FILE)

  # The dewasm binary does not report its source revision, so the pinned revision is stated here and checked by the reader, not by this task.
  puts "dewasm binary: #{DEWASM_BIN} (pinned revision #{DEWASM_REVISION})"
  sh DEWASM_BIN,
     WASM_FILE,
     "--target",
     "ruby",
     "--mode",
     "library",
     "--module-name",
     "Dewasm::Pozeiden::WasmModule",
     "-o",
     GENERATED_FILE
end

desc "Measure sizes, memory, and speed, and rewrite the table in README.md"
task measure: :generate do
  sh RbConfig.ruby, "tools/measure.rb"
end

desc "Build the gem"
task build: :generate do
  sh "gem", "build", "dewasm-pozeiden.gemspec"
end

desc "Remove build products"
task :clean do
  rm_f [WASM_FILE, GENERATED_FILE]
  rm_rf File.join(WASM_DIR, "zig-out")
  rm_rf File.join(WASM_DIR, ".zig-cache")
end

Rake::TestTask.new(test: :generate) do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = false
end

task default: :test
