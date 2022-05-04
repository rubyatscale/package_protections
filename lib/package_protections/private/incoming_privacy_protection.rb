# typed: strict
# frozen_string_literal: true

module PackageProtections
  module Private
    class IncomingPrivacyProtection
      extend T::Sig

      include ProtectionInterface

      IDENTIFIER = 'prevent_other_packages_from_using_this_packages_internals'

      sig { override.returns(String) }
      def identifier
        IDENTIFIER
      end

      sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
      def unmet_preconditions_for_behavior(behavior, package)
        if behavior.enabled? && !package.enforces_privacy?
          "Package #{package.name} must have `enforce_privacy: true` to use this protection"
        elsif !behavior.enabled? && package.enforces_privacy?
          "Package #{package.name} must have `enforce_privacy: false` to turn this protection off"
        else
          nil
        end
      end

      sig { override.returns(String) }
      def humanized_protection_name
        'Privacy Violations'
      end

      sig { override.returns(String) }
      def humanized_protection_description
        <<~MESSAGE
          To resolve these violations, check the `public/` folder in each pack for public constants and APIs.
          If you need help or can't find what you need to meet your use case, reach out to the owning team.
          See https://go/packwerk_cheatsheet_privacy for more info.
        MESSAGE
      end

      sig do
        override.params(
          new_violations: T::Array[PerFileViolation]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_new_violations(new_violations)
        new_violations.select(&:privacy?).flat_map do |per_file_violation|
          protected_package = Private.get_package_with_name(per_file_violation.constant_source_package)
          violation_behavior = protected_package.violation_behavior_for(identifier)

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
            package: protected_package.original_package
          )
        end
      end

      sig do
        override.params(
          protected_packages: T::Array[ProtectedPackage]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_existing_violations(protected_packages)
        all_listed_violations = protected_packages.flat_map do |protected_package|
          protected_package.violations.select(&:privacy?).flat_map do |violation|
            PerFileViolation.from(violation, protected_package.original_package)
          end
        end

        all_listed_violations.flat_map do |per_file_violation|
          constant_source_package = Private.get_package_with_name(per_file_violation.constant_source_package)
          violation_behavior = constant_source_package.violation_behavior_for(identifier)

          case violation_behavior
          when ViolationBehavior::FailNever, ViolationBehavior::FailOnNew
            []
          when ViolationBehavior::FailOnAny
            Offense.new(
              file: per_file_violation.filepath,
              message: message_for_fail_on_any(per_file_violation),
              violation_type: identifier,
              package: constant_source_package.original_package
            )
          else
            T.absurd(violation_behavior)
          end
        end
      end

      private

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_any(per_file_violation)
        "#{message_for_fail_on_new(per_file_violation)} (`#{per_file_violation.constant_source_package}` set to `fail_on_any`)"
      end

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_new(per_file_violation)
        "`#{per_file_violation.filepath}` references private `#{per_file_violation.class_name}` from `#{per_file_violation.constant_source_package}`"
      end
    end
  end
end
