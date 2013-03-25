class HBA
  attr_accessor :dev
  attr_accessor :speed

  def initialize(dev, wwn, speed)
    @dev = dev
    set_wwn wwn
    set_speed speed
  end

  def set_wwn(value)
    raise "wwn not valid" unless value.size >= 16
    v = value[-16, 16].downcase
    @wwn = [v[0, 2], v[2, 2], v[4, 2], v[6, 2], v[8, 2], v[10, 2], v[12, 2], v[14, 2]]
  end

  def set_speed(value)
    raise "speed not valid" unless value.size >= 1
    @speed = value[0].to_i
  end

  def wwn=(value)
    set_wwn(value)
  end

  def wwn
    return @wwn.join(':')
  end

  def wwn_compact
    return @wwn.join('')
  end

  def inspect
    return "#{@dev}, #{@wwn}, #{@speed}"
  end
end

class SanHost < GenericHost
  attr_accessor :hbas

  def initialize(name, host, user, pass)
    super(name, host, user, pass)
    @hbas = nil
  end

  def fetch_hba
    @hbas = []
    debug "fetching HBA of #{@host}"
    return unless defined? cmd_list_hbas

    hba_devs = exec(cmd_list_hbas)
    hba_devs.split.each do |dev|
      wwn = exec(cmd_get_wwn(dev))
      # speed = exec(cmd_get_speed(dev))
      hba = HBA.new(dev, wwn, 'NA')
      @hbas.push(hba)
    end
    debug "found #{@hbas.size} HBA"
  end
end

class AixHost < SanHost
  def cmd_list_hbas
    "lsdev -Cc adapter | grep fcs | awk '{print $1}'"
  end

  def cmd_get_wwn(dev)
    "lscfg -vl #{dev} | #{_sed_search('Network Address\\.*')}"
  end

  def cmd_get_speed(dev)
    "fcstat #{dev} | #{_sed_search('Port Speed (running):')}"
  end
end

class HpuxHost < SanHost
  def cmd_list_hbas
    "ls /dev | egrep 'fcd|td|fclp'"
  end

  def cmd_get_wwn(dev)
    "/opt/fcms/bin/fcmsutil /dev/#{dev} | #{_sed_search('N_Port Port World Wide Name =')}"
  end

  def cmd_get_speed(dev)
    "/opt/fcms/bin/fcmsutil /dev/#{dev} | #{_sed_search('Link Speed =')}"
  end
end

class EsxHost < SanHost  
  def fetch_hba
    @hbas = []
    debug "fetching HBA of #{@host}"

    hba_devs = exec('esxcli --formatter=csv storage core adapter list')
    hba_devs.split.each do |line|
      values = line.split(',')
      next unless values.size >= 5
      addr =  values[4].strip
      if m = /fc\.(.*?):(.*)/.match(addr)
        dev = values[2]
        wwn = m[2]
        hba = HBA.new(dev, wwn, 'NA')
        @hbas.push(hba)
      end
    end
    debug "found #{@hbas.size} HBA"
  end

end