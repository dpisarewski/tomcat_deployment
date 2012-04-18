# TomcatDeployment

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'tomcat_deployment'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install tomcat_deployment

## Usage

1. Create 'deploy.rb' file and define application name, server, user, password, tomcat directory and environment in it

```ruby
set :application, "my_application"
server "myhost", :web, :app, :db
set :user, "deploy-user"
set :password, "deploy user password"
set :tomcat_home, "/opt/apache-tomcat-6.0.33"
set :stage, "production"
```

Optional you can define you ruby version. jruby-1.6.5 will be used by default.

```ruby
set :rvm_ruby_string, "jruby-1.6.5@#{application}"
```

2. If you deploy to many stages, you can create 'deploy' directory with your many deployment configurations. In this case 'deploy.rb' will be used for common settings.

```shell
mkdir deploy
touch deploy/staging.rb
touch deploy/production.rb
```

3. Set up migrations task using available tasks for migrations or define yours(db.create_db, db.copy_production_to_staging, db.copy_data_from_production, db.migrate). You have to run task 'gems.copy_bundle' before any task that runs ruby on the server.

```ruby
namespace :deploy do
  task :migrations do |t|
    gems.copy_bundle
    db.create_db
    db.migrate
  end
end
```

4. If it's the first deployment run 'cap <environment> deploy:setup'

5. Run 'cap <environment> deploy'

6. If there are new migrations in the release run 'cap <environment> deploy:migrations'