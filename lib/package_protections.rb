# frozen_string_literal: true

# typed: strict

require 'sorbet-runtime'
require 'open3'
require 'set'
require 'parse_packwerk'
require 'rubocop'
require 'rubocop-sorbet'
require 'rubocop-packs'

#
# Welcome to PackageProtections!
# See https://github.com/rubyatscale/package_protections#readme for more info
#
# This file is a reference for the available API to `package_protections`, but all implementation details are private
# (which is why we delegate to `Private` for the actual implementation).
#
module PackageProtections
  extend T::Sig

  PROTECTIONS_TODO_YML = 'protections_todo.yml'
  EXPECTED_PACK_DIRECTORIES = T.let(%w[packs packages gems components], T::Array[String])

  # A protection identifier is just a string that identifies the name of the protection within a `package.yml`
  Identifier = T.type_alias { String }

  # This is currently the only handled exception that `PackageProtections` will throw.
  class IncorrectPublicApiUsageError < StandardError; end

  require 'package_protections/offense'
  require 'package_protections/violation_behavior'
  require 'package_protections/protected_package'
  require 'package_protections/per_file_violation'
  require 'package_protections/protection_interface'
  require 'package_protections/rubocop_protection_interface'
  require 'package_protections/private'

  # Implementation of rubocop-based protections
  require 'rubocop/cop/package_protections/namespaced_under_package_name'
  require 'rubocop/cop/package_protections/typed_public_api'
  require 'rubocop/cop/package_protections/only_class_methods'
  require 'rubocop/cop/package_protections/require_documented_public_apis'

  class << self
    extend T::Sig

    sig { params(blk: T.proc.params(arg0: Private::Configuration).void).void }
    def configure(&blk)
      yield(PackageProtections.config)
    end
  end

  sig { returns(T::Array[ProtectionInterface]) }
  def self.all
    config.protections
  end

  sig { returns(Private::Configuration) }
  def self.config
    Private.load_client_configuration
    @config = T.let(@config, T.nilable(Private::Configuration))
    @config ||= Private::Configuration.new
  end

  #
  # This is a fast way to get a protection given an identifier
  #
  sig { params(identifier: Identifier).returns(ProtectionInterface) }
  def self.with_identifier(identifier)
    @map ||= T.let(@map, T.nilable(T::Hash[Identifier, ProtectionInterface]))
    @map ||= all.to_h { |protection| [protection.identifier, protection] }
    @map.fetch(identifier)
  end

  #
  # This returns an array of a `Offense` which is how we represent the outcome of attempting to protect one or more packages,
  # each of which is configured with different violation behaviors for each protection.
  #
  sig do
    params(
      packages: T::Array[ParsePackwerk::Package],
      new_violations: T::Array[PerFileViolation]
    ).returns(T::Array[Offense])
  end
  def self.get_offenses(packages:, new_violations:)
    Private.get_offenses(
      packages: packages,
      new_violations: new_violations
    ).compact
  end

  sig do
    returns(T::Array[String])
  end
  def self.validate!
    errors = T.let([], T::Array[String])
    valid_identifiers = PackageProtections.all.map(&:identifier)

    ParsePackwerk.all.each do |p|
      metadata = p.metadata['protections'] || {}

      # Validate that there are no invalid keys
      invalid_identifiers = metadata.keys - valid_identifiers
      if invalid_identifiers.any?
        errors << "Invalid configuration for package `#{p.name}`. The metadata keys #{invalid_identifiers.inspect} are not a valid behavior under the `protection` metadata namespace. Valid keys are #{valid_identifiers.inspect}. See https://github.com/rubyatscale/package_protections#readme for more info"
      end

      # Validate that all protections requiring configuration have explicit configuration
      unspecified_protections = valid_identifiers - metadata.keys
      protections_requiring_explicit_configuration = unspecified_protections.select do |protection_key|
        protection = PackageProtections.with_identifier(protection_key)
        !protection.default_behavior.fail_never?
      end

      protections_requiring_explicit_configuration.each do |protection_identifier|
        errors << "All protections must explicitly set unless their default behavior is `fail_never`. Missing protection #{protection_identifier} for package #{p.name}."
      end

      # Validate that all protections have all preconditions met
      metadata.each do |protection_identifier, value|
        next if !valid_identifiers.include?(protection_identifier)
        behavior = ViolationBehavior.from_raw_value(value)
        protection = PackageProtections.with_identifier(protection_identifier)
        unmet_preconditions = protection.unmet_preconditions_for_behavior(behavior, p)
        if unmet_preconditions
          errors << "#{protection_identifier} protection does not have the valid preconditions in #{p.name}. #{unmet_preconditions}. See https://github.com/rubyatscale/package_protections#readme for more info"
        end
      end
    end

    errors
  end

  #
  # PackageProtections.set_defaults! sets any unset protections to their default enforcement
  #
  sig do
    params(
      packages: T::Array[ParsePackwerk::Package],
      protection_identifiers: T::Array[String],
      verbose: T::Boolean
    ).void
  end
  def self.set_defaults!(packages, protection_identifiers: PackageProtections.all.map(&:identifier), verbose: true)
    Private.set_defaults!(packages, protection_identifiers: protection_identifiers, verbose: verbose)
  end

  # Why do we use Bundler.root here?
  # The reason is that this function is evaluated in `.client_rubocop.yml`, so when rubocop evaluates the
  # YML and parses the ERB, the working directory is inside this gem. We need to make sure it's at the root of the
  # application so that we can find all of the packwerk packages.
  # We use Bundler.root to get the root because:
  # A) We expect it to be reliable
  # B) We expect the client to be running bundle exec rubocop, which is typically done at the root, and also means
  # the client already has this dependency.
  sig { params(root_pathname: Pathname).returns(String) }
  def self.rubocop_yml(root_pathname: Bundler.root)
    Private.rubocop_yml(root_pathname: root_pathname)
  end

  sig { void }
  def self.bust_cache!
    Private.bust_cache!
    RuboCop::Packs.bust_cache!
  end
end
