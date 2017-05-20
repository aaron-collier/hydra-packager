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

# Installation

### Quick Install

Download the rake file into your apps `lib/tasks` folder:

```
cd lib/tasks
wget https://raw.githubusercontent.com/aaron-collier/hydra-packager/master/lib/tasks/packager.rake
```

# Parameters

The rake tasks currently takes two (2) parameters:

1. The full path to the root AIP exported package
2. The email address of the default depositor

NOTE: Currently, the packager creates users by the email address of the exported depositor.

TODO: Make the user creation configurable.

# Configuration

All configuration is currently handled inside the rake file.

TODO: Add a configuration file.

1. @type_of_work_map - A hash that maps from "resource_type" and the `hyrax:work` types in your app
2. @attributes - A hash that maps from dspace exported dublin core fields to work properties defined in your models where multiple is true (default)
3. @singulars - A hash that maps from dspace exported dunblin core fields to work properties defined in your models where multiple is false

# Importing AIP packages into hyrax

```
rake packager:aip["/path/to/zip/file.zip","admin@example.edu"] RAILS_ENV=<target environment
```
