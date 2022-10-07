# typed: true

module RuboCop
  module Cop
    module PackageProtections
      class OnlyClassMethods < Modularization::ClassMethodsAsPublicApis
        extend T::Sig
        include ::PackageProtections::RubocopProtectionInterface

        IDENTIFIER = 'prevent_this_package_from_exposing_instance_method_public_apis'.freeze

        sig { override.returns(String) }
        def humanized_protection_description
          <<~MESSAGE
            Public API methods can only be static methods.
            This is failing because these files are in `.rubocop_todo.yml` under `#{cop_name}`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `#{IDENTIFIER}` to `#{::PackageProtections::ViolationBehavior::FailOnNew.serialize}`
          MESSAGE
        end

        sig do
          override.params(file: String).returns(String)
        end
        def message_for_fail_on_any(file)
          "`#{file}` must only contain static (class or module level) methods"
        end

        sig { override.returns(T::Array[String]) }
        def included_globs_for_pack
          [
            'app/public/**/*',
          ]
        end

        sig { override.returns(String) }
        def identifier
          IDENTIFIER
        end

        sig { override.returns(String) }
        def humanized_protection_name
          'Class Method Public APIs'
        end

        sig { override.returns(String) }
        def cop_name
          'PackageProtections/OnlyClassMethods'
        end

        sig { override.returns(::PackageProtections::ViolationBehavior) }
        def default_behavior
          ::PackageProtections::ViolationBehavior::FailNever
        end
      end
    end
  end
end
