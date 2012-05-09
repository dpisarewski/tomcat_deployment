# TomcatDeployment

Capistrano recipe for Tomcat

## Requirements

1. bash
2. apt-get (otherwise disable installing curl and install it manually)
3. user with sudo rights

## Installation

Add this line to your application's Gemfile:

```ruby
group :development do
    gem 'tomcat_deployment'
end
```

And then execute:

```shell
bundle
```

Or install it yourself as:

```shell
gem install tomcat_deployment
```

## Usage

1. Create 'deploy.rb' file and define application name, server, user, password, tomcat directory and environment in it

    ```ruby
    require "bundler/setup"
    require "tomcat_deployment"

    set :application, "my_application"
    server "myhost", :web, :app, :db
    set :user, "deploy-user"
    set :password, "deploy user password"
    set :tomcat_home, "/opt/apache-tomcat-6.0.33"
    set :stage, "production"
    ```

    User is 'deploy-user' by default.

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

    db.create_db, db.copy_production_to_staging and db.copy_data_from_production work only with MySQL database.

4. If it's the first deployment run `cap <environment> deploy:setup`

5. Run `cap <environment> deploy`

6. If there are new migrations in the release run `cap <environment> deploy:migrations`

### Options
If you want to backup war file before replacing it with new one add:

```ruby
set :backup_war_file, true
```


If you want to use database configuration file different from 'database.yml' define:

```ruby
set :database_config, "your configuration file"
```

To define tomcat user add:

```ruby
set :tomcat_user, "your tomcat user"
```

If you want to kill tomcat process after shutdown add:

```ruby
set :tomcat_process_name, "your tomcat process name"
```

To set pause after tomcat shutdown add:

```ruby
set :restart_pause, 3
```

To skip installing curl on setup or to skip adding github public key:

```ruby
set :install_software_requirements, false
set :add_github_public_key
```

