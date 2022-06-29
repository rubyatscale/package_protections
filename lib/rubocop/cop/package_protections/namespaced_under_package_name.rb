# typed: false

# For String#camelize
require 'active_support/core_ext/string/inflections'

module RuboCop
  module Cop
    module PackageProtections
      class NamespacedUnderPackageName < Base
        include RangeHelp

        def on_new_investigation
          absolute_filepath = Pathname.new(processed_source.file_path)
          relative_filepath = absolute_filepath.relative_path_from(Pathname.pwd)
          relative_filename = relative_filepath.to_s

          # This cop only works for files in `app`
          return if !relative_filename.include?('app/')

          match = relative_filename.match(%r{((#{::PackageProtections::EXPECTED_PACK_DIRECTORIES.join("|")})/.*?)/})
          package_name = match && match[1]

          return if package_name.nil?

          return if relative_filepath.extname != '.rb'

          # Zeitwerk establishes a standard convention by which namespaces are defined.
          # The package protections namespace checker is coupled to a specific assumption about how auto-loading works.
          #
          # Namely, we expect the following autoload paths: `packs/**/app/**/`
          # Examples:
          # 1) `packs/package_1/app/public/package_1/my_constant.rb` produces constant `Package1::MyConstant`
          # 2) `packs/package_1/app/services/package_1/my_service.rb` produces constant `Package1::MyService`
          # 3) `packs/package_1/app/services/package_1.rb` produces constant `Package1`
          # 4) `packs/package_1/app/public/package_1.rb` produces constant `Package1`
          #
          # Described another way, we expect any part of the directory labeled NAMESPACE to establish a portion of the fully qualified runtime constant:
          # `packs/**/app/**/NAMESPACE1/NAMESPACE2/[etc]`
          #
          # Therefore, for our implementation, we substitute out the non-namespace producing portions of the filename to count the number of namespaces.
          # Note this will *not work* properly in applications that have different assumptions about autoloading.
          package_last_name = package_name.split('/').last
          path_without_package_base = relative_filename.gsub(%r{#{package_name}/app/}, '')
          if path_without_package_base.include?('concerns')
            autoload_folder_name = path_without_package_base.split('/').first(2).join('/')
          else
            autoload_folder_name = path_without_package_base.split('/').first
          end

          remaining_file_path = path_without_package_base.gsub(%r{\A#{autoload_folder_name}/}, '')
          actual_namespace = get_actual_namespace(remaining_file_path, relative_filepath, package_name)
          allowed_namespaces = get_allowed_namespaces(package_name)
          if allowed_namespaces.include?(actual_namespace)
            # No problem!
          elsif allowed_namespaces.count == 1
            single_allowed_namespace = allowed_namespaces.first
            if relative_filepath.to_s.include?('app/')
              app_or_lib = 'app'
            elsif relative_filepath.to_s.include?('lib/')
              app_or_lib = 'lib'
            end

            absolute_desired_path = root_pathname.join(package_name, app_or_lib, T.must(autoload_folder_name), single_allowed_namespace.underscore, remaining_file_path)

            relative_desired_path = absolute_desired_path.relative_path_from(root_pathname)

            add_offense(
              source_range(processed_source.buffer, 1, 0),
              message: format(
                '`%<package_name>s` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `%<expected_namespace>s` with path `%<expected_path>s`. See https://go/packwerk_cheatsheet_namespaces for more info.',
                package_name: package_name,
                expected_namespace: package_last_name.camelize,
                expected_path: relative_desired_path
              )
            )
          else
            add_offense(
              source_range(processed_source.buffer, 1, 0),
              message: format(
                '`%<package_name>s` prevents modules/classes that are not submodules of one of the allowed namespaces in `%<package_yml>s`. See https://go/packwerk_cheatsheet_namespaces for more info.',
                package_name: package_name,
                package_yml: "#{package_name}/package.yml"
              )
            )
          end
        end

        private

        def get_allowed_namespaces(package_name)
          cop_config = ::PackageProtections.private_cop_config('prevent_this_package_from_creating_other_namespaces')
          allowed_global_namespaces = cop_config[package_name]['GlobalNamespaces'] || [package_name.split('/').last.camelize]
          Set.new(allowed_global_namespaces)
        end

        def get_actual_namespace(remaining_file_path, relative_filepath, package_name)
          # If the remaining file path is a ruby file (not a directory), then it establishes a global namespace
          # Otherwise, per Zeitwerk's conventions as listed above, its a directory that establishes another global namespace
          remaining_file_path.split('/').first.gsub('.rb', '').camelize
        end

        def root_pathname
          Pathname.pwd
        end
      end
    end
  end
end
