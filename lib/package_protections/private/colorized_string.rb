# typed: strict
# frozen_string_literal: true

module PackageProtections
  module Private
    class ColorizedString
      extend T::Sig

      class Color < T::Enum
        enums do
          Black = new
          Red = new
          Green = new
          Yellow = new
          Blue = new
          Pink = new
          LightBlue = new
          White = new
        end
      end

      sig { params(original_string: String, color: Color).void }
      def initialize(original_string, color = Color::White)
        @original_string = original_string
        @color = color
      end

      sig { returns(String) }
      def colorized_to_s
        "\e[#{color_code}m#{@original_string}\e[0m"
      end

      sig { returns(String) }
      def to_s
        @original_string
      end

      sig { returns(ColorizedString) }
      def red
        colorize(Color::Red)
      end

      sig { returns(ColorizedString) }
      def green
        colorize(Color::Green)
      end

      sig { returns(ColorizedString) }
      def yellow
        colorize(Color::Yellow)
      end

      sig { returns(ColorizedString) }
      def blue
        colorize(Color::Blue)
      end

      sig { returns(ColorizedString) }
      def pink
        colorize(Color::Pink)
      end

      sig { returns(ColorizedString) }
      def light_blue
        colorize(Color::LightBlue)
      end

      sig { returns(ColorizedString) }
      def white
        colorize(Color::White)
      end

      private

      sig { params(color: Color).returns(ColorizedString) }
      def colorize(color)
        self.class.new(@original_string, color)
      end

      sig { returns(Integer) }
      def color_code
        case @color
        when Color::Black then 30
        when Color::Red then 31
        when Color::Green then 32
        when Color::Yellow then 33
        when Color::Blue then 34
        when Color::Pink then 35
        when Color::LightBlue then 36
        when Color::White then 37
        else
          T.absurd(@color)
        end
      end
    end
  end
end
