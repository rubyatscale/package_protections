# typed: strict
# frozen_string_literal: true

module PackageProtections
  module Private
    class TypedApiProtection
      extend T::Sig

      include ProtectionInterface
      include RubocopProtectionInterface

      IDENTIFIER = 'prevent_this_package_from_exposing_an_untyped_api'
      COP_NAME = 'Sorbet/StrictSigil'

      sig { override.returns(String) }
      def identifier
        IDENTIFIER
      end

      sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
      def unmet_preconditions_for_behavior(behavior, package)
        # We might decide that we should check that `package.enforces_privacy?` is true here too, since that signifies the app has decided they want
        # a public api in `app/public`. For now, we say there are no preconditions, because the user can still make `app/public` even if they are not yet
        # ready to enforce privacy, and they might want to enforce a typed API.
        nil
      end

      sig do
        override
          .params(packages: T::Array[ProtectedPackage])
          .returns(T::Array[CopConfig])
      end
      def cop_configs(packages)
        include_paths = T.let([], T::Array[String])
        packages.each do |p|
          if p.violation_behavior_for(identifier).enabled?
            directory = p.original_package.directory
            include_paths << directory.join('app', 'public', '**', '*').to_s
          end
        end

        [
          CopConfig.new(
            name: COP_NAME,
            enabled: include_paths.any?,
            include_paths: include_paths
          )
        ]
      end

      sig do
        override.params(
          protected_packages: T::Array[ProtectedPackage]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_existing_violations(protected_packages)
        exclude_list = exclude_for_rule(COP_NAME)

        offenses = T.let([], T::Array[Offense])
        protected_packages.flat_map do |protected_package|
          violation_behavior = protected_package.violation_behavior_for(identifier)

          case violation_behavior
          when ViolationBehavior::FailNever, ViolationBehavior::FailOnNew
            next
          when ViolationBehavior::FailOnAny
            # Continue
          else
            T.absurd(violation_behavior)
          end

          protected_package.original_package.directory.glob('app/public/**/**/*.*').each do |relative_path_to_file|
            next unless exclude_list.include?(relative_path_to_file.to_s)

            file = relative_path_to_file.to_s
            offenses << Offense.new(
              file: file,
              message: "#{file} should be `typed: strict`",
              violation_type: identifier,
              package: protected_package.original_package
            )
          end
        end

        offenses
      end

      sig { override.returns(String) }
      def humanized_protection_name
        'Typed API Violations'
      end

      sig { override.returns(String) }
      def humanized_protection_description
        <<~MESSAGE
          These files cannot have ANY Ruby files in the public API that are not typed strict or higher.
          This is failing because these files are in `.rubocop_todo.yml` under `#{COP_NAME}`.
          If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
          change `#{IDENTIFIER}` to `#{ViolationBehavior::FailOnNew.serialize}`

          See https://go/packwerk_cheatsheet_typed_api for more info.
        MESSAGE
      end
    end
  end
end
