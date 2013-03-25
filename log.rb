require 'logger'

$logger = Logger.new(STDOUT)

$logger.sev_threshold = Logger::DEBUG

$logger.formatter = proc do |severity, datetime, progname, msg|
  datestr = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{severity}\t#{datestr} -- #{msg}\n"
end

def info(str)
  $logger.info(str)
end

def debug(str)
  $logger.debug(str)
end

def error(str)
  $logger.error(str)
end

def warn(str)
  $logger.warn(str)
end