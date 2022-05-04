# frozen_string_literal: true

# typed: strict
module PackageProtections
  module Private
    class Output
      extend T::Sig

      sig { params(str: String).void }
      def self.p(str)
        puts str
      end

      sig { params(str: ColorizedString, colorized: T::Boolean).void }
      def self.p_colorized(str, colorized:)
        if colorized
          p str.colorized_to_s
        else
          p str.to_s
        end
      end
    end
  end
end
