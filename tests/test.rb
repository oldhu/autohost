require './hosts'
require './sanhosts'
require './fabric'
require './symmetrix'

# hosts = Hosts.new

# hosts.host1.exec('ifconfig eth0')
# hosts.exec('ifconfig eth0 mtu 9000')
# hosts.exec('ifconfig eth0 mtu 1500')


b1 = BrocadeHost.new('b1', '10.32.32.198', 'admin', 'password')
b2 = BrocadeHost.new('b2', '10.32.32.199', 'admin', 'password')

f1 = Fabric.new
f1.add_switch(b1)
f1.add_switch(b2)

a1 = AixHost.new('a1', '10.62.36.5', 'root', 'root')
e1 = EsxHost.new('e1', "10.32.32.187", 'root', 'Emc123456')
e1.fetch_hba

s1 = SymmetrixHost.new('s1', '10.62.36.5', 'root', 'root', '056')

s1.stop_ttp
s1.clean_ttp

# f1.find_host(e1)
# f1.find_host(a1)