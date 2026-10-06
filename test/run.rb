# frozen_string_literal: true

# Run the whole suite in one process: bundle exec ruby test/run.rb
Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |file| require file }
