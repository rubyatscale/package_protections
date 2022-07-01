# frozen_string_literal: true

# Require this file to load code that supports testing using RSpec.

require_relative 'application_fixture_helper'
require_relative 'matchers'

def get_resulting_rubocop
  write_file('config/default.yml', <<~YML.strip)
    <%= PackageProtections.rubocop_yml(root_pathname: Pathname.pwd) %>
  YML
  YAML.safe_load(ERB.new(File.read('config/default.yml')).result(binding))
end

RSpec.configure do |config|
  config.include ApplicationFixtureHelper

  config.before do |example|
    PackageProtections.bust_cache!
  end
end
