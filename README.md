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
wget https://raw.githubusercontent.com/aaron-collier/hydra-packager/configuration/lib/tasks/packager.rake
mkdir app/services/packager
wget https://raw.githubusercontent.com/aaron-collier/hydra-packager/configuration/app/services/packager/packager.rake
cd config
wget https://raw.githubusercontent.com/aaron-collier/hydra-packager/configuration/config/packager.yml
```

# Parameters

The rake tasks currently takes one (1) parameters:

1. The file name of the AIP exported package

NOTE: Currently, the packager creates users by the email address of the exported depositor.

TODO: Make the user creation configurable.

# Configuration

All configuration is handled in `config/packager.yml`

### Primary configuration options

1. `input_dir` - the directory to find the AIP packages
2. `include_thumbnail` - a switch used to attach existing thumbnail bitstreams
3. `type_of_work_map` - A hash that maps from "resource_type" and the `hyrax:work` types in your app
2. `fields` - An extensive, nested hash that maps from dspace exported dublin core fields to work properties defined in your models. Includes the appropriate XML xpath query string and
the multiple or singular tag (Array vs String)

### Behavior configuration options

These configuration settings define how the rake task will behave in the shell.

1. `exit_on_error` - should the rake task hard stop when an error occurs. This is helpful when
gettign started, but if the task is expected to run for an extended period of time, it is recommended to set this to `false`
2. `output_level` - What will be output to the shell. This does not affect the log output.

# Importing AIP packages into hyrax

```
rake packager:aip["file.zip"] RAILS_ENV=<target environment>
```

# Logging

Extended output is always available in `log/packager.log`
