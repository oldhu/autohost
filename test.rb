require './hosts'

hosts = Hosts.new

hosts.host1.exec('ifconfig eth0')
hosts.exec('ifconfig eth0 mtu 9000')
hosts.exec('ifconfig eth0 mtu 1500')