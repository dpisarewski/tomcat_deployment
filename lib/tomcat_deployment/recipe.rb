unless Capistrano::Configuration.respond_to?(:instance)
  fail "capistrano 2 required"
end

Capistrano::Configuration.instance.load do
  #TODO fail if required variables are missing(application, server, password)

  require "capistrano"
  require 'capistrano/ext/multistage'
  require "rvm/capistrano"
  require "bundler/capistrano"

  set :default_stage, "staging"

  #RVM support
  if not exists? :rvm or rvm
    unless exists? :rvm_ruby_string
      set :rvm_ruby_string, "jruby-1.6.5@#{application}"
    end
    set :rvm_install_type, :stable
    before 'deploy:setup', 'rvm:install_rvm'
    before 'deploy:setup', 'rvm:install_ruby'
  end

  #Bundler support
  set :bundle_cmd, "jruby -ropenssl -S bundle"

  default_run_options[:pty] = true

  # DEPLOYMENT SCHEME
  set :scm, :none
  set :deploy_via, :copy
  set :repository do
    fetch(:deploy_from)
  end

  #Directories
  set :deploy_to do
    "#{apps_directory}/#{application}"
  end
  set :webapps_directory do
    "#{tomcat_home}/webapps"
  end
  set :apps_directory do
    "#{tomcat_home}/apps"
  end
  set :current_release do
    "#{deploy_to}/current"
  end
  set :web_inf do
    "#{webapps_directory}/#{application}/WEB-INF"
  end


  #Create release directory
  set :deploy_from do
    dir = "/tmp/prep_#{release_name}"
    system("mkdir -p #{dir}")
    dir
  end

  # LOCAL
  set :war, "#{application}.war"
  FILES = war

  # USER / SHELL
  unless exists? :user
    set :user, "deploy-user" # the user to run remote commands as
  end
  unless exists? :tomcat_user
    set :tomcat_user, "tomcat"
  end
  unless exists? :tomcat_group
    set :tomcat_group, "tomcat"
  end
  unless exists? :database_config
    set :database_config, "database.yml"
  end
  unless exists? :install_software_requirements
    set :install_software_requirements, true
  end
  unless exists? :add_github_public_key
    set :add_github_public_key, true
  end
  unless exists? :skip_restart
    set :skip_restart, false
  end

  set :use_sudo, false

  before 'rvm:install_rvm' do
    software.install_curl if install_software_requirements
  end

  before 'deploy:setup' do
    deploy_user.configure
    tomcat.create_apps_directory
    gems.add_github_public_key if add_github_public_key
    gems.install_bundler_requirements
  end

  #Compile war file
  before "deploy" do
    deployment = DeploymentUtils.new stage
    deployment.compile
  end

  #Put required files into release directory
  before 'deploy:update_code' do
    unless war.nil?
      system "cp #{war} #{deploy_from}"
      gems.copy_gemfiles
      puts system("ls -l #{deploy_from}")
    end
    warble.backup_war_file if exists? :backup_war_file
  end

  #Link current release and remove unnecessary files
  after 'deploy:update_code' do
    sudo "chmod g+w #{webapps_directory}", :as => tomcat_user
    sudo "[ -f #{webapps_directory}/#{war} ] && chmod g+w #{webapps_directory}/#{war}"
    cmd = "ln -sf #{current_release}/#{war} #{webapps_directory}/#{war}"
    puts cmd
    run cmd
    run "rm -rf #{current_release}/log #{current_release}/public #{current_release}/tmp"
  end

  before 'deploy:finalize_update' do
    deploy.create_symlink
  end

  after 'deploy' do
    deploy.cleanup
  end

  #
  # simple interactions with the tomcat server
  #
  namespace :tomcat do

    unless exists? :restart_pause
      set :restart_pause, 3
    end

    def without_pty
      pty = default_run_options[:pty]
      default_run_options[:pty] = false
      yield
      default_run_options[:pty] = pty
    end

    def sudo_without_pty(command, options = {})
      sudo command, options do |channel, stream, data|
        if data =~ /^#{Regexp.escape(sudo_prompt)}/
          logger.info "#{channel[:host]} asked for password"
          channel.send_data password
        end
      end
    end

    desc "start tomcat"
    task :start do
      without_pty do
        sudo_without_pty "#{tomcat_home}/bin/startup.sh", :as => tomcat_user
      end
    end

    desc "stop tomcat"
    task :stop do
      without_pty do
        sudo_without_pty "#{tomcat_home}/bin/shutdown.sh", :as => tomcat_user
      end
      sudo "pkill -f #{tomcat_process_name}" if exists? :tomcat_process_name
    end

    desc "stop and start tomcat"
    task :restart do
      tomcat.stop
      sleep restart_pause
      tomcat.start
    end

    desc "tail :tomcat_home/logs/*.log and logs/catalina.out"
    task :tail do
      stream "tail -f #{tomcat_home}/logs/*.log #{tomcat_home}/logs/catalina.out"
    end

  end

  namespace :deploy do
    # restart tomcat
    task :restart do
      tomcat.restart unless skip_restart
    end
  end

  #
  # Disable all the default tasks that
  # either don't apply, or I haven't made work.
  #
  namespace :deploy do
    [:cold, :start, :stop, :migrate, :migrations, :assets, :finalize_update ].each do |default_task|
      desc "[internal] disabled"
      task default_task do
        # disabled
      end
    end

    namespace :web do
      [ :disable, :enable ].each do |default_task|
        desc "[internal] disabled"
        task default_task do
          # disabled
        end
      end
    end

    namespace :pending do
      [ :default, :diff ].each do |default_task|
        desc "[internal] disabled"
        task default_task do
          # disabled
        end
      end
    end

  end


  namespace :db do
    def db_config
      YAML::load(ERB.new(File.read("config/#{database_config}")).result)
    end
    def db_password
      db_config[stage]['password']
    end
    def database
      db_config[stage]['database']
    end

    task :copy_production_to_staging do |t|
      run   "mysql -u root -p#{db_password} -e \"DROP DATABASE IF EXISTS #{database}\" && mysqladmin -u root -p#{db_password} create #{database}"
      run   "mysqldump -u root -p#{db_password} #{db_config["production"]['database']} | mysql -u root -p#{db_password} #{database}"
    end

    task :copy_data_from_production do
      run "mysqldump -u root -p#{db_password} --no-create-db --no-create-info --ignore-table=schema_migrations #{db_config["production"]['database']} | mysql -u root -p#{db_password} #{database}"
    end

    task :migrate do |t|
      sudo  "chmod -R g+w #{web_inf}/db", :as => tomcat_user
      run   "cd #{web_inf} && bundle exec rake db:migrate RAILS_ENV=#{stage} --trace"
    end

    task :create_db do |t|
      if exists?(:database_config)
        run "mysql -u root -p#{db_password} -e 'SHOW DATABASES' | grep vacation_request_#{stage} || mysql -u root -p#{db_password} -e 'CREATE DATABASE vacation_request_#{stage}'"
      end
    end
  end

  namespace :gems do
    task :copy_gemfiles do |t|
      system "cp Gemfile Gemfile.lock #{deploy_from}"
    end

    task :add_github_public_key do |t|
      run "[[ -n $(grep '^github.com' ~/.ssh/known_hosts) ]] || ssh-keyscan github.com >> ~/.ssh/known_hosts"
    end

    task :install_bundler_requirements do |t|
      run "gem install rubygems-update"
      run "update_rubygems"
      run "gem install bundler && gem install jruby-openssl"
    end

    task :copy_bundle do |t|
      sudo  "cp -R #{current_release}/.bundle #{web_inf}", :as => tomcat_user
    end
  end

  namespace :warble do
    task :backup_war_file do |t|
      sudo "test -f #{webapps_directory}/#{war} && cp #{webapps_directory}/#{war} #{webapps_directory}/#{war}.bak || true", :as => tomcat_user
    end
  end

  namespace :tomcat do
    task :create_apps_directory do |t|
      sudo "chmod g+w #{tomcat_home}", :as => tomcat_user
      run "mkdir -p #{apps_directory}", :as => tomcat_user
    end
  end

  namespace :deploy_user do
    task :configure do |t|
      run "[ $SHELL != '/bin/bash' ] && chsh -s /bin/bash || true" do |channel, stream, data|
        if data =~ /^Password:/
          logger.info "#{channel[:host]} asked for password"
          channel.send_data password
        end
      end
      sudo "usermod -g #{tomcat_group} #{user}"
    end
  end

  namespace :software do
    task :install_curl do
      sudo "bash -c 'type curl >/dev/null 2>&1 || type apt-get >/dev/null 2>&1 && apt-get install curl'"
    end
  end
end