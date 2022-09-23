require 'pry'
require 'package_protections'
require 'rubocop/rspec/support'
require 'package_protections/rspec/support'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.filter_run_when_matching :focus

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.around do |example|
    ParsePackwerk.bust_cache!
    example.run
  end

  config.around do |example|
    prefix = [File.basename($0), Process.pid].join('-') # rubocop:disable Style/SpecialGlobalVars
    tmpdir = Dir.mktmpdir(prefix)

    begin
      Dir.chdir(tmpdir) do
        example.run
      end
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  config.include(RuboCop::RSpec::ExpectOffense)

  config.include(ApplicationFixtureHelper)

  config.define_derived_metadata(file_path: %r{/spec/lib/rubocop/cop/rspec}) do |meta|
    meta[:type] = :rubocop_rspec_spec
  end
end
