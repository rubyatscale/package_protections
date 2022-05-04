# typed: strict
# frozen_string_literal: true

module PackageProtections
  module Private
    class VisibilityProtection
      extend T::Sig

      include ProtectionInterface

      IDENTIFIER = 'prevent_other_packages_from_using_this_package_without_explicit_visibility'

      sig { override.returns(String) }
      def identifier
        IDENTIFIER
      end

      sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
      def unmet_preconditions_for_behavior(behavior, package)
        # This protection relies on seeing privacy violations in other packages.
        # We also require that the other package enforces dependencies, as otherwise, if the client is using public API, it won't show up
        # as a privacy OR dependency violation. For now, we don't have the system structure to support that requirement.
        if behavior.enabled? && !package.enforces_privacy?
          "Package #{package.name} must have `enforce_privacy: true` to use this protection"
        elsif !behavior.enabled? && !package.metadata['visible_to'].nil?
          "Invalid configuration for package `#{package.name}`. `#{identifier}` must be turned on to use `visible_to` configuration."
        else
          nil
        end
      end

      #
      # By default, this protection does not show up when creating a new package, and its default behavior is FailNever
      # A package that uses this protection is not considered strictly better -- in general, we want to design packages that
      # are consumable by all packages. Therefore, a package that is consumable by all packages is the happy path.
      #
      # If a user wants to turn on package visibility, they must do it explicitly.
      #
      sig { returns(ViolationBehavior) }
      def default_behavior
        ViolationBehavior::FailNever
      end

      sig { override.returns(String) }
      def humanized_protection_name
        'Visibility Violations'
      end

      sig { override.returns(String) }
      def humanized_protection_description
        <<~MESSAGE
          These files are using a constant from a package that restricts its usage through the `visible_to` flag in its `package.yml`
          To resolve these violations, work with the team who owns the package you are trying to use and to figure out the
          preferred public API for the behavior you want.

          See https://go/packwerk_cheatsheet_visibility for more info.
        MESSAGE
      end

      sig do
        override.params(
          new_violations: T::Array[PerFileViolation]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_new_violations(new_violations)
        new_violations.flat_map do |per_file_violation|
          depended_on_package = Private.get_package_with_name(per_file_violation.constant_source_package)
          violation_behavior = depended_on_package.violation_behavior_for(identifier)
          visible_to = depended_on_package.visible_to
          next [] if visible_to.include?(per_file_violation.reference_source_package.name)

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
            package: depended_on_package.original_package
          )
        end
      end

      sig do
        override.params(
          protected_packages: T::Array[ProtectedPackage]
        ).returns(T::Array[Offense])
      end
      def get_offenses_for_existing_violations(protected_packages)
        all_offenses = T.let([], T::Array[Offense])

        all_listed_violations = protected_packages.flat_map do |protected_package|
          protected_package.violations.flat_map do |violation|
            PerFileViolation.from(violation, protected_package.original_package)
          end
        end

        #
        # First we get offenses related to violations between packages, looking at all dependency and privacy
        # violations between packages.
        #

        # We only care about looking at each edge once. Since an edge can show up twice if its both a privacy and dependency violation,
        # we only look at each combination of class from package (A) that's referenced in package (B)
        unique_per_file_violations = all_listed_violations.uniq do |per_file_violation|
          [per_file_violation.reference_source_package.name, per_file_violation.constant_source_package, per_file_violation.class_name]
        end

        all_offenses += unique_per_file_violations.flat_map do |per_file_violation|
          depended_on_package = Private.get_package_with_name(per_file_violation.constant_source_package)
          violation_behavior = depended_on_package.violation_behavior_for(identifier)
          visible_to = depended_on_package.visible_to
          next [] if visible_to.include?(per_file_violation.reference_source_package.name)

          case violation_behavior
          when ViolationBehavior::FailNever, ViolationBehavior::FailOnNew
            next []
          when ViolationBehavior::FailOnAny
            message = message_for_fail_on_any(per_file_violation)
          else
            T.absurd(violation_behavior)
          end

          Offense.new(
            file: per_file_violation.filepath,
            message: message,
            violation_type: identifier,
            package: depended_on_package.original_package
          )
        end

        #
        # Then we get offenses from stated dependencies
        #
        all_offenses += protected_packages.flat_map do |protected_package|
          protected_package.dependencies.flat_map do |package_dependency_name|
            depended_on_package = Private.get_package_with_name(package_dependency_name)
            visible_to = depended_on_package.visible_to
            next [] if visible_to.include?(protected_package.name)

            violation_behavior = depended_on_package.violation_behavior_for(identifier)

            case violation_behavior
            when ViolationBehavior::FailNever
              next []
            when ViolationBehavior::FailOnAny, ViolationBehavior::FailOnNew
              # continue
            else
              T.absurd(violation_behavior)
            end

            message = "`#{protected_package.name}` cannot state a dependency on `#{depended_on_package.name}`, as it violates package visibility in `#{depended_on_package.yml}`"
            Offense.new(
              file: protected_package.yml.to_s,
              message: message,
              violation_type: identifier,
              package: depended_on_package.original_package
            )
          end
        end

        all_offenses
      end

      private

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_any(per_file_violation)
        "#{message_for_fail_on_new(per_file_violation)} (`#{per_file_violation.constant_source_package}` set to `fail_on_any`)"
      end

      sig { params(per_file_violation: PerFileViolation).returns(String) }
      def message_for_fail_on_new(per_file_violation)
        "`#{per_file_violation.filepath}` references non-visible `#{per_file_violation.class_name}` from `#{per_file_violation.constant_source_package}`"
      end
    end
  end
end
