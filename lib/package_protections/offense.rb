# typed: strict

module PackageProtections
  class Offense < T::Struct
    extend T::Sig

    const :file, String
    const :message, String
    const :violation_type, Identifier
    const :package, ParsePackwerk::Package

    sig { returns(String) }
    def package_name
      package.name
    end
  end
end
