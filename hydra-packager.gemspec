# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.authors       = ["Aaron Collier"]
  spec.email         = ["acollier@calstate.edu"]
  spec.description   = 'Hydra Packager.'
  spec.summary       = 'Hydra Packager.'
  spec.homepage      = 'https://github.com/aaron-collier/hydra-packager'
  spec.name          = 'hydra-packager'
  spec.require_paths = ['lib']
  spec.version       = '1.0'
  spec.license       = 'Apache2'
  spec.files         = ['lib/hydra_packager.rb'] + Dir['lib/tasks/*'] + ['README.md']

  spec.add_dependency 'rubyzip'
  spec.add_dependency 'colorize'
end
