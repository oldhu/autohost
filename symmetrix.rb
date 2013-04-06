require 'rexml/document'

class SymmetrixHost < Host
  attr_accessor :sid
  attr_accessor :stp

  def initialize(name, host, user, pass, sid)
    super(name, host, user, pass)
    @sid = sid
    @stp = STP.new(self)
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

end

class STP
  def initialize(symm)
    @symm = symm
  end

  def full_sid
    @full_sid ||= symm.fetch_full_sid(@symm.sid)
  end

  def set_option(name, value)
    symm.exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name #{name}=#{value}")
  end

  def disable_rdf_collect
    set_option('ttp_rdfa_metrics', 'Disabled')
    set_option('ttp_rdfsys_metrics', 'Disabled')
    set_option('ttp_rdfdir_metrics', 'Disabled')
    set_option('ttp_rdfdev_metrics', 'Disabled')
    set_option('ttp_rdfgrp_metrics', 'Disabled')
  end

  def set_default_options
    set_option('dmn_symmids', full_sid)
    set_option('dmn_run_ttp', 'Enabled')
    set_option('ttp_collection_interval', interval)
    set_option('ttp_symmids', full_sid)
    set_option('ttp_tp_dev_metrics', 'Enabled')
    set_option('sync_vp_data', 'Enabled')
  end

  def start(interval)
    info "starting stordaemon for sid #{full_sid}, collect interval #{interval}"
    set_default_options
    @symm.exec("/opt/emc/SYMCLI/bin/stordaemon start storstpd")
  end

  def stop
    info "stopping stordaemon for sid #{full_sid}"
    @symm.exec("/opt/emc/SYMCLI/bin/stordaemon shutdown storstpd")
  end

  def clean
    info "cleaning ttp log dir for #{full_sid}"
    @symm.exec("rm /var/symapi/stp/ttp/#{full_sid}/*")
  end

  def download(local)
    info "download ttp log files for #{full_sid} into #{local}"
    @symm.download("/var/symapi/stp/ttp/#{full_sid}/", local)
  end
end