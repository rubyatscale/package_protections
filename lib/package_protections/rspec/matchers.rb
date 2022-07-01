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
