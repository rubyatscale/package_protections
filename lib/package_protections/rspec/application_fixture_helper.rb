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
    global_namespaces: [],
    visible_to: []
  )
    defaults = PackageProtections
      .all
      .to_h { |p| [p.identifier, p.default_behavior.serialize] }

    protections_with_defaults = defaults.merge(protections)
    metadata = { 'protections' => protections_with_defaults }
    if visible_to.any?
      metadata.merge!('visible_to' => visible_to)
    end

    if global_namespaces.any?
      metadata.merge!('global_namespaces' => global_namespaces)
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
