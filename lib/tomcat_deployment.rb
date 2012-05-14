require "active_support"
require "active_support/core_ext"

if defined? Capistrano
  require "tomcat_deployment/deployment_utils"
  require "tomcat_deployment/recipe"
end

