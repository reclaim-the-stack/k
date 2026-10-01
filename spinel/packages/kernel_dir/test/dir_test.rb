require "kernel_dir"

# Under CRuby __dir__ is this test's directory, under Spinel the compiled test's. Both are absolute,
# canonical and hold the running program.
dir = __dir__
p dir.start_with?("/")
p dir == File.realpath(dir)
p File.exist?(File.join(dir, File.basename($PROGRAM_NAME)))
p File.basename(dir)
