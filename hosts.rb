require 'yaml'
require 'net/ssh'
require 'net/scp'

require_relative 'log'

class GenericHost
  attr_accessor :name
  attr_accessor :host
  attr_accessor :user
  attr_accessor :pass
  attr_accessor :ssh_conn

  def initialize(name, host, user, pass)
    @name = name
    @host = host
    @user = user
    @pass = pass
  end

  def ssh_connect
    return if @ssh_conn
    debug "connecting to #{name} #{host} ... "
    @ssh_conn = Net::SSH.start(@host, @user, :password => @pass)
    debug "#{name} #{host} conntected"
  end

  def ssh_exec!(ssh, command)
    stdout_data = ""
    stderr_data = ""
    exit_code = nil
    exit_signal = nil
    ssh.open_channel do |channel|
      channel.exec(command) do |ch, success|
        unless success
          fail "FAILED: couldn't execute command (ssh.channel.exec)"
          abort "FAILED: couldn't execute command (ssh.channel.exec)"
        end
        channel.on_data do |ch,data|
          stdout_data+=data
        end

        channel.on_extended_data do |ch,type,data|
          stderr_data+=data
        end

        channel.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
        end

        channel.on_request("exit-signal") do |ch, data|
          exit_signal = data.read_long
        end
      end
    end
    ssh.loop
    [stdout_data, stderr_data, exit_code, exit_signal]
  end

  def exec(cmd, stopaterror = nil)
    ssh_connect
    debug "exec #{cmd} on #{@name}"
    stdout, stderr, code, signal = ssh_exec!(@ssh_conn, cmd)
    if code > 0 and stopaterror then
      abort "FAILED, command return with error: #{stderr}"
    end
    stdout.strip
  end

  def _sed_search(str)
    return "sed -n 's/#{str}\\(.*\\).*/\\1/p'"
  end

end


class Host < GenericHost

  def upload(local, remote)
    unless remote.start_with? '/'
      warn "remote dir must start with /"
      return
    end
    ssh_connect
    Dir.glob(local) do |file|
      debug "uploding #{file} to #{@host}:#{remote}"
      @ssh_conn.scp.upload! file, remote do |ch, name, sent, total|
        percent = 100
        percent = sent * 100 / total if total > 0
        debug "    #{name} - #{percent}% - #{sent}/#{total}"
      end
    end
    debug "upload completed"
  end

  def download(remote, local)
    unless remote.start_with? '/'
      warn "remote dir must start with /"
      return
    end
    ssh_connect
    files = exec("find #{remote} -type f").split("\n")
    files.each do |file|
      file = file.strip
      debug "downloading #{@host}:#{file} to #{local}"
      @ssh_conn.scp.download! file, local do |ch, name, sent, total|
        percent = 100
        percent = sent * 100 / total if total > 0
        debug "    #{name}: #{percent}% \t #{sent}/#{total}"
      end
    end
    debug "download completed"
  end

  def start_task(task)
    info "starting #{task} as backgroud task"
    cmd = "nohup #{task} > /dev/null 2> /dev/null < /dev/null &"
    exec(cmd)
  end

  def brackets_first_char(str)
    return str if str.size < 1
    return "[#{str[0]}]#{str[1..-1]}"
  end

  def kill(str)
    info "kill #{str}"
    cmd = "ps -aef | grep #{brackets_first_char(str)} | awk '{print $2}' | xargs kill"
    exec(cmd)
    while(true)
      sleep 2
      debug "waiting for #{str} to die"
      break unless check_task(str)
    end
  end

  def check_task(str)
    cmd = "ps -aef | grep #{brackets_first_char(str)}"
    return false if exec(cmd).size == 0
    true
  end

  def wait_task(str)
    info "waiting for #{str} to end..."
    while true
      break unless check_task(str)
      sleep 1
    end
    puts "gone."
  end

  def wait_or_kill_task(str, timeout)
    info "wait or kill task #{str} timeout #{timeout}"
    time1 = Time.now
    while true
      seconds = Time.now - time1
      unless check_task(str)
        debug "#{str} is gone, run for #{seconds} seconds"
        break
      end
      if seconds > timeout
        debug "timeout #{seconds} seconds, killing #{str} and exit"
        kill(str)
        break
      end
      sleep 5
    end
  end

end

class Hosts
  def initialize
    @hosts = {}
    load_yaml
  end

  def initialize(hosts)
    @hosts = hosts
  end

  def load_yaml
    hosts_hash = YAML.load_file('hosts.yml')['hosts']
    user = hosts_hash['user']
    pass = hosts_hash['pass']
    hosts_hash['list'].each do |hash|
      name = hash.keys[0]
      value = hash.values[0]
      h = Host.new(name, value, user, pass)
      @hosts[name] = h
      self.class.send :define_method, name do h end
    end
  end

  def start_task(task)
    @hosts.each do |name, host|
      host.start_task(task) if defined? host.start_task
    end
  end

  def wait_task(str)
    hosts = @hosts.values.select { |h| defined? h.check_task }
    while true
      break if hosts.size == 0
      hosts.each do |h| 
        hosts.delete(h) unless h.check_task
      end
      sleep 1
    end
  end

  def exec(str)
    @hosts.each do |name, h|
      h.exec(str)
    end
  end

  def pexec
    threads = []
    @hosts.each do |name, h|
      threads << Thread.new { yield(name, h) }
    end
    threads.each do |t|
      t.join
    end
  end

  def pkill(str)
    threads = []
    @hosts.each do |name, h|
      threads << Thread.new { h.kill(str) }
    end
    threads.each do |t|
      t.join
    end
  end

  def kill(str)
    @hosts.each do |name, h|
      h.kill(str)
    end
  end

  def all
    return @hosts
  end
end
