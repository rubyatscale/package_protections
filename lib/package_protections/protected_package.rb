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
      protections = {}
      metadata.each_key do |protection_key|
        protection = PackageProtections.with_identifier(protection_key)
        if !protection
          raise IncorrectPublicApiUsageError.new("Invalid configuration for package `#{original_package.name}`. The metadata key #{protection_key} is not a valid behaviors under the `protection` metadata namespace. Valid keys are #{valid_identifiers.inspect}. See https://github.com/rubyatscale/package_protections#readme for more info") # rubocop:disable Style/RaiseArgs
        end

        protections[protection.identifier] = get_violation_behavior(protection, metadata, original_package)
      end

      unspecified_protections = valid_identifiers - protections.keys
      unspecified_protections.each do |protection_key|
        protections[protection_key] = PackageProtections.with_identifier(protection_key).default_behavior
      end

      new(
        original_package: original_package,
        protections: protections,
        deprecated_references: ParsePackwerk::DeprecatedReferences.for(original_package)
      )
    end

    sig { params(protection: ProtectionInterface, metadata: T::Hash[T.untyped, T.untyped], package: ParsePackwerk::Package).returns(ViolationBehavior) }
    def self.get_violation_behavior(protection, metadata, package)
      ViolationBehavior.from_raw_value(metadata[protection.identifier])
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

    sig { returns(T::Array[ParsePackwerk::Violation]) }
    def violations
      deprecated_references.violations
    end
  end
end
