# frozen_string_literal: true

# typed: strict
module PackageProtections
  module RubocopProtectionInterface
    include ProtectionInterface
    extend T::Sig
    extend T::Helpers

    abstract!

    sig do
      abstract
        .params(packages: T::Array[ProtectedPackage])
        .returns(T::Array[CopConfig])
    end
    def cop_configs(packages); end

    sig do
      params(package: ProtectedPackage).returns(T::Hash[T.untyped, T.untyped])
    end
    def custom_cop_config(package)
      {}
    end

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

    private

    sig { params(rule: String).returns(T::Set[String]) }
    def exclude_for_rule(rule)
      rule_config = RubocopProtectionInterface.rubocop_todo_yml[rule] || {}
      Set.new(rule_config['Exclude'] || [])
    end
  end
end
