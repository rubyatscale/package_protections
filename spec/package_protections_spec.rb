# typed: false

require 'open3'

describe PackageProtections do
  before do
    # Run rspec with DEBUG=1 to print out messages
    unless ENV['DEBUG']
      allow(PackageProtections.const_get(:Private)::Output).to receive(:p)
    end

    PackageProtections.bust_cache!
    allow(Bundler).to receive(:root).and_return(Pathname.new('.'))

    RuboCop::Packs.configure do |config|
      config.globally_permitted_namespaces = globally_permitted_namespaces
    end
  end

  let(:globally_permitted_namespaces) { [] }

  def get_packages
    ParsePackwerk.bust_cache!
    ParsePackwerk.all
  end

  def get_new_violations
    get_packages.flat_map do |package|
      PackageProtections::ProtectedPackage.from(package).violations.flat_map do |violation|
        PackageProtections::PerFileViolation.from(violation, package)
      end
    end
  end

  describe 'get_offenses' do
    describe 'general behavior' do
      it 'raises on incorrect protection configuration keys' do
        write_package_yml(ParsePackwerk::ROOT_PACKAGE_NAME, protections: {
                            'some_misconfigured_key' => true,
                            'prevent_other_packages_from_using_this_packages_internalsTYPOTYPO!!' => 'something'
                          })

        expect(PackageProtections.validate!).to eq(['Invalid configuration for package `.`. The metadata keys ["some_misconfigured_key", "prevent_other_packages_from_using_this_packages_internalsTYPOTYPO!!"] are not a valid behavior under the `protection` metadata namespace. Valid keys are ["prevent_this_package_from_violating_its_stated_dependencies", "prevent_other_packages_from_using_this_packages_internals", "prevent_this_package_from_exposing_an_untyped_api", "prevent_this_package_from_creating_other_namespaces", "prevent_this_package_from_exposing_instance_method_public_apis", "prevent_this_package_from_exposing_undocumented_public_apis"]. See https://github.com/rubyatscale/package_protections#readme for more info'])
      end

      it 'raises on incorrect protection configuration values' do
        write_package_yml(ParsePackwerk::ROOT_PACKAGE_NAME, protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_anyTYPO' })

        expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error do |e|
          expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
          error_message = 'The metadata value fail_on_anyTYPO is not a valid behavior. Double check your spelling'
          expect(e.message).to include error_message
        end
      end

      it 'has no offenses when all protections are met' do
        offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
        expect(offenses).to contain_exactly(0).offenses
      end

      it 'has offenses when not all protections are met' do
        write_package_yml('packs/apples', protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any' })
        write_package_yml('packs/trees')

        write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
          ---
          "packs/trees":
            "Trees::Tree":
              violations:
              - dependency
              files:
              - packs/apples/models/apples/apple.rb
        YML

        offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
        expect(offenses).to contain_exactly(1).offense
        file = 'packs/apples/models/apples/apple.rb'
        message = '`packs/apples/models/apples/apple.rb` depends on `Trees::Tree` from `packs/trees` (`packs/apples` set to `fail_on_any`)'
        expect(offenses).to include_offense offense(
          'packs/apples', message, file, 'prevent_this_package_from_violating_its_stated_dependencies'
        )
      end

      it 'respects the configured protections' do
        PackageProtections.configure do |config|
          config.protections = []
        end

        write_package_yml('packs/trees')
        expect(PackageProtections.validate!).to eq ['Invalid configuration for package `packs/trees`. The metadata keys ["prevent_this_package_from_violating_its_stated_dependencies", "prevent_other_packages_from_using_this_packages_internals", "prevent_this_package_from_exposing_an_untyped_api", "prevent_this_package_from_creating_other_namespaces", "prevent_this_package_from_exposing_instance_method_public_apis"] are not a valid behavior under the `protection` metadata namespace. Valid keys are []. See https://github.com/rubyatscale/package_protections#readme for more info']
      end
    end

    describe 'the protections' do
      describe 'prevent_this_package_from_violating_its_stated_dependencies' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Dependency Violations'
          actual_message = PackageProtections.with_identifier('prevent_this_package_from_violating_its_stated_dependencies').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            To resolve these violations, should you add a dependency in the client's `package.yml`?
            Is the code referencing the constant, and the referenced constant, in the right packages?
            See https://go/packwerk_cheatsheet_dependency for more info.
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_this_package_from_violating_its_stated_dependencies').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          it 'succeeds even if a violation occurs' do
            write_package_yml('packs/apples',
              enforce_dependencies: false,
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_never' })
            write_package_yml('packs/trees')

            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - dependency
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end

        context 'set to fail_on_new' do
          let(:apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_new) do
            write_package_yml('packs/apples',
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_new' })
          end

          it 'has a validation error on missing "enforce_dependencies: true" precondition' do
            write_package_yml('packs/apples',
              enforce_dependencies: false,
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any' })

            expect(PackageProtections.validate!).to eq ['prevent_this_package_from_violating_its_stated_dependencies protection does not have the valid preconditions in packs/apples. Package packs/apples must have `enforce_dependencies: true` to use this protection. See https://github.com/rubyatscale/package_protections#readme for more info']
          end

          it 'fails when this package newly depends on another package implicitly from a new file' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_new
            write_package_yml('packs/trees')
            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - dependency
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: get_new_violations)
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/models/apples/apple.rb` depends on `Trees::Tree` from `packs/trees`',
              'packs/apples/models/apples/apple.rb',
              'prevent_this_package_from_violating_its_stated_dependencies'
            )
          end

          it 'succeeds if there is no new implict usage' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_new
            write_package_yml('packs/trees')
            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - dependency
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end

        context 'set to fail_on_any' do
          let(:apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_any) do
            write_package_yml('packs/apples',
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any' })
          end

          it 'blows up on missing "enforce_dependencies: true" precondition' do
            write_package_yml('packs/apples',
              enforce_dependencies: false,
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any' })

            expect(PackageProtections.validate!).to eq ['prevent_this_package_from_violating_its_stated_dependencies protection does not have the valid preconditions in packs/apples. Package packs/apples must have `enforce_dependencies: true` to use this protection. See https://github.com/rubyatscale/package_protections#readme for more info']
          end

          it 'fails when this package depends on another package implicitly' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_any
            write_package_yml('packs/trees')
            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - dependency
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/models/apples/apple.rb` depends on `Trees::Tree` from `packs/trees` (`packs/apples` set to `fail_on_any`)', 'packs/apples/models/apples/apple.rb', 'prevent_this_package_from_violating_its_stated_dependencies'
            )
          end

          it 'fails when this package NEWLY depends on another package implicitly' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_any
            write_package_yml('packs/trees')
            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - dependency
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            violations = get_new_violations
            delete_app_file('packs/apples/deprecated_references.yml')

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/models/apples/apple.rb` depends on `Trees::Tree` from `packs/trees` (`packs/apples` set to `fail_on_any`)', 'packs/apples/models/apples/apple.rb', 'prevent_this_package_from_violating_its_stated_dependencies'
            )
          end

          it 'succeeds when this package has no implicit dependencies' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_any
            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end

          it 'succeeds when this package uses private API of another pack' do
            apples_package_yml_with_outgoing_dependency_protection_set_to_fail_on_any
            write_package_yml('packs/trees')
            write_file('packs/apples/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - privacy
                  files:
                  - packs/apples/models/apples/apple.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end
        end
      end

      describe 'prevent_other_packages_from_using_this_packages_internals' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Privacy Violations'
          actual_message = PackageProtections.with_identifier('prevent_other_packages_from_using_this_packages_internals').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            To resolve these violations, check the `public/` folder in each pack for public constants and APIs.
            If you need help or can't find what you need to meet your use case, reach out to the owning team.
            See https://go/packwerk_cheatsheet_privacy for more info.
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_other_packages_from_using_this_packages_internals').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          it 'succeeds even if a violation occurs' do
            write_package_yml('packs/apples', enforce_privacy: false, protections: { 'prevent_other_packages_from_using_this_packages_internals' => 'fail_never' })
            write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/apples":
                "Apples::Apple":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end

        context 'set to fail_on_new' do
          let(:apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_new) do
            write_package_yml('packs/apples',
              protections: { 'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new' })
          end

          it 'fails when some package newly depends on the protected package implicitly' do
            apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_new
            write_package_yml('packs/trees')

            write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/apples":
                "Apples::Apple":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            new_violations = get_new_violations
            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: new_violations)
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/trees/models/trees/tree.rb` references private `Apples::Apple` from `packs/apples`', 'packs/trees/models/trees/tree.rb', 'prevent_other_packages_from_using_this_packages_internals'
            )
          end

          context 'violation is on root package' do
            it 'fails when some package newly depends on the protected package implicitly' do
              write_package_yml(ParsePackwerk::ROOT_PACKAGE_NAME,
                protections: { 'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new' })

              write_package_yml('packs/trees')

              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                ".":
                  "Apples::Apple":
                    violations:
                    - privacy
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              new_violations = get_new_violations
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: new_violations)
              expect(offenses).to contain_exactly(1).offense
              expect(offenses).to include_offense offense(
                ParsePackwerk::ROOT_PACKAGE_NAME,
                '`packs/trees/models/trees/tree.rb` references private `Apples::Apple` from `.`', 'packs/trees/models/trees/tree.rb', 'prevent_other_packages_from_using_this_packages_internals'
              )
            end
          end

          it 'succeeds if there is no new implict usage' do
            apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_new

            write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/apples":
                "Apples::Apple":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end

        context 'set to fail_on_any' do
          let(:apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_any) do
            write_package_yml('packs/apples',
              protections: { 'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_any' })
          end

          it 'fails when some package depends on the package internals' do
            apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_any
            write_package_yml('packs/trees')
            write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/apples":
                "Apples::Apple":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/trees/models/trees/tree.rb` references private `Apples::Apple` from `packs/apples` (`packs/apples` set to `fail_on_any`)', 'packs/trees/models/trees/tree.rb', 'prevent_other_packages_from_using_this_packages_internals'
            )
          end

          it 'fails when some package newly depends on the protected package implicitly' do
            apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_any
            write_package_yml('packs/trees')

            write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
              ---
              "packs/apples":
                "Apples::Apple":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            violations = get_new_violations
            delete_app_file('packs/trees/deprecated_references.yml')

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/trees/models/trees/tree.rb` references private `Apples::Apple` from `packs/apples` (`packs/apples` set to `fail_on_any`)',
              'packs/trees/models/trees/tree.rb',
              'prevent_other_packages_from_using_this_packages_internals'
            )
          end

          it 'succeeds when privacy violations in the app are not on on the protected package' do
            apples_package_yml_with_incoming_privacy_protection_set_to_fail_on_any
            write_package_yml('packs/trees',
              enforce_privacy: false,
              protections: { 'prevent_other_packages_from_using_this_packages_internals' => 'fail_never' })

            write_package_yml(ParsePackwerk::ROOT_PACKAGE_NAME)

            write_file('deprecated_references.yml', <<~YML.strip)
              ---
              "packs/trees":
                "Trees::Tree":
                  violations:
                  - privacy
                  files:
                  - packs/trees/models/trees/tree.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: get_new_violations)
            expect(offenses).to contain_exactly(0).offenses
          end
        end
      end

      describe 'prevent_this_package_from_exposing_an_untyped_api' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Typed API Violations'
          actual_message = PackageProtections.with_identifier('prevent_this_package_from_exposing_an_untyped_api').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            These files cannot have ANY Ruby files in the public API that are not typed strict or higher.
            This is failing because these files are in `.rubocop_todo.yml` under `PackageProtections/TypedPublicApi`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `prevent_this_package_from_exposing_an_untyped_api` to `fail_on_new`

            See https://go/packwerk_cheatsheet_typed_api for more info.
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_this_package_from_exposing_an_untyped_api').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          let(:apples_package_yml_with_typed_api_protection_set_to_fail_never) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_exposing_an_untyped_api' => 'fail_never' })
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_typed_api_protection_set_to_fail_never
            cop_config = get_resulting_rubocop['PackageProtections/TypedPublicApi']
            expect(cop_config).to eq({ 'Enabled' => false })
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_typed_api_protection_set_to_fail_never

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to be_empty
          end

          it 'succeeds even if there is a public API file in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_never

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/TypedPublicApi:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end
        end

        context 'set to fail_on_new' do
          let(:apples_package_yml_with_typed_api_protection_set_to_fail_on_new) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_new' })
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_new
            cop_config = get_resulting_rubocop['PackageProtections/TypedPublicApi']
            expect(cop_config['Exclude']).to eq(nil)
            expect(cop_config['Include']).to eq(['packs/apples/app/public/**/*'])
            expect(cop_config['Enabled']).to eq(true)
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_new

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to be_empty
          end
        end

        context 'set to fail_on_any' do
          let(:apples_package_yml_with_typed_api_protection_set_to_fail_on_any) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_any' })
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any
            cop_config = get_resulting_rubocop['PackageProtections/TypedPublicApi']
            expect(cop_config['Exclude']).to eq(nil)
            expect(cop_config['Include']).to eq(['packs/apples/app/public/**/*'])
            expect(cop_config['Enabled']).to eq(true)
          end

          it 'succeeds if there are no entries for public API files in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any
            write_file('packs/apples/app/public/tool.rb', '')

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end

          it 'succeeds when there are files from private implementation in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any
            write_file('packs/apples/app/services/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/TypedPublicApi:
                Exclude:
                  - packs/apples/app/services/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end

          it 'fails if there is a public API file in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/TypedPublicApi:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              'packs/apples/app/public/tool.rb should be `typed: strict`', 'packs/apples/app/public/tool.rb', 'prevent_this_package_from_exposing_an_untyped_api'
            )
          end

          it 'succeeds if there is a different pack\'s public API file in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/TypedPublicApi:
                Exclude:
                  - packs/other_pack/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end

          context 'when the pack with the protection is the root pack' do
            it 'succeeds if there is a different pack\'s public API file in the rubocop TODO list' do
              write_package_yml('.', protections: { 'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_any' })

              write_file('app/public/tool.rb', '')
              write_file('packs/other_pack/app/public/tool.rb', '')
              write_file('.rubocop_todo.yml', <<~YML.strip)
                PackageProtections/TypedPublicApi:
                  Exclude:
                    - packs/other_pack/app/public/tool.rb
              YML

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(0).offenses
            end
          end
        end
      end

      describe 'prevent_this_package_from_creating_other_namespaces' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Multiple Namespaces Violations'
          actual_message = PackageProtections.with_identifier('prevent_this_package_from_creating_other_namespaces').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            These files cannot have ANY modules/classes that are not submodules of the package's allowed namespaces.
            This is failing because these files are in `.rubocop_todo.yml` under `PackageProtections/NamespacedUnderPackageName`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `prevent_this_package_from_creating_other_namespaces` to `fail_on_new`

            See https://go/packwerk_cheatsheet_namespaces for more info.
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_this_package_from_creating_other_namespaces').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          let(:globally_permitted_namespaces) { [] }

          let(:apples_package_yml_with_namespace_protection_set_to_fail_never) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_never' })
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_namespace_protection_set_to_fail_never
            cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
            expect(cop_config).to eq({ 'Enabled' => false })
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_namespace_protection_set_to_fail_never

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to be_empty
          end

          it 'succeeds even if any of this pack\'s files are in the rubocop TODO' do
            apples_package_yml_with_namespace_protection_set_to_fail_never

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/NamespacedUnderPackageName:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end
        end

        context 'set to fail_on_new' do
          let(:globally_permitted_namespaces) { [] }

          let(:apples_package_yml_with_namespace_protection_set_to_fail_on_new) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new' })
          end

          context 'global_namespaces is unset' do
            let(:globally_permitted_namespaces) { [] }

            it 'generates the expected rubocop.yml entries' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
              expect(cop_config['Exclude']).to eq(nil)
              expect(cop_config['Include']).to eq(['packs/apples/app/**/*', 'packs/apples/lib/**/*'])
            end
          end

          context 'global_namespaces is set' do
            let(:globally_permitted_namespaces) { %w[AppleTrees Ciders Apples] }

            it 'generates the expected rubocop.yml entries' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
              expect(cop_config['Exclude']).to eq(nil)
              expect(cop_config['Include']).to eq(['packs/apples/app/**/*', 'packs/apples/lib/**/*'])
              expect(cop_config['Enabled']).to eq(true)
            end
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_new
            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to be_empty
          end

          context 'the package is nested' do
            let(:apples_package_yml_with_namespace_protection_set_to_fail_on_new) do
              write_package_yml('packs/apples/subpack', protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new' })
            end

            context 'global_namespaces is unset' do
              let(:globally_permitted_namespaces) { [] }

              it 'generates the expected rubocop.yml entries' do
                apples_package_yml_with_namespace_protection_set_to_fail_on_new
                cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
                expect(cop_config['Exclude']).to eq(nil)
                expect(cop_config['Enabled']).to eq(true)
                expect(cop_config['Include']).to eq(['packs/apples/subpack/app/**/*', 'packs/apples/subpack/lib/**/*'])
              end
            end

            context 'global_namespaces is set' do
              let(:globally_permitted_namespaces) { %w[AppleTrees Ciders Apples] }

              it 'generates the expected rubocop.yml entries' do
                apples_package_yml_with_namespace_protection_set_to_fail_on_new
                cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
                expect(cop_config['Exclude']).to eq(nil)
                expect(cop_config['Enabled']).to eq(true)
                expect(cop_config['Include']).to eq(['packs/apples/subpack/app/**/*', 'packs/apples/subpack/lib/**/*'])
              end
            end

            it 'is implemented by Rubocop' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to be_empty
            end
          end
        end

        context 'set to fail_on_any' do
          let(:apples_package_yml_with_namespace_protection_set_to_fail_on_any) do
            write_package_yml('packs/apples', protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_on_any' })
          end

          it 'fails if any of this pack\'s files are in the rubocop TODO' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/NamespacedUnderPackageName:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/app/public/tool.rb` should be namespaced under the package namespace', 'packs/apples/app/public/tool.rb', 'prevent_this_package_from_creating_other_namespaces'
            )
          end

          it 'fails if any of this pack\'s files are in a pack-level rubocop TODO' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('packs/apples/.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/NamespacedUnderPackageName:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/app/public/tool.rb` should be namespaced under the package namespace', 'packs/apples/app/public/tool.rb', 'prevent_this_package_from_creating_other_namespaces'
            )
          end

          it 'does not fail if a .rubocop_todo.yml is in the wrong format' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('packs/apples/.rubocop_todo.yml', ''.strip)

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end

          it 'succeeds if another pack\'s file is in the rubocop TODO' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_any

            write_file('packs/other_pack/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/NamespacedUnderPackageName:
                Exclude:
                  - packs/other_pack/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end

          it 'succeeds if no files are in the ruboop todo' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_any

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end
      end

      describe 'prevent_this_package_from_exposing_instance_method_public_apis' do
        let(:identifier) { 'prevent_this_package_from_exposing_instance_method_public_apis' }
        let(:cop_name) { 'PackageProtections/OnlyClassMethods' }

        it 'has a helpful humanized name' do
          expected_humanized_message = 'Class Method Public APIs'
          actual_message = PackageProtections.with_identifier(identifier).humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            Public API methods can only be static methods.
            This is failing because these files are in `.rubocop_todo.yml` under `PackageProtections/OnlyClassMethods`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `prevent_this_package_from_exposing_instance_method_public_apis` to `fail_on_new`
          MESSAGE

          actual_message = PackageProtections.with_identifier(identifier).humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          let(:apples_package_yml_with_api_documentation_protection_set_to_fail_never) do
            # TODO: Refactor Package Protections to not need to do this, see https://github.com/Gusto/zenpayroll/issues/141570
            write_package_yml(
              'packs/apples',
              protections: {
                'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_never'
              }
            )
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never
            cop_config = get_resulting_rubocop[cop_name]
            expect(cop_config).to eq({ 'Enabled' => false, 'AcceptableParentClasses' => [] })
          end

          context 'acceptable parent classes is configured' do
            it 'generates the expected rubocop.yml entries' do
              PackageProtections.configure do |config|
                config.acceptable_parent_classes = ['Blah']
              end
              apples_package_yml_with_api_documentation_protection_set_to_fail_never
              cop_config = get_resulting_rubocop[cop_name]
              expect(cop_config).to eq({ 'Enabled' => false, 'AcceptableParentClasses' => ['Blah'] })
            end
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to be_empty
          end

          it 'succeeds even if there is a public API file in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              #{cop_name}:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end
        end

        context 'set to fail_on_new' do
          let(:apples_package_yml_with_only_class_methods_set_to_fail_on_new) do
            # TODO: Refactor Package Protections to not need to do this, see https://github.com/Gusto/zenpayroll/issues/141570
            write_package_yml(
              'packs/apples',
              protections: {
                'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_on_new'
              }
            )
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_only_class_methods_set_to_fail_on_new

            cop_config = get_resulting_rubocop[cop_name]
            expect(cop_config['Exclude']).to eq(nil)
            expect(cop_config['Include']).to eq(['packs/apples/app/public/**/*'])
            expect(cop_config['Enabled']).to eq(true)
          end

          context 'package has non-static methods' do
            it 'ensures no new violations are added' do
              apples_package_yml_with_only_class_methods_set_to_fail_on_new

              # Test the file
              offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
              expect(offenses).to be_empty
            end
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_only_class_methods_set_to_fail_on_new
            write_file('packs/apples/README.md')
            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to be_empty
          end
        end
      end

      describe 'prevent_this_package_from_exposing_undocumented_public_apis' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Documented Public APIs'
          actual_message = PackageProtections.with_identifier('prevent_this_package_from_exposing_undocumented_public_apis').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            All public API must have a documentation comment (between the signature and method).
            This is failing because these files are in `.rubocop_todo.yml` under `PackageProtections/RequireDocumentedPublicApis`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `prevent_this_package_from_exposing_undocumented_public_apis` to `fail_on_new`
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_this_package_from_exposing_undocumented_public_apis').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          let(:apples_package_yml_with_api_documentation_protection_set_to_fail_never) do
            # TODO: Refactor Package Protections to not need to do this, see https://github.com/Gusto/zenpayroll/issues/141570
            write_package_yml(
              'packs/apples',
              protections: {
                'prevent_this_package_from_exposing_undocumented_public_apis' => 'fail_never',
                'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_never'
              }
            )
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never
            cop_config = get_resulting_rubocop['PackageProtections/RequireDocumentedPublicApis']
            expect(cop_config).to eq({ 'Enabled' => false })
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to be_empty
          end

          it 'succeeds even if there is a public API file in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_never

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/RequireDocumentedPublicApi:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end
        end

        context 'set to fail_on_new' do
          let(:apples_package_yml_with_api_documentation_protection_set_to_fail_on_new) do
            # TODO: Refactor Package Protections to not need to do this, see https://github.com/Gusto/zenpayroll/issues/141570
            write_package_yml(
              'packs/apples',
              protections: {
                'prevent_this_package_from_exposing_undocumented_public_apis' => 'fail_on_new',
                'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_never'
              }
            )
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_new
            write_file('packs/apples/README.md')
            cop_config = get_resulting_rubocop['PackageProtections/RequireDocumentedPublicApis']
            expect(cop_config['Exclude']).to eq(nil)
            expect(cop_config['Include']).to eq(['packs/apples/app/public/**/*'])
            expect(cop_config['Enabled']).to eq(true)
          end

          context 'package has no README.md' do
            it 'has a validation error' do
              apples_package_yml_with_api_documentation_protection_set_to_fail_on_new
              expect(PackageProtections.validate!).to eq(['prevent_this_package_from_exposing_undocumented_public_apis protection does not have the valid preconditions in packs/apples. This package must have a readme at packs/apples/README.md to use this protection. See https://github.com/rubyatscale/package_protections#readme for more info'])
            end
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_new
            write_file('packs/apples/README.md')
            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to be_empty
          end
        end

        context 'set to fail_on_any' do
          let(:apples_package_yml_with_api_documentation_protection_set_to_fail_on_any) do
            # TODO: Refactor Package Protections to not need to do this, see https://github.com/Gusto/zenpayroll/issues/141570
            write_package_yml(
              'packs/apples',
              protections: {
                'prevent_this_package_from_exposing_undocumented_public_apis' => 'fail_on_any',
                'prevent_this_package_from_exposing_instance_method_public_apis' => 'fail_never'
              }
            )
          end

          it 'generates the expected rubocop.yml entries' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_any
            write_file('packs/apples/README.md')
            cop_config = get_resulting_rubocop['PackageProtections/RequireDocumentedPublicApis']
            expect(cop_config['Exclude']).to eq(nil)
            expect(cop_config['Include']).to eq(['packs/apples/app/public/**/*'])
            expect(cop_config['Enabled']).to eq(true)
          end

          it 'succeeds if there are no entries for public API files in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_any
            write_file('packs/apples/app/public/tool.rb', '')
            write_file('packs/apples/README.md')
            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end

          it 'succeeds when there are files from private implementation in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_any
            write_file('packs/apples/README.md')
            write_file('packs/apples/app/services/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/RequireDocumentedPublicApi:
                Exclude:
                  - packs/apples/app/services/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(0).offense
          end

          it 'fails if there is a public API file in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_any
            write_file('packs/apples/README.md')
            write_file('packs/apples/app/public/tool.rb', '')

            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/RequireDocumentedPublicApis:
                Exclude:
                  - packs/apples/app/public/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(1).offense
            expect(offenses).to include_offense offense(
              'packs/apples',
              '`packs/apples/app/public/tool.rb` must contain documentation on every method (between signature and method)', 'packs/apples/app/public/tool.rb', 'prevent_this_package_from_exposing_undocumented_public_apis'
            )
          end

          it 'succeeds if there is a different pack\'s public API file in the rubocop TODO list' do
            apples_package_yml_with_api_documentation_protection_set_to_fail_on_any

            write_file('packs/apples/app/public/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/RequireDocumentedPublicApi:
                Exclude:
                  - packs/other_pack/app/public/tool.rb
            YML

            write_file('packs/apples/README.md')

            offenses = PackageProtections.get_offenses(packages: ParsePackwerk.all, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
          end
        end
      end
    end
  end

  describe 'set_defaults!' do
    it 'sets all not opted-out, not-explicitly-set-protections to their default explicitly' do
      write_file('package.yml', <<~YML.strip)
        enforce_dependencies: true
        enforce_privacy: true
        metadata:
          protections: {}
      YML

      PackageProtections.set_defaults!(get_packages)

      root_package = get_packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }

      expect(root_package.metadata['protections']).to eq({
                                                           'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new',
                                                           'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new',
                                                           'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_new',
                                                           'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_new'
                                                         })
    end

    context 'protection key is unset' do
      it 'sets all not opted-out, not-explicitly-set-protections to their default explicitly' do
        write_file('package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        PackageProtections.set_defaults!(get_packages)

        root_package = get_packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }

        expect(root_package.metadata['protections']).to eq({
                                                             'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new',
                                                             'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new',
                                                             'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_new',
                                                             'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_new'
                                                           })
      end
    end

    it 'does not set opted out protections and preserves their default value' do
      write_file('package.yml', <<~YML.strip)
        enforce_dependencies: true
        enforce_privacy: true
        metadata:
          protections: {}
      YML

      PackageProtections.set_defaults!(get_packages)
      root_package = get_packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }

      expect(root_package.metadata['protections'].keys).to_not include 'prevent_this_package_from_exposing_instance_method_public_apis'
      protected_package = PackageProtections::ProtectedPackage.from(root_package)
      expect(protected_package.violation_behavior_for('prevent_this_package_from_exposing_instance_method_public_apis')).to eq PackageProtections::ViolationBehavior::FailNever
    end

    it 'does not change an explicitly set protection' do
      write_file('package.yml', <<~YML.strip)
        enforce_dependencies: true
        enforce_privacy: true
        metadata:
          protections:
            prevent_this_package_from_violating_its_stated_dependencies: fail_on_any
            prevent_other_packages_from_using_this_packages_internals: fail_on_new
      YML

      PackageProtections.set_defaults!(get_packages)

      root_package = get_packages.find { |p| p.name == ParsePackwerk::ROOT_PACKAGE_NAME }

      expect(root_package.metadata['protections']).to eq({
                                                           'prevent_other_packages_from_using_this_packages_internals' => 'fail_on_new',
                                                           'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new',
                                                           'prevent_this_package_from_exposing_an_untyped_api' => 'fail_on_new',
                                                           'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any'
                                                         })
    end
  end

  describe 'configuration' do
    context 'app has a user defined configuration' do
      let(:globally_permitted_namespaces) { ['MyNamespace'] }

      it 'properly configures package protections' do
        expect(RuboCop::Packs.config.globally_permitted_namespaces).to eq(['MyNamespace'])
      end
    end
  end
end
