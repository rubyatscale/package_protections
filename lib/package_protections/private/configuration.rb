# typed: strict

module PackageProtections
  module Private
    class Configuration
      extend T::Sig

      sig { params(protections: T::Array[ProtectionInterface]).void }
      attr_writer :protections

      sig { void }
      def initialize
        @protections = T.let(default_protections, T::Array[ProtectionInterface])
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def protections
        @protections
      end

      sig { void }
      def bust_cache!
        @protections = default_protections
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def default_protections
        require 'rubocop/cop/package_protections'

        [
          Private::OutgoingDependencyProtection.new,
          Private::IncomingPrivacyProtection.new,
          RuboCop::Cop::PackageProtections::TypedPublicApi.new,
          RuboCop::Cop::PackageProtections::NamespacedUnderPackageName.new,
          Private::VisibilityProtection.new
        ]
      end
    end
  end
end
