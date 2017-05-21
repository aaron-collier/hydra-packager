require 'hydra_packager'
require 'rails'

class HydraPackager::Railtie < Rails::Railtie
  rake_tasks do
    load "tasks/lib/packager.rake"
  end
end
