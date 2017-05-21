# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.authors       = ["Aaron Collier"]
  spec.email         = ["acollier@calstate.edu"]
  spec.description   = 'Hydra Packager.'
  spec.summary       = 'Hydra Packager.'

  spec.add_dependency 'rubyzip'
  spec.add_dependency 'colorize'
end
