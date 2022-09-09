require 'rubocop'
require 'rubocop-sorbet'

module Rubocop
  module Cop
    module PackageProtections
      autoload :NamespacedUnderPackageName, 'rubocop/cop/package_protections/namespaced_under_package_name'
      autoload :TypedPublicApi, 'rubocop/cop/package_protections/typed_public_api'
    end
  end
end

# Implementation of rubocop-based protections
