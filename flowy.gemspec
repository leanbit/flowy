require_relative 'lib/flowy/version'

Gem::Specification.new do |spec|
  spec.name          = 'flowy'
  spec.version       = Flowy::VERSION
  spec.authors       = ['Leanbit']
  spec.email         = ['support@leanbit.eu']

  spec.summary       = 'Lightweight Railway Oriented Programming for Ruby'
  spec.description   = 'Flowy provides Success/Failure result objects and a composable step-based concern for clean, functional-style service objects in Ruby.'
  spec.homepage      = 'https://github.com/leanbit/flowy'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2'

  spec.add_development_dependency 'rspec', '~> 3.13'

  spec.files         = Dir['lib/**/*', 'README.md', 'LICENSE.txt']
  spec.require_paths = ['lib']
end
