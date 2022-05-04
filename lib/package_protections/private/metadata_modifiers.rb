# frozen_string_literal: true

# typed: strict
module PackageProtections
  module Private
    class MetadataModifiers
      extend T::Sig

      sig { params(package: ParsePackwerk::Package, protection_identifier: Identifier, violation_behavior: ViolationBehavior).returns(ParsePackwerk::Package) }
      def self.package_with_modified_protection(package, protection_identifier, violation_behavior)
        # We dup this to prevent mutations to the original underlying hash
        new_metadata = package.metadata.dup
        protections = new_metadata['protections'].dup || {}
        protections[protection_identifier] = violation_behavior.serialize
        new_metadata['protections'] = protections

        ParsePackwerk::Package.new(
          name: package.name,
          enforce_dependencies: package.enforce_dependencies,
          enforce_privacy: package.enforce_privacy,
          dependencies: package.dependencies,
          metadata: new_metadata
        )
      end
    end
  end
end
