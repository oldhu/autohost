require 'rexml/document'

class SymmetrixHost < Host
  def initialize(name, host, user, pass, sid)
    super(name, host, user, pass)
    @sid = sid
    @hbas = []
  end

  def exec_doc(cmd)
    cmd = 'PATH=$PATH:/opt/emc/SYMCLI/bin/;export SYMCLI_OUTPUT_MODE=XML_ELEMENT;' + cmd 
    return REXML::Document.new(exec(cmd))
  end

  def exec_with_sid(sid, cmd)
    return exec_doc("export SYMCLI_SID=#{sid};" + cmd)
  end

  def fetch_symids
    doc = exec_doc('syminq -sym -symmids -wwn')
    symids = []
    doc.elements.each('SymCLI_ML/Inquiry/symid') do |ele|
      symids << ele.text
    end
    puts symids.uniq!
  end

  def fetch_fa_wwns(sid)
    @hbas = []
    doc = exec_with_sid(sid, 'symcfg list -FA ALL')
    doc.elements.each('SymCLI_ML/Symmetrix/Director') do |dir|
      id = dir.text('Dir_Info/id')
      dir.elements.each('Port/Port_Info') do |port|
        dev = "#{id}:#{port.text('port')}"
        wwn = port.text('port_wwn')
        speed = port.text('maximum_speed')
        hba = HBA.new(dev, wwn, speed)
        @hbas << hba
      end
    end
  end

  def fetch_hba
    fetch_fa_wwns(@sid)
  end

  def fetch_maskviews(host)
    views = []
    host.hbas.each do |hba|
      doc = exec_with_sid(@sid, "symaccess list -type initiator -wwn #{hba.wwn_compact}")
      doc.elements.each('SymCLI_ML/Symmetrix/Initiator_Group/Group_Info/Mask_View_Names/view_name') do |ele|
        views << ele.text
      end
    end
    views.uniq
  end

  def fetch_sgs_from_maskviews(maskviews)
    sgs = []
    maskviews.each do |view|
      doc = exec_with_sid(@sid, "symaccess list view -name #{view}")
      sgs << doc.text('SymCLI_ML/Symmetrix/Masking_View/View_Info/stor_grpname')
    end
    sgs.uniq
  end

  def fetch_devs_from_sgs(sgs)
    devs = []
    sgs.each do |sg|
      doc = exec_with_sid(@sid, "symaccess show #{sg} -type storage")
      doc.elements.each('SymCLI_ML/Symmetrix/Storage_Group/Group_Info/Device/start_dev') do |ele|
        devs << ele.text
      end
    end
    devs.uniq
  end

  def fetch_devs_for_host(host)
    maskviews = fetch_maskviews(host)
    sgs = fetch_sgs_from_maskviews(maskviews)
    devs = fetch_devs_from_sgs(sgs)
  end

  def fetch_full_sid(sid)
    doc = exec_with_sid(sid, 'symcfg list')
    doc.text('SymCLI_ML/Symmetrix/Symm_Info/symid')
  end

  def clean_ttp
    sid = fetch_full_sid(@sid)
    exec("rm /var/symapi/stp/ttp/#{sid}/*")
  end

  def download_ttp(local)
    sid = fetch_full_sid(@sid)
    download("/var/symapi/stp/ttp/#{sid}/", local)
  end

  def start_ttp(interval)
    exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name dmn_symmids=#{@sid}")
    exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name dmn_run_ttp=Enabled")
    exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name ttp_collection_interval=#{interval}")
    exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name ttp_symmids=#{@sid}")
    exec("/opt/emc/SYMCLI/bin/stordaemon start storstpd")
  end

  def stop_ttp
    exec("/opt/emc/SYMCLI/bin/stordaemon shutdown storstpd")
  end

end