# typed: strict
# frozen_string_literal: true

require 'package_protections/private/colorized_string'
require 'package_protections/private/output'
require 'package_protections/private/incoming_privacy_protection'
require 'package_protections/private/outgoing_dependency_protection'
require 'package_protections/private/metadata_modifiers'
require 'package_protections/private/configuration'

module PackageProtections
  #
  # This module cannot be accessed by clients of `PackageProtections` -- only within the `PackageProtections` module itself.
  # All implementation details are in here to keep the main `PackageProtections` module easily scannable and to keep the private things private.
  #
  module Private
    extend T::Sig

    sig do
      params(
        packages: T::Array[ParsePackwerk::Package],
        new_violations: T::Array[PerFileViolation]
      ).returns(T::Array[Offense])
    end
    def self.get_offenses(packages:, new_violations:)
      protected_packages = packages.map { |p| ProtectedPackage.from(p) }

      PackageProtections.all.flat_map do |protector|
        protector.get_offenses(protected_packages, new_violations)
      end
    end

    sig do
      params(
        packages: T::Array[ParsePackwerk::Package],
        protection_identifiers: T::Array[String],
        verbose: T::Boolean
      ).void
    end
    def self.set_defaults!(packages, protection_identifiers:, verbose:)
      information = <<~INFO
        We will attempt to set the defaults for #{packages.count} packages!
      INFO
      if verbose
        Private::Output.p_colorized Private::ColorizedString.new(information).yellow, colorized: true
      end

      new_protected_packages = []

      packages.each_with_index do |package, i|
        if verbose
          Private::Output.p_colorized Private::ColorizedString.new("[#{i + 1}/#{packages.count}] Setting defaults for #{package.name}").yellow, colorized: true
        end

        package_protections = PackageProtections.all.select { |p| protection_identifiers.include?(p.identifier) }
        package_protections.each do |protection|
          # We don't set defaults when the behavior is fail never because
          next if protection.default_behavior.fail_never?

          protections = package.metadata['protections'] || {}
          current_behavior = protections[protection.identifier]
          next if current_behavior.present?

          package = Private::MetadataModifiers.package_with_modified_protection(package, protection.identifier, protection.default_behavior)
        end

        package = ParsePackwerk::Package.new(
          name: package.name,
          # We set these values to be true always by default
          enforce_dependencies: true,
          enforce_privacy: true,
          dependencies: package.dependencies,
          metadata: package.metadata
        )

        new_protected_packages << ProtectedPackage.from(package)
      end

      new_protected_packages.each do |package|
        ParsePackwerk.write_package_yml!(package.original_package)
      end
    end

    sig { params(root_pathname: Pathname).returns(String) }
    def self.rubocop_yml(root_pathname:)
      protected_packages = Dir.chdir(root_pathname) { all_protected_packages }
      package_protection = T.cast(PackageProtections.all.select { |p| p.is_a?(RubocopProtectionInterface) }, T::Array[RubocopProtectionInterface])
      cop_configs = package_protection.flat_map { |p| p.cop_configs(protected_packages) }
      cop_configs.map(&:to_rubocop_yml_compatible_format).join("\n\n")
    end

    sig do
      returns(T::Array[ProtectedPackage])
    end
    def self.all_protected_packages
      # Note -- we should get rid of Package in favor of SimplePackage
      # Benchmark ParsePackwerk.all with package vs simple package
      # convert tools to use ParsePackwerk::DeprecatedReferences.from(packs.directory)
      # that should make this faster and not affect rubocop as much
      ParsePackwerk.all.map do |p|
        ProtectedPackage.from(p)
      end
    end

    sig { params(name: String).returns(ProtectedPackage) }
    def self.get_package_with_name(name)
      @protected_packages_indexed_by_name ||= T.let(@protected_packages_indexed_by_name, T.nilable(T::Hash[String, ProtectedPackage]))
      @protected_packages_indexed_by_name ||= all_protected_packages.each_with_object({}) { |package, index|
        index[package.name] = package
      }

      @protected_packages_indexed_by_name.fetch(name)
    end

    sig { void }
    def self.bust_cache!
      @protected_packages_indexed_by_name = nil
      PackageProtections.config.bust_cache!
      # This comes explicitly after `PackageProtections.config.bust_cache!` because
      # otherwise `PackageProtections.config` will attempt to reload the client configuratoin.
      @loaded_client_configuration = false
    end

    sig { void }
    def self.load_client_configuration
      @loaded_client_configuration ||= T.let(false, T.nilable(T::Boolean))
      return if @loaded_client_configuration

      @loaded_client_configuration = true
      client_configuration = Pathname.pwd.join('config/package_protections.rb')
      require client_configuration.to_s if client_configuration.exist?
    end
  end

  private_constant :Private
end
