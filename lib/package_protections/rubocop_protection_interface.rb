# frozen_string_literal: true

# typed: strict
module PackageProtections
  module RubocopProtectionInterface
    class CopConfig < T::Struct
      extend T::Sig
      const :name, String
      const :enabled, T::Boolean, default: true
      const :include_paths, T::Array[String], default: []
      const :exclude_paths, T::Array[String], default: []

      sig { returns(String) }
      def to_rubocop_yml_compatible_format
        cop_config = { 'Enabled' => enabled }

        if include_paths.any?
          cop_config['Include'] = include_paths
        end

        if exclude_paths.any?
          cop_config['Exclude'] = exclude_paths
        end

        { name => cop_config }.to_yaml.gsub("---\n", '')
      end
    end

    include ProtectionInterface
    extend T::Sig
    extend T::Helpers

    abstract!

    ###########################################################################
    # Abstract Methods: These are methods that the client needs to implement
    ############################################################################
    sig { abstract.returns(String) }
    def cop_name; end

    sig do
      abstract.params(file: String).returns(String)
    end
    def message_for_fail_on_any(file); end

    sig { abstract.returns(T::Array[String]) }
    def included_globs_for_pack; end

    ###########################################################################
    # Overriddable Methods: These are methods that the client can override,
    # but a default is provided.
    ############################################################################
    sig do
      params(package: ProtectedPackage).returns(T::Hash[T.untyped, T.untyped])
    end
    def custom_cop_config(package)
      {}
    end

    sig { override.params(behavior: ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
    def unmet_preconditions_for_behavior(behavior, package); end

    sig do
      override.params(
        new_violations: T::Array[PerFileViolation]
      ).returns(T::Array[Offense])
    end
    def get_offenses_for_new_violations(new_violations)
      []
    end

    sig { void }
    def self.bust_rubocop_todo_yml_cache
      @rubocop_todo_yml = nil
    end

    sig { returns(T.untyped) }
    def self.rubocop_todo_yml
      @rubocop_todo_yml = T.let(@rubocop_todo_yml, T.untyped)
      @rubocop_todo_yml ||= begin
        todo_file = Pathname.new('.rubocop_todo.yml')
        if todo_file.exist?
          YAML.load_file(todo_file)
        else
          {}
        end
      end
    end

    sig do
      override.params(
        protected_packages: T::Array[ProtectedPackage]
      ).returns(T::Array[Offense])
    end
    def get_offenses_for_existing_violations(protected_packages)
      exclude_list = exclude_for_rule(cop_name)
      offenses = []

      protected_packages.each do |package|
        violation_behavior = package.violation_behavior_for(identifier)

        case violation_behavior
        when ViolationBehavior::FailNever, ViolationBehavior::FailOnNew
          next
        when ViolationBehavior::FailOnAny
          # Continue
        else
          T.absurd(violation_behavior)
        end

        package.original_package.directory.glob(included_globs_for_pack).each do |relative_path_to_file|
          next unless exclude_list.include?(relative_path_to_file.to_s)

          file = relative_path_to_file.to_s
          offenses << Offense.new(
            file: file,
            message: message_for_fail_on_any(file),
            violation_type: identifier,
            package: package.original_package
          )
        end
      end

      offenses
    end

    sig do
      params(packages: T::Array[ProtectedPackage])
      .returns(T::Array[CopConfig])
    end
    def cop_configs(packages)
      include_paths = T.let([], T::Array[String])
      packages.each do |p|
        next unless p.violation_behavior_for(identifier).enabled?

        included_globs_for_pack.each do |glob|
          include_paths << p.original_package.directory.join(glob).to_s
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

    private

    sig { params(rule: String).returns(T::Set[String]) }
    def exclude_for_rule(rule)
      rule_config = RubocopProtectionInterface.rubocop_todo_yml[rule] || {}
      Set.new(rule_config['Exclude'] || [])
    end
  end
end
