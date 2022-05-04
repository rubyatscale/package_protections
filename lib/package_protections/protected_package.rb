# frozen_string_literal: true

# typed: strict
module PackageProtections
  class ProtectedPackage < T::Struct
    extend T::Sig

    const :original_package, ParsePackwerk::Package
    const :protections, T::Hash[Identifier, ViolationBehavior]
    const :deprecated_references, ParsePackwerk::DeprecatedReferences

    sig { params(original_package: ParsePackwerk::Package).returns(ProtectedPackage) }
    def self.from(original_package)
      metadata = original_package.metadata['protections'] || {}

      valid_identifiers = PackageProtections.all.map(&:identifier)
      invalid_identifiers = metadata.keys - valid_identifiers

      if invalid_identifiers.any?
        raise IncorrectPublicApiUsageError.new("Invalid configuration for package `#{original_package.name}`. The metadata keys #{invalid_identifiers.inspect} are not valid behaviors under the `protection` metadata namespace. Valid keys are #{valid_identifiers.inspect}. See https://github.com/bigrails/package_protections#readme for more info") # rubocop:disable Style/RaiseArgs
      end

      protections = {}
      metadata.each_key do |protection_key|
        protection = PackageProtections.with_identifier(protection_key)
        if !protection
          raise IncorrectPublicApiUsageError.new("Invalid configuration for package `#{original_package.name}`. The metadata key #{protection_key} is not a valid behaviors under the `protection` metadata namespace. Valid keys are #{valid_identifiers.inspect}. See https://github.com/bigrails/package_protections#readme for more info") # rubocop:disable Style/RaiseArgs
        end

        protections[protection.identifier] = get_violation_behavior(protection, metadata, original_package)
      end

      unspecified_protections = valid_identifiers - protections.keys
      protections_requiring_explicit_configuration = T.let([], T::Array[Identifier])
      unspecified_protections.each do |protection_key|
        protection = PackageProtections.with_identifier(protection_key)
        if !protection.default_behavior.fail_never?
          protections_requiring_explicit_configuration << protection.identifier
        end
        protections[protection_key] = protection.default_behavior
      end

      if protections_requiring_explicit_configuration.any?
        error = "All protections must explicitly set unless their default behavior is `fail_never`. Missing protections: #{protections_requiring_explicit_configuration.join(', ')}"
        raise IncorrectPublicApiUsageError, error
      end

      new(
        original_package: original_package,
        protections: protections,
        deprecated_references: ParsePackwerk::DeprecatedReferences.for(original_package)
      )
    end

    sig { params(protection: ProtectionInterface, metadata: T::Hash[T.untyped, T.untyped], package: ParsePackwerk::Package).returns(ViolationBehavior) }
    def self.get_violation_behavior(protection, metadata, package)
      behavior = ViolationBehavior.from_raw_value(metadata[protection.identifier])
      unmet_preconditions = protection.unmet_preconditions_for_behavior(behavior, package)
      if !unmet_preconditions.nil?
        raise IncorrectPublicApiUsageError.new("#{protection.identifier} protection does not have the valid preconditions. #{unmet_preconditions}. See https://github.com/bigrails/package_protections#readme for more info") # rubocop:disable Style/RaiseArgs
      end

      behavior
    end

    sig { params(key: Identifier).returns(ViolationBehavior) }
    def violation_behavior_for(key)
      protections.fetch(key)
    end

    sig { returns(String) }
    def name
      original_package.name
    end

    sig { returns(ParsePackwerk::MetadataYmlType) }
    def metadata
      original_package.metadata
    end

    sig { returns(Pathname) }
    def yml
      original_package.yml
    end

    sig { returns(T::Array[String]) }
    def dependencies
      original_package.dependencies
    end

    sig { returns(T::Set[String]) }
    def visible_to
      Set.new(metadata['visible_to'] || [])
    end

    sig { returns(T::Array[ParsePackwerk::Violation]) }
    def violations
      deprecated_references.violations
    end
  end
end
