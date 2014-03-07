require 'rexml/document'

class SymmetrixHost < SanHost
  attr_accessor :sid
  attr_accessor :stp
  attr_accessor :ap

  def initialize(name, host, user, pass, sid)
    super(name, host, user, pass)
    @sid = sid
    @stp = STP.new(self)
    @ap = AutoProvision.new(self)
  end

  def exec_doc(cmd)
    cmd = 'PATH=$PATH:/opt/emc/SYMCLI/bin/;export SYMCLI_OUTPUT_MODE=XML_ELEMENT;' + cmd 
    return REXML::Document.new(exec(cmd))
  end

  def exec_with_sid(sid, cmd)
    return exec_doc("export SYMCLI_SID=#{sid};" + cmd)
  end

  def exec_sym(cmd)
    return exec_doc("export SYMCLI_SID=#{@sid};" + cmd)
  end

  # replace with symcfg list
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
    debug "fetching HBA of #{@host}"
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
    @full_sid ||= @symm.fetch_full_sid(@symm.sid)
  end

  def set_option(name, value)
    @symm.exec("/opt/emc/SYMCLI/bin/stordaemon setoption storstpd -name #{name}=#{value}")
  end

  def disable_rdf_collect
    set_option('ttp_rdfa_metrics', 'Disabled')
    set_option('ttp_rdfsys_metrics', 'Disabled')
    set_option('ttp_rdfdir_metrics', 'Disabled')
    set_option('ttp_rdfdev_metrics', 'Disabled')
    set_option('ttp_rdfgrp_metrics', 'Disabled')
  end

  def set_default_options(interval)
    set_option('dmn_symmids', full_sid)
    set_option('dmn_run_ttp', 'Enabled')
    set_option('ttp_collection_interval', interval)
    set_option('ttp_symmids', full_sid)
    set_option('ttp_tp_dev_metrics', 'Enabled')
    set_option('sync_vp_data', 'Enabled')
  end

  def start(interval)
    info "starting stordaemon for sid #{full_sid}, collect interval #{interval}"
    set_default_options(interval)
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

class InitGrp
  attr_accessor :name
  attr_accessor :wwns

  def initialize(symm, name)
    @symm = symm
    @name = name
    @wwns = []
  end

  def fetch_wwns
    @wwns = []
    doc = @symm.exec_sym("symaccess show #{name} -type initiator")
    doc.elements.each('SymCLI_ML/Symmetrix/Initiator_Group/Group_Info/Initiators/wwn') do |w|
      @wwns << w.text
    end
  end

  def rmall
    @wwns.each do |w|
      info "removing #{w} from #{name}"
      cmd = "symaccess -name #{name} -type initiator -wwn #{w} remove"
      @symm.exec_sym(cmd)
    end
  end

  def destroy
    rmall
    @symm.exec_sym()
  end
end

class View
  attr_accessor :ig
  attr_accessor :sg
  attr_accessor :pg
  attr_accessor :name

  def initialize(symm, name, ig_name, sg, pg)
    @symm = symm
    @name = name
    @ig = InitGrp.new(symm, ig_name)
    @sg = sg
    @pg = pg
  end
end

class AutoProvision
  def initialize(symm)
    @symm = symm
    @views = []
  end

  def create_ig(name)
  end

  def create_sg(name)
  end

  def create_pg(name)
  end

  def create_view(ig, sg, pg)
  end

  def fetch_views
    @views = []
    doc = @symm.exec_sym("symaccess list view")
    doc.elements.each('SymCLI_ML/Symmetrix/Masking_View/View_Info') do |ele|
      name = ele.text('view_name')
      ig = ele.text('init_grpname')
      sg = ele.text('stor_grpname')
      pg = ele.text('port_grpname')
      view = View.new(@symm, name, ig, sg, pg)
      @views << view
    end
  end

  def list_views
    fetch_views
    puts "name".ljust(20) + "ig".ljust(20) + "pg".ljust(20) + "sg".ljust(20)
    puts '=' * 80
    @views.each do |v|
        puts v.name.ljust(20) + v.ig.name.ljust(20) + v.pg.ljust(20) + v.sg.ljust(20)
    end
  end

  def get_view_by_name(name)
    fetch_views if @views.size == 0
    @views.each do |v|
      return v if v.name == name 
    end
    return nil
  end

  def destroy_view(name)
    view = get_view_by_name(name)
    if view == nil
      info "Cannot find view name #{name}"
    end
    info "destroying view #{name} and related groups"
  end

end