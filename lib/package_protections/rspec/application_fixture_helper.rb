# typed: true
# frozen_string_literal: true

require 'fileutils'

module ApplicationFixtureHelper
  def write_file(path, content = '')
    pathname = Pathname.new(path)
    FileUtils.mkdir_p(pathname.dirname)
    pathname.write(content)
    path
  end

  def write_package_yml(
    pack_name,
    dependencies: [],
    enforce_dependencies: true,
    enforce_privacy: true,
    protections: {},
    visible_to: []
  )
    defaults = {
      'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_new',
      'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new',
      'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_new',
      'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new',
      'prevent_other_packages_from_using_this_package_without_explicit_visibility' => 'fail_never',
      'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_never',
    }
    protections_with_defaults = defaults.merge(protections)
    metadata = { 'protections' => protections_with_defaults }
    if visible_to.any?
      metadata.merge!('visible_to' => visible_to)
    end

    package = ParsePackwerk::Package.new(
      name: pack_name,
      dependencies: dependencies,
      enforce_dependencies: enforce_dependencies,
      enforce_privacy: enforce_privacy,
      metadata: metadata
    )

    ParsePackwerk.write_package_yml!(package)
  end

  def delete_app_file(path)
    File.delete(path)
  end
end
