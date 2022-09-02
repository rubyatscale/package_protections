# typed: strict

module PackageProtections
  module Private
    class Configuration
      extend T::Sig

      sig { params(protections: T::Array[ProtectionInterface]).void }
      attr_writer :protections, :globally_permitted_namespaces

      sig { params(globally_permitted_namespaces: T::Array[String]).void }

      sig { void }
      def initialize
        @protections = T.let(default_protections, T::Array[ProtectionInterface])
        @globally_permitted_namespaces = T.let([], T::Array[String])
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def protections
        @protections
      end

      sig { returns(T::Array[String]) }
      def globally_permitted_namespaces
        @globally_permitted_namespaces
      end

      sig { void }
      def bust_cache!
        @protections = default_protections
        @globally_permitted_namespaces = []
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def default_protections
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
