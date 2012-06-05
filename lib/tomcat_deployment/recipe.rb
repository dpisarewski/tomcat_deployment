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
  unless exists? :tomcat_stop_cmd
    set :tomcat_stop_cmd do
      "#{tomcat_home}/bin/shutdown.sh"
    end
  end
  unless exists? :tomcat_start_cmd
    set :tomcat_start_cmd do
      "#{tomcat_home}/bin/start.sh"
    end
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
    tomcat.stop unless skip_restart
    tomcat.remove_old_application_directory
    sudo "chmod g+w #{webapps_directory}", :as => tomcat_user
    sudo "[ -f #{webapps_directory}/#{war} ] && chmod g+w #{webapps_directory}/#{war} || true"
    cmd = "ln -sf #{current_release}/#{war} #{webapps_directory}/#{war}"
    puts cmd
    run cmd
    run "rm -rf #{current_release}/log #{current_release}/public #{current_release}/tmp"
    tomcat.start unless skip_restart
  end

  before 'deploy:finalize_update' do
    deploy.create_symlink
  end

  after 'deploy' do
    deploy.cleanup
  end

  def in_shell(shell)
    tmp = default_shell
    set :default_shell, shell
    yield
    set :default_shell, tmp
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

  #
  # simple interactions with the tomcat server
  #
  namespace :tomcat do

    unless exists? :restart_pause
      set :restart_pause, 3
    end

    desc "start tomcat"
    task :start do
      without_pty do
        sudo_without_pty tomcat_start_cmd
      end
    end

    desc "stop tomcat"
    task :stop do
      without_pty do
        sudo_without_pty tomcat_stop_cmd
      end
      sleep restart_pause
      tomcat.kill_webserver_process
    end

    task :kill_webserver_process do
      without_pty do
        sudo_without_pty "pkill -9 -f #{tomcat_process_name}; true", :as => tomcat_user if exists? :tomcat_process_name
      end
    end

    desc "stop and start tomcat"
    task :restart do
      tomcat.stop
      tomcat.start
    end

    task :remove_old_application_directory do
      sudo "sh -c 'rm -rf #{webapps_directory}/#{application}'; true", :as => tomcat_user
    end

    desc "tail :tomcat_home/logs/*.log and logs/catalina.out"
    task :tail do
      stream "tail -f #{tomcat_home}/logs/*.log #{tomcat_home}/logs/catalina.out"
    end

  end

  namespace :deploy do
    task :restart do
      #do nothing here
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
      YAML::load(ERB.new(File.read("config/#{database_config}").concat("\n")).result)
    end
    def db_password
      db_config[stage]['password']
    end
    def database
      db_config[stage]['database']
    end
    def db_user
      db_config[stage]['username']
    end

    task :copy_production_to_staging do |t|
      password_param = " -p#{db_password}" if db_password.present?
      run   "mysql -u #{db_user} #{password_param} -e \"DROP DATABASE IF EXISTS #{database}\" && mysqladmin -u #{db_user} #{password_param} create #{database}"
      run   "mysqldump -u #{db_user} #{password_param} #{db_config["production"]['database']} | mysql -u #{db_user} #{password_param} #{database}"
    end

    task :copy_data_from_production do
      password_param = " -p#{db_password}" if db_password.present?
      run "mysqldump -u #{db_user} #{password_param} --no-create-db --no-create-info --ignore-table=schema_migrations #{db_config["production"]['database']} | mysql -u #{db_user} #{password_param} #{database}"
    end

    task :migrate do |t|
      sudo  "chmod -R g+w #{web_inf}/db", :as => tomcat_user
      run   "cd #{web_inf} && bundle exec rake db:migrate RAILS_ENV=#{stage} --trace"
    end

    task :create_db do |t|
      if exists?(:database_config)
        password_param = " -p#{db_password}" if db_password.present?
        run "mysql -u #{db_user} #{password_param} -e 'SHOW DATABASES' | grep #{database} || mysql -u #{db_user} #{password_param} -e 'CREATE DATABASE #{database}'"
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
      run "[ $SHELL != '/bin/bash' ] && chsh -s /bin/bash; true" do |channel, stream, data|
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
      in_shell("/bin/bash") do
        sudo "bash -c 'type curl >/dev/null 2>&1 || type apt-get >/dev/null 2>&1 && apt-get install curl'"
      end
    end
  end

  #WORKAROUND FOR CAPISTRANO BUG
  namespace :deploy do
    self.class.send(:include, Capistrano::Configuration::Actions::Inspect)
  end

end