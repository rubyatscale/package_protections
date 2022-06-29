# frozen_string_literal: true

# typed: strict

module PackageProtections
  module Private
    class MultipleNamespacesProtection
      extend T::Sig

      include ProtectionInterface
      include RubocopProtectionInterface

      IDENTIFIER = 'prevent_this_package_from_creating_other_namespaces'

      sig { override.returns(String) }
      def identifier
        IDENTIFIER
      end

      sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
      def unmet_preconditions_for_behavior(behavior, package)
        if !behavior.enabled? && !package.metadata['global_namespaces'].nil?
          "Invalid configuration for package `#{package.name}`. `#{identifier}` must be turned on to use `global_namespaces` configuration."
        else
          # We don't need to validate if the behavior is currentely fail_never
          return if behavior.fail_never?

          # The reason for this is precondition is the `MultipleNamespacesProtection` assumes this to work properly.
          # To remove this precondition, we need to modify `MultipleNamespacesProtection` to be more generalized!
          if EXPECTED_PACK_DIRECTORIES.include?(Pathname.new(package.name).dirname.to_s) || package.name == ParsePackwerk::ROOT_PACKAGE_NAME
            nil
          else
            "Package #{package.name} must be located in one of #{EXPECTED_PACK_DIRECTORIES.join(', ')} (or be the root) to use this protection"
          end
        end
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
            include_paths << p.original_package.directory.join('app', '**', '*').to_s
            include_paths << p.original_package.directory.join('lib', '**', '*').to_s
          end
        end

        [
          CopConfig.new(
            name: cop_name,
            enabled: include_paths.any?,
            include_paths: include_paths
          )
        ]
      end

      sig do
        params(package: ProtectedPackage).returns(T::Hash[T.untyped, T.untyped])
      end
      def custom_cop_config(package)
        {
          'GlobalNamespaces' => package.metadata['global_namespaces']
        }
      end

      sig { override.returns(String) }
      def cop_name
        'PackageProtections/NamespacedUnderPackageName'
      end

      sig { override.returns(String) }
      def humanized_protection_name
        'Multiple Namespaces Violations'
      end

      sig { override.returns(String) }
      def humanized_protection_description
        <<~MESSAGE
          These files cannot have ANY modules/classes that are not submodules of the package's allowed namespaces.
          This is failing because these files are in `.rubocop_todo.yml` under `#{cop_name}`.
          If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
          change `#{IDENTIFIER}` to `#{ViolationBehavior::FailOnNew.serialize}`

          See https://go/packwerk_cheatsheet_namespaces for more info.
        MESSAGE
      end
    end
  end
end
