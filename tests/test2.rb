# start symmetrix performance daemon on aix
# start test on linux using fio
# wait for fio to stop or timeout in 10 minutes
# stop performance daemon
# download performance data

require '../hosts'
require '../symmetrix'

s1 = SymmetrixHost.new('056', '10.62.36.5', 'root', 'root', '056')

s1.stop_ttp
s1.clean_ttp
s1.start_ttp(1)

l1 = Host.new('linux', '10.32.32.166', 'root', 'password')
l1.upload('./test2_fiop', '/root')
l1.start_task('/usr/bin/fio /root/test2_fiop')
l1.wait_or_kill_task('fio', 60 * 10)

s1.stop_ttp
s1.download_ttp('./')