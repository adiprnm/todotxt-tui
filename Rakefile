# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << 'test' << 'lib'
  task.test_files = FileList['test/**/*_test.rb']
end

desc 'Build a standalone binary with Spinel'
task :spinel do
  # Bundler itself cannot be compiled, so the load paths are passed with -I.
  # The patched ruby-tui sources live in a sibling checkout by default; set
  # RUBY_TUI_LIB to point somewhere else, OUT to rename the binary.
  ruby_tui = ENV['RUBY_TUI_LIB']
  ruby_tui ||= File.expand_path('../ruby-tui/lib') if File.directory?('../ruby-tui/lib')
  abort 'RUBY_TUI_LIB must point at the ruby-tui lib directory' unless ruby_tui

  sh "spinel bin/todotui.spinel.rb -o #{ENV['OUT'] || 'tt'} -I lib -I #{ruby_tui}"
end

desc 'Build and install the tt native binary to BINDIR (default ~/.local/bin)'
task install: :spinel do
  bindir = ENV['BINDIR'] || File.join(Dir.home, '.local', 'bin')
  FileUtils.mkdir_p(bindir)
  dest = File.join(bindir, 'tt')
  # Remove first: a symlink would otherwise make install write through it.
  FileUtils.rm_f(dest) if File.symlink?(dest)
  FileUtils.install(ENV['OUT'] || 'tt', dest, mode: 0o755)
  puts "installed #{dest}"
end

task default: :test
