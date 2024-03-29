# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `rubocop-packs` gem.
# Please instead update this file by running `bin/tapioca gem rubocop-packs`.

module RuboCop; end
module RuboCop::Cop; end
module RuboCop::Cop::Packs; end

class RuboCop::Cop::Packs::ClassMethodsAsPublicApis < ::RuboCop::Cop::Base
  sig { params(node: T.untyped).void }
  def on_def(node); end

  sig { returns(T::Boolean) }
  def support_autocorrect?; end
end

class RuboCop::Cop::Packs::DocumentedPublicApis < ::RuboCop::Cop::Style::DocumentationMethod
  sig { params(node: T.untyped).void }
  def check(node); end

  sig { returns(T::Boolean) }
  def support_autocorrect?; end
end

class RuboCop::Cop::Packs::RootNamespaceIsPackName < ::RuboCop::Cop::Base
  include ::RuboCop::Cop::RangeHelp

  sig { void }
  def on_new_investigation; end

  sig { returns(T::Boolean) }
  def support_autocorrect?; end

  private

  sig { returns(RuboCop::Cop::Packs::RootNamespaceIsPackName::DesiredZeitwerkApi) }
  def desired_zeitwerk_api; end
end

class RuboCop::Cop::Packs::RootNamespaceIsPackName::DesiredZeitwerkApi
  sig { params(relative_filename: String, package_for_path: ParsePackwerk::Package).returns(T.nilable(RuboCop::Cop::Packs::RootNamespaceIsPackName::DesiredZeitwerkApi::NamespaceContext)) }
  def for_file(relative_filename, package_for_path); end

  sig { params(pack: ParsePackwerk::Package).returns(String) }
  def get_pack_based_namespace(pack); end

  private

  sig { params(remaining_file_path: String, package_name: String).returns(String) }
  def get_actual_namespace(remaining_file_path, package_name); end

  sig { params(pack: ParsePackwerk::Package).returns(String) }
  def get_package_last_name(pack); end

  sig { returns(Pathname) }
  def root_pathname; end
end

class RuboCop::Cop::Packs::RootNamespaceIsPackName::DesiredZeitwerkApi::NamespaceContext < ::T::Struct
  const :current_fully_qualified_constant, String
  const :current_namespace, String
  const :expected_filepath, String
  const :expected_namespace, String

  class << self
    def inherited(s); end
  end
end

class RuboCop::Cop::Packs::TypedPublicApis < ::RuboCop::Cop::Sorbet::StrictSigil
  sig { params(processed_source: T.untyped).void }
  def investigate(processed_source); end
end

module RuboCop::Cop::PackwerkLite; end
class RuboCop::Cop::PackwerkLite::ConstantResolver; end

module RuboCop::Packs
  class << self
    sig { params(packs: T::Array[ParsePackwerk::Package]).void }
    def auto_generate_rubocop_todo(packs:); end

    sig { void }
    def bust_cache!; end

    sig { returns(RuboCop::Packs::Private::Configuration) }
    def config; end

    sig { params(blk: T.proc.params(arg0: RuboCop::Packs::Private::Configuration).void).void }
    def configure(&blk); end

    sig { params(rule: String).returns(T::Set[String]) }
    def exclude_for_rule(rule); end

    sig { params(root_pathname: String).returns(String) }
    def pack_based_rubocop_todos(root_pathname: T.unsafe(nil)); end

    sig { params(packs: T::Array[ParsePackwerk::Package]).void }
    def set_default_rubocop_yml(packs:); end

    sig { returns(T::Array[String]) }
    def validate; end
  end
end

RuboCop::Packs::CONFIG = T.let(T.unsafe(nil), Hash)
RuboCop::Packs::CONFIG_DEFAULT = T.let(T.unsafe(nil), Pathname)
class RuboCop::Packs::Error < ::StandardError; end

module RuboCop::Packs::Inject
  class << self
    sig { void }
    def defaults!; end
  end
end

RuboCop::Packs::PROJECT_ROOT = T.let(T.unsafe(nil), Pathname)

module RuboCop::Packs::Private
  class << self
    sig { void }
    def bust_cache!; end

    sig { params(rule: String).returns(T::Set[String]) }
    def exclude_for_rule(rule); end

    sig { void }
    def load_client_configuration; end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def rubocop_todo_ymls; end

    sig { params(package: ParsePackwerk::Package).returns(T::Array[String]) }
    def validate_failure_mode_strict(package); end

    sig { params(package: ParsePackwerk::Package).returns(T::Array[String]) }
    def validate_rubocop_todo_yml(package); end

    sig { params(package: ParsePackwerk::Package).returns(T::Array[String]) }
    def validate_rubocop_yml(package); end
  end
end

class RuboCop::Packs::Private::Configuration
  sig { void }
  def initialize; end

  sig { void }
  def bust_cache!; end

  sig { returns(T::Array[String]) }
  def globally_permitted_namespaces; end

  def globally_permitted_namespaces=(_arg0); end

  sig { returns(T::Array[String]) }
  def permitted_pack_level_cops; end

  def permitted_pack_level_cops=(_arg0); end

  sig { returns(T::Array[String]) }
  def required_pack_level_cops; end

  def required_pack_level_cops=(_arg0); end
end

module RuboCop::PackwerkLite; end
class RuboCop::PackwerkLite::Error < ::StandardError; end
