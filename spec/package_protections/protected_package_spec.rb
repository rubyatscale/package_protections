# frozen_string_literal: true

# typed: false

RSpec.describe PackageProtections::ProtectedPackage do
  let(:packages) do
    ParsePackwerk.all
  end

  describe 'unspecified protections' do
    it 'blows up if package has not specified behaviors explicitly for protections with non no-op default behavior' do
      write_file('package.yml', <<~YML.strip)
        enforce_dependencies: false
        enforce_privacy: false
      YML

      expect { PackageProtections::ProtectedPackage.from(packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }) }.to raise_error do |e|
        expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
        error_message = 'All protections must explicitly set unless their default behavior is `fail_never`. Missing protections: prevent_this_package_from_violating_its_stated_dependencies, prevent_other_packages_from_using_this_packages_internals, prevent_this_package_from_exposing_an_untyped_api, prevent_this_package_from_creating_other_namespaces'
        expect(e.message).to include error_message
      end
    end

    context 'empty metadata->protections' do
      it 'blows up if package has not specified behaviors explicitly for protections with non no-op default behavior in case of empty metadata->protections' do
        write_file('package.yml', <<~YML.strip)
          metadata:
            protections: {}
        YML

        expect { PackageProtections::ProtectedPackage.from(packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }) }.to raise_error do |e|
          expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
          error_message = 'All protections must explicitly set unless their default behavior is `fail_never`. Missing protections: prevent_this_package_from_violating_its_stated_dependencies, prevent_other_packages_from_using_this_packages_internals, prevent_this_package_from_exposing_an_untyped_api, prevent_this_package_from_creating_other_namespaces'
          expect(e.message).to include error_message
        end
      end
    end

    it 'blows up if metadata->protections contain unknown keys' do
      write_file('package.yml', <<~YML.strip)
        metadata:
          protections:
            someprotection: true
      YML

      expect {
        PackageProtections::ProtectedPackage.from(packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME })
      }.to raise_exception(PackageProtections::IncorrectPublicApiUsageError)
    end
  end

  describe '#violation_behavior_for' do
    it 'returns specified protections at the set level' do
      write_file('package.yml', <<~YML.strip)
        enforce_privacy: true
        metadata:
          protections:
            prevent_this_package_from_violating_its_stated_dependencies: fail_never
            prevent_other_packages_from_using_this_packages_internals: 'fail_on_any'
            prevent_this_package_from_exposing_an_untyped_api: fail_never
            prevent_this_package_from_creating_other_namespaces: fail_never
      YML

      protected_package = PackageProtections::ProtectedPackage.from(packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME })

      expect(protected_package.violation_behavior_for('prevent_this_package_from_violating_its_stated_dependencies')).to eq(
        PackageProtections::ViolationBehavior::FailNever
      )
      expect(protected_package.violation_behavior_for('prevent_other_packages_from_using_this_packages_internals')).to eq(
        PackageProtections::ViolationBehavior::FailOnAny
      )
    end
  end
end
