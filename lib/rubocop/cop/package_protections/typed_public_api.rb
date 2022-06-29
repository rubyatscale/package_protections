# typed: strict

module RuboCop
  module Cop
    module PackageProtections
      #
      # This inherits from `Sorbet::StrictSigil` and doesn't change any behavior of it.
      # The only reason we do this is so that configuration for this cop can live under a different cop namespace.
      # This prevents this cop's configuration from clashing with other configurations for the same cop.
      # A concrete example of this would be if a user is using this package protection to make sure public APIs are typed,
      # and separately the application as a whole requiring strict typing in certain parts of the application.
      #
      # To prevent problems associated with needing to manage identical configurations for the same cop, we simply call it
      # something else in the context of this protection.
      #
      # We can apply this same pattern if we want to use other cops in the context of package protections and prevent clashing.
      #
      class TypedPublicApi < Sorbet::StrictSigil
      end
    end
  end
end
