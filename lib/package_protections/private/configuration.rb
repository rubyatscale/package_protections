# typed: strict

module PackageProtections
  module Private
    class Configuration
      extend T::Sig

      sig { returns(T::Array[ProtectionInterface]) }
      attr_accessor :protections

      sig { returns(T::Array[String]) }
      attr_accessor :globally_permitted_namespaces

      sig { returns(T::Array[String]) }
      attr_accessor :acceptable_parent_classes

      sig { void }
      def initialize
        @protections = T.let(default_protections, T::Array[ProtectionInterface])
        @globally_permitted_namespaces = T.let([], T::Array[String])
        @acceptable_parent_classes = T.let([], T::Array[String])
      end
      sig { void }
      def bust_cache!
        @protections = default_protections
        @globally_permitted_namespaces = []
        @acceptable_parent_classes = []
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def default_protections
        [
          Private::OutgoingDependencyProtection.new,
          Private::IncomingPrivacyProtection.new,
          RuboCop::Cop::PackageProtections::TypedPublicApi.new,
          RuboCop::Cop::PackageProtections::NamespacedUnderPackageName.new,
          RuboCop::Cop::PackageProtections::OnlyClassMethods.new,
          RuboCop::Cop::PackageProtections::RequireDocumentedPublicApis.new
        ]
      end
    end
  end
end
