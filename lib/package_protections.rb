# frozen_string_literal: true

# typed: strict
require 'sorbet-runtime'
require 'open3'
require 'set'
require 'parse_packwerk'
require 'rubocop'
require 'rubocop-sorbet'

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
    @map ||= all.map { |protection| [protection.identifier, protection] }.to_h
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

  #
  # Do not use this method -- it's meant to be used by Rubocop cops to get directory-specific
  # parameters without needing to have directory-specific .rubocop.yml files.
  #
  sig { params(identifier: Identifier).returns(T::Hash[T.untyped, T.untyped]) }
  def self.private_cop_config(identifier)
    Private.private_cop_config(identifier)
  end

  sig { void }
  def self.bust_cache!
    Private.bust_cache!
    RubocopProtectionInterface.bust_rubocop_todo_yml_cache
  end
end
