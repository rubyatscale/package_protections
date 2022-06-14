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
  end

  RSpec::Matchers.define(:include_offense) do |expected_offense|
    match do |actual_offenses|
      @actual_offenses = actual_offenses
      @expected_offense = expected_offense
      if ENV['DEBUG']
        PackageProtections.print_offenses(actual_offenses)
      end
      @matching_offense = actual_offenses.find do |actual_offense|
        actual_offense.file == expected_offense.file &&
          actual_offense.message == expected_offense.message &&
          actual_offense.violation_type == expected_offense.violation_type &&
          actual_offense.package.name == expected_offense.package.name
      end
      !@matching_offense.nil?
    end

    description do
      "to have an offense with type `#{expected_offense.type}` tied to package `#{expected_offense.package_name}` with message `#{expected_offense.message}` and instances `#{expected_offense.submessages.join(', ')}`"
    end

    failure_message do
      <<~MSG
        Could not find offense! Here are the found offenses:
        #{serialize_offenses_diff(@actual_offenses, expected_offense).join("\n\n")}
      MSG
    end
  end

  RSpec::Matchers.define(:contain_exactly) do |number_of_offenses|
    match do |actual_offenses|
      @actual_offenses = actual_offenses || []
      @offenses = []
      @actual_offenses.select do |offense|
        @offenses << offense
      end
      @offenses.size == number_of_offenses
    end

    chain :offense, :number_of_offenses
    chain :offenses, :number_of_offenses

    description do
      'to contain offenses'
    end

    failure_message_when_negated do
      "Found the following offenses:\n#{@offenses.map { |r| "#{r.package_name}: #{r.message}" }}"
    end

    failure_message do
      if @offenses.empty?
        "Found #{@offenses.size} instead."
      else
        <<~MSG
          Found #{@offenses.size} instead.

          #{serialize_offenses(@offenses).join("\n")}
        MSG
      end
    end
  end

  def serialize_offenses_diff(actual_offenses, expected_offense)
    color_by_match = ->(actual, expected) { actual == expected ? Rainbow(actual).green : "#{Rainbow(actual).red} (expected: #{expected})" }

    actual_offenses.map do |offense|
      # We color each field red or green depending on if the attributes match our expected
      <<~SERIALIZED_OFFENSE
        File: #{color_by_match.call(offense.file, expected_offense.file)}
        Message: #{color_by_match.call(offense.message, expected_offense.message)}
        Violation Type: #{color_by_match.call(offense.violation_type, expected_offense.violation_type)}
        Package: #{color_by_match.call(offense.package.name, expected_offense.package.name)}
      SERIALIZED_OFFENSE
    end
  end

  def serialize_offenses(actual_offenses)
    actual_offenses.map do |offense|
      <<~SERIALIZED_OFFENSE
        File: #{offense.file}
        Message: #{offense.message}
        Violation Type: #{offense.violation_type}
        Package: #{offense.package.name}
      SERIALIZED_OFFENSE
    end
  end

  def get_packages
    ParsePackwerk.all
  end

  def get_new_violations
    get_packages.flat_map do |package|
      PackageProtections::ProtectedPackage.from(package).violations.flat_map do |violation|
        PackageProtections::PerFileViolation.from(violation, package)
      end
    end
  end

  def get_resulting_rubocop
    write_file('config/default.yml', <<~YML.strip)
      <%= PackageProtections.rubocop_yml %>
    YML
    YAML.safe_load(ERB.new(YAML.load_file('config/default.yml')).result(binding))
  end

  def offense(
    package_name, message, file, violation_type
  )
    package = get_packages.find { |p| p.name == package_name }
    PackageProtections::Offense.new(
      package: package,
      message: message,
      file: file,
      violation_type: violation_type
    )
  end

  describe 'get_offenses' do
    describe 'general behavior' do
      it 'raises on incorrect protection configuration keys' do
        write_package_yml(ParsePackwerk::ROOT_PACKAGE_NAME, protections: {
                            'some_misconfigured_key' => true,
                            'prevent_other_packages_from_using_this_packages_internalsTYPOTYPO!!' => 'something'
                          })

        expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error do |e|
          expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
          error_message = 'Invalid configuration for package `.`. The metadata keys ["some_misconfigured_key", "prevent_other_packages_from_using_this_packages_internalsTYPOTYPO!!"] are not valid behaviors under the `protection` metadata namespace. Valid keys are'
          expect(e.message).to include error_message
        end
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

        expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error(PackageProtections::IncorrectPublicApiUsageError) do |e|
          expect(e.message).to eq 'Invalid configuration for package `packs/trees`. The metadata keys ["prevent_this_package_from_violating_its_stated_dependencies", "prevent_other_packages_from_using_this_packages_internals", "prevent_this_package_from_exposing_an_untyped_api", "prevent_this_package_from_creating_other_namespaces", "prevent_other_packages_from_using_this_package_without_explicit_visibility"] are not valid behaviors under the `protection` metadata namespace. Valid keys are []. See https://github.com/bigrails/package_protections#readme for more info'
        end
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

          it 'blows up on missing "enforce_dependencies: true" precondition' do
            write_package_yml('packs/apples',
              enforce_dependencies: false,
              protections: { 'prevent_this_package_from_violating_its_stated_dependencies' => 'fail_on_any' })

            expect {
              PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            }.to raise_exception(PackageProtections::IncorrectPublicApiUsageError)
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

            expect {
              PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            }.to raise_exception(PackageProtections::IncorrectPublicApiUsageError)
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

          it 'succeeds even if there are files from private implementation in the rubocop TODO list' do
            apples_package_yml_with_typed_api_protection_set_to_fail_on_any
            write_file('packs/apples/app/services/tool.rb', '')
            write_file('.rubocop_todo.yml', <<~YML.strip)
              PackageProtections/TypedPublicApi:
                Exclude:
                  - packs/apples/app/services/tool.rb
            YML

            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to contain_exactly(0).offenses
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
          let(:apples_global_namespaces) { [] }

          let(:apples_package_yml_with_namespace_protection_set_to_fail_never) do
            write_package_yml('packs/apples', global_namespaces: apples_global_namespaces, protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_never' })
          end

          context 'global_namespaces to metadata is set but protection is fail_on_never' do
            let(:apples_global_namespaces) { ['AppleTrees'] }

            it 'blows up due to invalid precondition' do
              apples_package_yml_with_namespace_protection_set_to_fail_never
              expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error do |e|
                expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
                error_message = 'Invalid configuration for package `packs/apples`. `prevent_this_package_from_creating_other_namespaces` must be turned on to use `global_namespaces` configuration.'
                expect(e.message).to include error_message
              end
            end
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
          let(:apples_global_namespaces) { [] }

          let(:apples_package_yml_with_namespace_protection_set_to_fail_on_new) do
            write_package_yml('packs/apples', global_namespaces: apples_global_namespaces, protections: { 'prevent_this_package_from_creating_other_namespaces' => 'fail_on_new' })
          end

          context 'global_namespaces is unset' do
            let(:apples_global_namespaces) { [] }

            it 'generates the expected rubocop.yml entries' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
              expect(cop_config['Exclude']).to eq(nil)
              expect(cop_config['Include']).to eq(['packs/apples/app/**/*', 'packs/apples/lib/**/*'])
              expect(cop_config['Enabled']).to eq(true)
            end
          end

          context 'global_namespaces is set' do
            let(:apples_global_namespaces) { %w[AppleTrees Ciders Apples] }

            it 'generates the expected rubocop.yml entries' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              cop_config = get_resulting_rubocop['PackageProtections/NamespacedUnderPackageName']
              expect(cop_config['Exclude']).to eq(nil)
              expect(cop_config['Include']).to eq(['packs/apples/app/**/*', 'packs/apples/lib/**/*'])
              expect(cop_config['Enabled']).to eq(true)
            end

            it 'retrieves the right rubocop metadata' do
              apples_package_yml_with_namespace_protection_set_to_fail_on_new
              private_cop_config = PackageProtections.private_cop_config('prevent_this_package_from_creating_other_namespaces')
              expect(private_cop_config['packs/apples']).to eq({ 'GlobalNamespaces' => %w[AppleTrees Ciders Apples] })
            end
          end

          it 'is implemented by Rubocop' do
            apples_package_yml_with_namespace_protection_set_to_fail_on_new
            offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
            expect(offenses).to be_empty
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

      describe 'prevent_other_packages_from_using_this_package_without_explicit_visibility' do
        it 'has a helpful humanized name' do
          expected_humanized_message = 'Visibility Violations'
          actual_message = PackageProtections.with_identifier('prevent_other_packages_from_using_this_package_without_explicit_visibility').humanized_protection_name
          expect(actual_message).to eq expected_humanized_message
        end

        it 'has a helpful humanized description' do
          expected_humanized_message = <<~MESSAGE
            These files are using a constant from a package that restricts its usage through the `visible_to` flag in its `package.yml`
            To resolve these violations, work with the team who owns the package you are trying to use and to figure out the
            preferred public API for the behavior you want.

            See https://go/packwerk_cheatsheet_visibility for more info.
          MESSAGE

          actual_message = PackageProtections.with_identifier('prevent_other_packages_from_using_this_package_without_explicit_visibility').humanized_protection_description
          expect(actual_message).to eq expected_humanized_message
        end

        context 'set to fail_never' do
          before do
            write_package_yml('packs/apples',
              visible_to: apples_visible_to,
              protections: { 'prevent_other_packages_from_using_this_package_without_explicit_visibility' => 'fail_never' })
          end

          context 'visible to metadata is set but protection is fail_on_never' do
            let(:apples_visible_to) { ['packs/some_other_pack'] }

            it 'blows up due to invalid precondition' do
              expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error do |e|
                expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
                error_message = 'Invalid configuration for package `packs/apples`. `prevent_other_packages_from_using_this_package_without_explicit_visibility` must be turned on to use `visible_to` configuration.'
                expect(e.message).to include error_message
              end
            end
          end

          context 'package is newly using another package that does not permit anyone to use it' do
            let(:apples_visible_to) { [] }

            it 'has no offenses for this protection' do
              write_package_yml('packs/trees')
              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                "packs/apples":
                  "Apples::Apple":
                    violations:
                    - dependency
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              violations = get_new_violations
              delete_app_file('packs/trees/deprecated_references.yml')

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
              expect(offenses).to contain_exactly(1).offense
              # It only includes the dependency violation
              expect(offenses).to include_offense offense(
                'packs/trees',
                '`packs/trees/models/trees/tree.rb` depends on `Apples::Apple` from `packs/apples`',
                'packs/trees/models/trees/tree.rb',
                'prevent_this_package_from_violating_its_stated_dependencies'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit ANYONE to depend on it' do
            let(:apples_visible_to) { [] }

            it 'has no offenses' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(0).offenses
            end
          end
        end

        context 'set to fail on new' do
          before do
            write_package_yml('packs/apples',
              visible_to: apples_visible_to,
              protections: { 'prevent_other_packages_from_using_this_package_without_explicit_visibility' => 'fail_on_new' })
          end

          context 'enforce_dependencies is false' do
            let(:apples_visible_to) { [] }

            it 'blows up due to incorrect precondition' do
              write_package_yml('packs/apples',
                enforce_privacy: false,
                protections: { 'prevent_other_packages_from_using_this_package_without_explicit_visibility' => 'fail_on_new' })

              expect { PackageProtections.get_offenses(packages: get_packages, new_violations: []) }.to raise_error do |e|
                expect(e).to be_a PackageProtections::IncorrectPublicApiUsageError
                error_message = 'Package packs/apples must have `enforce_privacy: true` to use this protection'
                expect(e.message).to include error_message
              end
            end
          end

          context 'package is newly using another package that permits it' do
            let(:apples_visible_to) { ['trees'] }

            it 'has no offenses' do
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
              expect(offenses).to contain_exactly(0).offenses
            end
          end

          context 'package is newly using another package that does not permit it' do
            let(:apples_visible_to) { ['packs/forestry'] }

            it 'has an offense disallowing the use of the non-visible constant' do
              write_package_yml('packs/trees')
              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                "packs/apples":
                  "Apples::Apple":
                    violations:
                    - dependency
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              violations = get_new_violations
              delete_app_file('packs/trees/deprecated_references.yml')

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
              # There are two offenses here -- one is visbility, one is the dependency violation
              expect(offenses).to contain_exactly(2).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees/models/trees/tree.rb` references non-visible `Apples::Apple` from `packs/apples`',
                'packs/trees/models/trees/tree.rb',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package is newly using another package that does not permit anyone to use it' do
            let(:apples_visible_to) { [] }

            it 'has an offense disallowing the use of the non-visible constant' do
              write_package_yml('packs/trees')
              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                "packs/apples":
                  "Apples::Apple":
                    violations:
                    - dependency
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              violations = get_new_violations
              delete_app_file('packs/trees/deprecated_references.yml')

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
              # There are two offenses here -- one is visbility, one is the dependency violation
              expect(offenses).to contain_exactly(2).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees/models/trees/tree.rb` references non-visible `Apples::Apple` from `packs/apples`',
                'packs/trees/models/trees/tree.rb',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit it' do
            let(:apples_visible_to) { ['packs/forestry'] }

            it 'has an offense disallowing dependency on non-visible package' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(1).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit ANYONE to depend on it' do
            let(:apples_visible_to) { [] }

            it 'has an offense disallowing dependency on non-visible package' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(1).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit it, but there is an existing violation' do
            let(:apples_visible_to) { ['packs/forestry'] }

            it 'still has an offense disallowing dependency on non-visible package' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
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
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that DOES permit it' do
            let(:apples_visible_to) { ['packs/trees'] }

            it 'has no offenses' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: get_new_violations)
              expect(offenses).to contain_exactly(0).offenses
            end
          end
        end

        context 'set to fail_on_any' do
          before do
            write_package_yml('packs/apples',
              visible_to: apples_visible_to,
              protections: { 'prevent_other_packages_from_using_this_package_without_explicit_visibility' => 'fail_on_any' })
          end

          context 'package is newly using another package that permits it' do
            let(:apples_visible_to) { ['trees'] }

            it 'has no offenses' do
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
              expect(offenses).to contain_exactly(0).offenses
            end
          end

          context 'package is newly using another package that does not permit it' do
            let(:apples_visible_to) { ['packs/forestry'] }

            it 'has an offense disallowing the use of the non-visible constant' do
              write_package_yml('packs/trees')
              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                "packs/apples":
                  "Apples::Apple":
                    violations:
                    - dependency
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              violations = get_new_violations
              delete_app_file('packs/trees/deprecated_references.yml')

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
              # There are two offenses here -- one is visbility, one is the dependency violation
              expect(offenses).to contain_exactly(2).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees/models/trees/tree.rb` references non-visible `Apples::Apple` from `packs/apples` (`packs/apples` set to `fail_on_any`)',
                'packs/trees/models/trees/tree.rb',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package is newly using another package that does not permit anyone to use it' do
            let(:apples_visible_to) { [] }

            it 'has an offense disallowing the use of the non-visible constant' do
              write_package_yml('packs/trees')
              write_file('packs/trees/deprecated_references.yml', <<~YML.strip)
                ---
                "packs/apples":
                  "Apples::Apple":
                    violations:
                    - dependency
                    files:
                    - packs/trees/models/trees/tree.rb
              YML

              violations = get_new_violations
              delete_app_file('packs/trees/deprecated_references.yml')

              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: violations)
              # There are two offenses here -- one is visbility, one is the dependency violation
              expect(offenses).to contain_exactly(2).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees/models/trees/tree.rb` references non-visible `Apples::Apple` from `packs/apples` (`packs/apples` set to `fail_on_any`)',
                'packs/trees/models/trees/tree.rb',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit it' do
            let(:apples_visible_to) { ['packs/forestry'] }

            it 'has an offense disallowing dependency on non-visible package' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(1).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that does not permit ANYONE to depend on it' do
            let(:apples_visible_to) { [] }

            it 'has an offense disallowing dependency on non-visible package' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: [])
              expect(offenses).to contain_exactly(1).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package uses another package that does not permit anyone to use it AND has declared a disallowed dependency' do
            let(:apples_visible_to) { [] }

            it 'has an offense disallowing the use of the non-visible constant' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
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
              expect(offenses).to contain_exactly(2).offense
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees/models/trees/tree.rb` references non-visible `Apples::Apple` from `packs/apples` (`packs/apples` set to `fail_on_any`)',
                'packs/trees/models/trees/tree.rb',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
              expect(offenses).to include_offense offense(
                'packs/apples',
                '`packs/trees` cannot state a dependency on `packs/apples`, as it violates package visibility in `packs/apples/package.yml`',
                'packs/trees/package.yml',
                'prevent_other_packages_from_using_this_package_without_explicit_visibility'
              )
            end
          end

          context 'package has declared a dependency on a package that DOES permit it' do
            let(:apples_visible_to) { ['packs/trees'] }

            it 'has no offenses' do
              write_package_yml('packs/trees', dependencies: ['packs/apples'])
              offenses = PackageProtections.get_offenses(packages: get_packages, new_violations: get_new_violations)
              expect(offenses).to contain_exactly(0).offenses
            end
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

      expect(root_package.metadata['protections'].keys).to_not include 'prevent_other_packages_from_using_this_package_without_explicit_visibility'
      protected_package = PackageProtections::ProtectedPackage.from(root_package)
      expect(protected_package.violation_behavior_for('prevent_other_packages_from_using_this_package_without_explicit_visibility')).to eq PackageProtections::ViolationBehavior::FailNever
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

  describe 'packages_for_names' do
    context 'can find the package' do
      it 'returns the package' do
        write_file('package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        write_file('packs/apples/package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        write_file('packs/zebras/package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        packages = PackageProtections.packages_for_names(['packs/apples'], get_packages)
        expect(packages.count).to eq 1
        expect(packages.first.name).to eq 'packs/apples'
      end
    end

    context 'cannot find the package' do
      it 'prints out available packages in sorted order' do
        write_file('package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        write_file('packs/apples/package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        write_file('packs/zebras/package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        expected_error_message = <<~MESSAGE
          Sorry, we couldn't find a package with name packs/elephants. Here are all of the package names we know about: [".", "packs/apples", "packs/zebras"]
        MESSAGE

        expect { PackageProtections.packages_for_names(['packs/elephants'], get_packages) }
          .to raise_error expected_error_message.chomp
      end
    end

    context 'package is root package, and we refer to it using the name .' do
      it 'returns the package' do
        write_file('package.yml', <<~YML.strip)
          enforce_dependencies: true
          enforce_privacy: true
        YML

        packages = PackageProtections.packages_for_names([ParsePackwerk::ROOT_PACKAGE_NAME], get_packages)
        expect(packages.count).to eq 1
        expect(packages.first.name).to eq ParsePackwerk::ROOT_PACKAGE_NAME
      end
    end
  end
end
