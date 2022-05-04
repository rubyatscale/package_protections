# typed: strict
# frozen_string_literal: true

module PackageProtections
  module Private
    class OutgoingDependencyProtection
      extend T::Sig

      include ProtectionInterface

      IDENTIFIER = 'prevent_this_package_from_violating_its_stated_dependencies'

      sig { override.returns(String) }
      def identifier
        IDENTIFIER
      end

      sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
      def unmet_preconditions_for_behavior(behavior, package)
        if behavior.enabled? && !package.enforces_dependencies?
          "Package #{package.name} must have `enforce_dependencies: true` to use this protection"
        elsif !behavior.enabled? && package.enforces_dependencies?
          "Package #{package.name} must have `enforce_dependencies: false` to turn this protection off"
        else
          nil
        end
      end

      sig { override.returns(String) }
      def humanized_protection_name
        'Dependency Violations'
      end

      sig { override.returns(String) }
      def humanized_protection_description
        <<~MESSAGE
          To resolve these violations, should you add a dependency in the client's `package.yml`?
          Is the code referencing the constant, and the referenced constant, in the right packages?
          See https://go/packwerk_cheatsheet_dependency for more info.
        MESSAGE
      end

      sig do
        override.params(
          new_violations: T::Array[PerFileViolation]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_new_violations(new_violations)
        new_violations.select(&:dependency?).flat_map do |per_file_violation|
          reference_source_package = Private.get_package_with_name(per_file_violation.reference_source_package.name)
          violation_behavior = reference_source_package.violation_behavior_for(identifier)

          case violation_behavior
          when ViolationBehavior::FailNever
            next []
          when ViolationBehavior::FailOnNew
            message = message_for_fail_on_new(per_file_violation)
          when ViolationBehavior::FailOnAny
            message = message_for_fail_on_any(per_file_violation)
          else
            T.absurd(violation_behavior)
          end

          Offense.new(
            file: per_file_violation.filepath,
            message: message,
            violation_type: identifier,
            package: reference_source_package.original_package
          )
        end
      end

      sig do
        override.params(
          protected_packages: T::Array[ProtectedPackage]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_existing_violations(protected_packages)
        protected_packages.flat_map do |protected_package|
          violation_behavior = protected_package.violation_behavior_for(identifier)

          case violation_behavior
          when ViolationBehavior::FailNever, ViolationBehavior::FailOnNew
            []
          when ViolationBehavior::FailOnAny
            listed_violations = protected_package.violations.select(&:dependency?).flat_map do |violation|
              PerFileViolation.from(violation, protected_package.original_package)
            end

            listed_violations.flat_map do |per_file_violation|
              Offense.new(
                file: per_file_violation.filepath,
                message: message_for_fail_on_any(per_file_violation),
                violation_type: identifier,
                package: protected_package.original_package
              )
            end
          else
            T.absurd(violation_behavior)
          end
        end
      end

      private

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_any(per_file_violation)
        "#{message_for_fail_on_new(per_file_violation)} (`#{per_file_violation.reference_source_package.name}` set to `fail_on_any`)"
      end

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_new(per_file_violation)
        "`#{per_file_violation.filepath}` depends on `#{per_file_violation.class_name}` from `#{per_file_violation.constant_source_package}`"
      end
    end
  end
end
