Gem::Specification.new do |spec|
  spec.name          = 'package_protections'
  spec.version       = '2.0.0'
  spec.authors       = ['Gusto Engineers']
  spec.email         = ['stephan.hagemann@gusto.com']
  spec.summary       = 'Package protections for Rails apps'
  spec.description   = 'Package protections for Rails apps'
  spec.homepage      = 'https://github.com/rubyatscale/package_protections'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://github.com/rubyatscale/parse_packwerk'
    spec.metadata['changelog_uri'] = 'https://github.com/rubyatscale/parse_packwerk/releases'
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
          'public gem pushes.'
  end

  spec.files = Dir['lib/**/*', 'README.md', 'config/default.yml']
  spec.required_ruby_version = Gem::Requirement.new('>= 2.5.0')

  spec.add_dependency 'activesupport'
  spec.add_dependency 'parse_packwerk'
  spec.add_dependency 'rubocop'
  spec.add_dependency 'rubocop-sorbet'
  spec.add_dependency 'sorbet-runtime'
  spec.add_dependency 'zeitwerk'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'sorbet'
  spec.add_development_dependency 'tapioca'
end
