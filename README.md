# hydra-packager
This is a rake job for importing DSpace exported AIP packages into Hydra repositories

# Prerequisites

This rake job was built for [Hyrax](http://hyr.ax/), but should be usable in any [Project Hydra](http://projecthydra.github.io/)
based repository project.

The following additional dependencies are necessary:

1. [RubyZip](#rubyzip) - The [rubyzip](https://rubygems.org/gems/rubyzip/versions/1.2.0) gem for unzipping packages
2. [Colorize](#colorize) - The [colorize](https://rubygems.org/gems/colorize) gem is used for formatted shell output

### RubyZip

Add the `rubyzip` gem to your Gemfile
```
gem 'rubyzip'
```

### Colorize

Add the `colorize` gem to your Gemfile
```
gem 'colorize'
```
