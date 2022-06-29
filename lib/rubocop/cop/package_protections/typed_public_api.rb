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
        extend T::Sig

        include ::PackageProtections::ProtectionInterface
        include ::PackageProtections::RubocopProtectionInterface

        IDENTIFIER = 'prevent_this_package_from_exposing_an_untyped_api'

        sig { override.returns(String) }
        def identifier
          IDENTIFIER
        end

        sig { override.params(behavior: ::PackageProtections::ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
        def unmet_preconditions_for_behavior(behavior, package)
          # We might decide that we should check that `package.enforces_privacy?` is true here too, since that signifies the app has decided they want
          # a public api in `app/public`. For now, we say there are no preconditions, because the user can still make `app/public` even if they are not yet
          # ready to enforce privacy, and they might want to enforce a typed API.
          nil
        end

        sig { override.returns(String) }
        def cop_name
          'PackageProtections/TypedPublicApi'
        end

        sig { override.returns(T::Array[String]) }
        def included_globs_for_pack
          [
            'app/public/**/*',
          ]
        end

        sig do
          override.params(file: String).returns(String)
        end
        def message_for_fail_on_any(file)
          "#{file} should be `typed: strict`"
        end

        sig { override.returns(String) }
        def humanized_protection_name
          'Typed API Violations'
        end

        sig { override.returns(String) }
        def humanized_protection_description
          <<~MESSAGE
            These files cannot have ANY Ruby files in the public API that are not typed strict or higher.
            This is failing because these files are in `.rubocop_todo.yml` under `#{cop_name}`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `#{IDENTIFIER}` to `#{::PackageProtections::ViolationBehavior::FailOnNew.serialize}`

            See https://go/packwerk_cheatsheet_typed_api for more info.
          MESSAGE
        end
      end
    end
  end
end
