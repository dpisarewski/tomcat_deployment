require "active_support"

class DeploymentUtils
  attr_accessor :host, :war_name, :upload_path, :catalina_home, :username, :destination, :sudo_user, :ssh, :password

  def initialize(destination)
    self.destination  = destination
    load_configruration
  end

  def move_to_temp(file_name)
    FileUtils.move(file_name, "#{file_name}.tmp")
  end

  def restore_from_temp(file_name)
    FileUtils.move("#{file_name}.tmp", file_name)
  end

  def swap_files(files, &block)
    files.each do |filename1, filename2|
      move_to_temp filename1 if File.exist? filename1 and File.exists? filename2
      FileUtils.move filename2, filename1 if File.exists? filename2
    end
    yield
  ensure
    files.each do |filename1, filename2|
      FileUtils.move filename1, filename2 if File.exists? filename1 and File.exist? "#{filename1}.tmp"
      restore_from_temp filename1  if File.exist? "#{filename1}.tmp"
    end
  end

  def compile
    files_to_swap = {
      File.join("config", "database.yml") => File.join("config", "database_original.yml"),
      File.join("config", "deploy.properties") => File.join("config", "deploy_#{destination}.properties")
    }

    swap_files files_to_swap do
      system "bundle exec warble RAILS_ENV=#{destination}"
    end
  end

  def load_configruration(config_file = "config/deploy.yml")
    if File.exists?(config_file)
      config = YAML::load(File.open(config_file))[destination].symbolize_keys
      self.host, self.war_name, self.catalina_home, self.username, self.sudo_user, self.upload_path, self.password =
        config.values_at(:host, :war_name, :catalina_home, :username, :sudo_user, :upload_path, :password)
    end
  end

  def try_sudo(command, user = nil)
    puts "no sudo_user given in the deploy.yml" and return unless sudo_user
    system "ssh -t -t #{sudo_user}@#{host} 'sudo #{"-u #{user}" if user} #{command}'"
  end

  def ssh_session(&block)
    Net::SSH.start host, username, :password => password do |ssh|
      yield self.ssh = ssh
    end
  end

  def upload
    puts "Upload war file to #{upload_path} on the server"
    system "scp #{war_name} #{username}@#{host}:#{upload_path}"
    ssh.exec "chown :tomcat #{upload_path}/#{war_name}"
  end

  def backup_old
    puts "Back up old war file"
    ssh.exec "cp #{deploy_path}/#{war_name} #{deploy_path}/#{war_name}.bak"
  end

  def move_to_deploy_path
    puts "Move war file to #{deploy_path}/#{war_name} on the server"
    ssh.exec "mv #{upload_path}/#{war_name} #{deploy_path}/#{war_name}"
  end

  def stop_server
    puts "Stop tomcat"
    ssh.exec "#{catalina_home}/bin/shutdown.sh"
  end

  def start_server
    puts "Start tomcat"
    ssh.exec "#{catalina_home}/bin/startup.sh"
  end

  def restart_server
    stop_server
    start_server
  end

  def deploy_path
    "#{catalina_home}/webapps"
  end

  def finish
    puts "Deployment complete"
  end

end