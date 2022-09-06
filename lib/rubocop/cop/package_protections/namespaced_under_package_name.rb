# typed: strict

# For String#camelize
require 'active_support/core_ext/string/inflections'
require 'rubocop/cop/package_protections/namespaced_under_package_name/desired_zeitwerk_api'

module RuboCop
  module Cop
    module PackageProtections
      #
      # TODO:
      # This class is in serious need of being split up into helpful abstractions.
      # A really helpful abstraction would be one that takes a file path and can spit out information about
      # namespacing, such as the exposed namespace, the file path for a different namespace, and more.
      #
      class NamespacedUnderPackageName < Base
        extend T::Sig

        include RangeHelp
        include ::PackageProtections::RubocopProtectionInterface

        sig { void }
        def on_new_investigation
          absolute_filepath = Pathname.new(processed_source.file_path)
          relative_filepath = absolute_filepath.relative_path_from(Pathname.pwd)
          relative_filename = relative_filepath.to_s

          # This cop only works for files ruby files in `app`
          return if !relative_filename.include?('app/') || relative_filepath.extname != '.rb'

          relative_filename = relative_filepath.to_s
          package_for_path = ParsePackwerk.package_from_path(relative_filename)
          return if package_for_path.nil?

          namespace_context = self.class.desired_zeitwerk_api.for_file(relative_filename, package_for_path)
          return if namespace_context.nil?

          allowed_global_namespaces = Set.new([
                                                namespace_context.expected_namespace,
                                                *::PackageProtections.config.globally_permitted_namespaces
                                              ])

          package_name = package_for_path.name
          actual_namespace = namespace_context.current_namespace

          if allowed_global_namespaces.include?(actual_namespace)
            # No problem!
          else
            package_enforces_namespaces = !::PackageProtections::ProtectedPackage.from(package_for_path).violation_behavior_for(NamespacedUnderPackageName::IDENTIFIER).fail_never?
            expected_namespace = namespace_context.expected_namespace
            relative_desired_path = namespace_context.expected_filepath
            pack_owning_this_namespace = self.class.namespaces_to_packs[actual_namespace]

            if package_enforces_namespaces
              add_offense(
                source_range(processed_source.buffer, 1, 0),
                message: format(
                  '`%<package_name>s` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `%<expected_namespace>s` with path `%<expected_path>s`. See https://go/packwerk_cheatsheet_namespaces for more info.',
                  package_name: package_name,
                  expected_namespace: expected_namespace,
                  expected_path: relative_desired_path
                )
              )
            elsif pack_owning_this_namespace
              add_offense(
                source_range(processed_source.buffer, 1, 0),
                message: format(
                  '`%<pack_owning_this_namespace>s` prevents other packs from sitting in the `%<actual_namespace>s` namespace. This should be namespaced under `%<expected_namespace>s` with path `%<expected_path>s`. See https://go/packwerk_cheatsheet_namespaces for more info.',
                  package_name: package_name,
                  pack_owning_this_namespace: pack_owning_this_namespace,
                  expected_namespace: expected_namespace,
                  actual_namespace: actual_namespace,
                  expected_path: relative_desired_path
                )
              )
            end
          end
        end

        # We override `cop_configs` for this protection.
        # The default behavior disables cops when a package has turned off a protection.
        # However: namespace violations can occur even when one package has TURNED OFF their namespace protection
        # but another package has it turned on. Therefore, all packages must always be opted in no matter what.
        #
        sig do
          params(packages: T::Array[::PackageProtections::ProtectedPackage])
          .returns(T::Array[::PackageProtections::RubocopProtectionInterface::CopConfig])
        end
        def cop_configs(packages)
          include_paths = T.let([], T::Array[String])
          packages.each do |p|
            included_globs_for_pack.each do |glob|
              include_paths << p.original_package.directory.join(glob).to_s
            end
          end

          [
            ::PackageProtections::RubocopProtectionInterface::CopConfig.new(
              name: cop_name,
              enabled: include_paths.any?,
              include_paths: include_paths
            )
          ]
        end

        IDENTIFIER = T.let('prevent_this_package_from_creating_other_namespaces'.freeze, String)

        sig { override.returns(String) }
        def identifier
          IDENTIFIER
        end

        sig { override.params(behavior: ::PackageProtections::ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
        def unmet_preconditions_for_behavior(behavior, package)
          if !behavior.enabled? && !package.metadata['global_namespaces'].nil?
            "Invalid configuration for package `#{package.name}`. `#{identifier}` must be turned on to use `global_namespaces` configuration."
          else
            # We don't need to validate if the behavior is currentely fail_never
            return if behavior.fail_never?

            # The reason for this is precondition is the `MultipleNamespacesProtection` assumes this to work properly.
            # To remove this precondition, we need to modify `MultipleNamespacesProtection` to be more generalized!
            is_root_package = package.name == ParsePackwerk::ROOT_PACKAGE_NAME
            in_allowed_directory = ::PackageProtections::EXPECTED_PACK_DIRECTORIES.any? do |expected_package_directory|
              package.directory.to_s.start_with?(expected_package_directory)
            end
            if in_allowed_directory || is_root_package
              nil
            else
              "Package #{package.name} must be located in one of #{::PackageProtections::EXPECTED_PACK_DIRECTORIES.join(', ')} (or be the root) to use this protection"
            end
          end
        end

        sig { override.returns(T::Array[String]) }
        def included_globs_for_pack
          [
            'app/**/*',
            'lib/**/*'
          ]
        end

        sig do
          override.params(file: String).returns(String)
        end
        def message_for_fail_on_any(file)
          "`#{file}` should be namespaced under the package namespace"
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
            change `#{IDENTIFIER}` to `#{::PackageProtections::ViolationBehavior::FailOnNew.serialize}`

            See https://go/packwerk_cheatsheet_namespaces for more info.
          MESSAGE
        end

        sig { returns(DesiredZeitwerkApi) }
        def self.desired_zeitwerk_api
          # This is cached at the class level so we will cache more expensive operations
          # across rubocop requests.
          @desired_zeitwerk_api ||= T.let(nil, T.nilable(DesiredZeitwerkApi))
          @desired_zeitwerk_api ||= DesiredZeitwerkApi.new
        end

        sig { returns(T::Hash[String, String]) }
        def self.namespaces_to_packs
          @namespaces_to_packs = T.let(nil, T.nilable(T::Hash[String, String]))
          @namespaces_to_packs ||= begin
            all_packs_enforcing_namespaces = ParsePackwerk.all.reject do |p|
              ::PackageProtections::ProtectedPackage.from(p).violation_behavior_for(NamespacedUnderPackageName::IDENTIFIER).fail_never?
            end

            namespaces_to_packs = {}
            all_packs_enforcing_namespaces.each do |package|
              namespaces_to_packs[desired_zeitwerk_api.get_pack_based_namespace(package)] = package.name
            end

            namespaces_to_packs
          end
        end
      end
    end
  end
end
