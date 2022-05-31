# typed: strict

module PackageProtections
  module Private
    class Configuration
      extend T::Sig

      sig { params(protections: T::Array[ProtectionInterface]).void }
      attr_writer :protections
 
      sig { void }
      def initialize
        @protections = T.let(@protections, T.nilable(T::Array[ProtectionInterface]))
      end

      sig { returns(T::Array[ProtectionInterface]) }
      def protections
        @protections ||= [
          Private::OutgoingDependencyProtection.new,
          Private::IncomingPrivacyProtection.new,
          Private::TypedApiProtection.new,
          Private::MultipleNamespacesProtection.new,
          Private::VisibilityProtection.new
        ]
      end

      sig { void }
      def bust_cache!
        @protections = nil
      end
    end
  end
end
