# -*- encoding: utf-8 -*-
require File.expand_path('../lib/tomcat_deployment/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Dieter Pisarewski"]
  gem.email         = ["dieter.pisarewski@arvatosystems.com"]
  gem.description   = "Tomcat deployment with Capistrano"
  gem.summary       = "Capistrano recipe for deployment to tomcat"
  gem.homepage      = "http://www.arvatosystems-us.com/"

  gem.files         = Dir.glob("lib/**/*")
  gem.name          = "tomcat_deployment"
  gem.require_paths = ["lib"]
  gem.version       = TomcatDeployment::VERSION

  gem.add_runtime_dependency "bundler"
  gem.add_runtime_dependency "activesupport"
  gem.add_runtime_dependency "capistrano"
  gem.add_runtime_dependency "capistrano-ext"
  gem.add_runtime_dependency "rvm-capistrano"
end
