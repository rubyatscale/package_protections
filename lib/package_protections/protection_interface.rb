# frozen_string_literal: true

# typed: strict

module PackageProtections
  module ProtectionInterface
    extend T::Sig
    extend T::Helpers

    abstract!

    requires_ancestor { Kernel }

    sig do
      params(
        protected_packages: T::Array[ProtectedPackage],
        new_violations: T::Array[PerFileViolation]
      ).returns(T::Array[Offense])
    end
    def get_offenses(protected_packages, new_violations)
      [
        # First we get all offenses for new violations
        *get_offenses_for_new_violations(new_violations),
        # Then we separately look at TODO lists and add violations if there are no issues
        *get_offenses_for_existing_violations(protected_packages)
      ].sort_by(&:message)
    end

    sig { abstract.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
    def unmet_preconditions_for_behavior(behavior, package); end

    sig { params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T::Boolean) }
    def supports_violation_behavior?(behavior, package)
      unmet_preconditions_for_behavior(behavior, package).nil?
    end

    sig { returns(ViolationBehavior) }
    def default_behavior
      # The default behavior here is that we simply return the `fail_on_new` protection.
      # In some cases, this protection may not actually be supported. For example, `OutgoingPrivacyProtection` raises if the user has `enforce_privacy: false`
      # Error messages should provide enough clarity to either:
      # A) Know which protection to explicitly set to fail_never
      # B) Know how to change conditions to allow protection to be supported (i.e. set enforce dependencies to be true)
      ViolationBehavior::FailOnNew
    end

    sig do
      abstract.params(
        new_violations: T::Array[PerFileViolation]
      ).returns(T::Array[Offense])
    end
    def get_offenses_for_new_violations(new_violations); end

    sig do
      abstract.params(
        protected_packages: T::Array[ProtectedPackage]
      ).returns(T::Array[Offense])
    end
    def get_offenses_for_existing_violations(protected_packages); end

    sig { abstract.returns(String) }
    def identifier; end

    sig { abstract.returns(String) }
    def humanized_protection_name; end

    sig { abstract.returns(String) }
    def humanized_protection_description; end
  end
end
