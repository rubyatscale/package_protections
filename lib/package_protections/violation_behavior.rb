# frozen_string_literal: true

# typed: strict

module PackageProtections
  class IncorrectPublicApiUsageError < StandardError; end

  class ViolationBehavior < T::Enum
    extend T::Sig

    enums do
      FailOnAny = new('fail_on_any')
      FailOnNew = new('fail_on_new')
      FailNever = new('fail_never')
    end

    sig { params(value: T.untyped).returns(ViolationBehavior) }
    def self.from_raw_value(value)
      ViolationBehavior.deserialize(value.to_s)
    rescue KeyError
      # Let's not encourage "unknown." That's mostly considered an internal value if nothing is specified.
      acceptable_values = ViolationBehavior.values.map(&:serialize) - ['unknown']
      raise IncorrectPublicApiUsageError.new("The metadata value #{value} is not a valid behavior. Double check your spelling! Acceptable values are #{acceptable_values}. See https://github.com/rubyatscale/package_protections#readme for more info") # rubocop:disable Style/RaiseArgs
    end

    sig { returns(T::Boolean) }
    def fail_on_any?
      case self
      when FailOnAny then true
      when FailOnNew then false
      when FailNever then false
      else
        T.absurd(self)
      end
    end

    sig { returns(T::Boolean) }
    def enabled?
      case self
      when FailOnAny then true
      when FailOnNew then true
      when FailNever then false
      else
        T.absurd(self)
      end
    end

    sig { returns(T::Boolean) }
    def fail_on_new?
      case self
      when FailOnAny then false
      when FailOnNew then true
      when FailNever then false
      else
        T.absurd(self)
      end
    end

    sig { returns(T::Boolean) }
    def fail_never?
      case self
      when FailOnAny then false
      when FailOnNew then false
      when FailNever then true
      else
        T.absurd(self)
      end
    end
  end
end
