# typed: true

module RuboCop
  module Cop
    module PackageProtections
      class RequireDocumentedPublicApis < Modularization::RequireDocumentedPublicApis
        extend T::Sig
        include ::PackageProtections::RubocopProtectionInterface

        IDENTIFIER = 'prevent_this_package_from_exposing_undocumented_public_apis'.freeze

        include ::PackageProtections::RubocopProtectionInterface

        sig { override.returns(String) }
        def identifier
          IDENTIFIER
        end

        sig { override.returns(T::Array[String]) }
        def included_globs_for_pack
          [
            'app/public/**/*'
          ]
        end

        sig { override.params(behavior: ::PackageProtections::ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
        def unmet_preconditions_for_behavior(behavior, package)
          if !behavior.fail_never?
            readme_path = package.directory.join('README.md')
            if !readme_path.exist?
              "This package must have a readme at #{readme_path} to use this protection"
            end
          end
        end

        sig do
          override.params(file: String).returns(String)
        end
        def message_for_fail_on_any(file)
          "`#{file}` must contain documentation on every method (between signature and method)"
        end

        sig { override.returns(String) }
        def cop_name
          'PackageProtections/RequireDocumentedPublicApis'
        end

        sig { override.returns(String) }
        def humanized_protection_name
          'Documented Public APIs'
        end

        sig { override.returns(::PackageProtections::ViolationBehavior) }
        def default_behavior
          ::PackageProtections::ViolationBehavior::FailNever
        end

        sig { override.returns(String) }
        def humanized_protection_description
          <<~MESSAGE
            All public API must have a documentation comment (between the signature and method).
            This is failing because these files are in `.rubocop_todo.yml` under `#{cop_name}`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `#{IDENTIFIER}` to `#{::PackageProtections::ViolationBehavior::FailOnNew.serialize}`
          MESSAGE
        end
      end
    end
  end
end
