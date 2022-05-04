# frozen_string_literal: true

# typed: strict
module PackageProtections
  # Perhaps this should be in ParsePackwerk. For now, this is here to help us break down violations per file.
  # This is analogous to `Packwerk::ReferenceOffense`
  class PerFileViolation < T::Struct
    extend T::Sig

    const :class_name, String
    const :filepath, String
    const :type, String
    const :constant_source_package, String
    const :reference_source_package, ParsePackwerk::Package

    sig { params(violation: ParsePackwerk::Violation, reference_source_package: ParsePackwerk::Package).returns(T::Array[PerFileViolation]) }
    def self.from(violation, reference_source_package)
      violation.files.map do |file|
        PerFileViolation.new(
          type: violation.type,
          class_name: violation.class_name,
          filepath: file,
          constant_source_package: violation.to_package_name,
          reference_source_package: reference_source_package
        )
      end
    end

    sig { returns(T::Boolean) }
    def dependency?
      type == 'dependency'
    end

    sig { returns(T::Boolean) }
    def privacy?
      type == 'privacy'
    end
  end
end
