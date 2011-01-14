#!/usr/bin/env ruby
#
# wp
# to read json stats from intelligenx SC
#
# Getting json data with one request. 
# Using one of the zabbix items instead of the cron job to run the script, 
# outputing the requested value, and the rest are being send with zabbix_sender
#

require "tempfile"
require "rubygems"
require "open-uri"
require "json"
require "socket"

# no fancy argument checks in zabbix scripts
# expecting 2 arguments: PORT and PARAMETER
if ARGV.length < 2
	puts "ERROR: need port and Parameter."
	exit
end

# lets get NUM_REQUESTS (do NOT confuse with NUM_SEARCHES) as our parameter, the rest will be defind in here
PORT		= ARGV[0]
PARAMETER	= ARGV[1]
PARMS 		= %w{ REQ_TOTAL_TIME_AVG NUM_SEARCHES QUEUE_LENGTH FAILED_SEARCH FREE_MEMORY USED_MEMORY }
# array of exceptions, we will sum it up later and present as one item.
SUMPARMS 	= %w{ UNKNOWN_ERROR CATEGORY_PARSER MAIN_ENGINE DISCOVERY_ENGINE }

url 		= "http://localhost:#{PORT}/lsp/stats/statusJson.jsp"
begin
	data 	= open(url, "UserAgent" => "Ruby-Wget").read
rescue
	puts "ERROR connecting."
	exit
end

result 		= JSON.parse(data)
tempFile 	= Tempfile.new('zabbix')
host		= Socket.gethostbyname(Socket.gethostname).first

# adding all teh values to a tmp file
PARMS.each do |parms|
	value	= result["#{parms}"]
	tempFile << "#{host} bse.#{parms.downcase} #{value.split(/\ /)[0]}\n" unless value == nil
	value 	= nil
end

# we need to sum all the exeptions
@sum		= 0
SUMPARMS.each do |i|
	exep	= result["#{i}"]
	@sum	= @sum + exep.to_i
	# add to the tmp file, and no \n
end

tempFile << "#{host} bse.total_exeptions #{@sum}" unless @sum == nil
tempFile.flush
# for debuging:
# system("cat #{tempFile.path}") 
cmd = "zabbix_sender -z zabbix.util.pages -i #{tempFile.path}"
system("#{cmd} 1>/dev/null 2>&1")
tempFile.close
# the files will be deleted when script exits, though we could .delete

# here is our requested value:
ourvalue		= result["#{PARAMETER}"]
puts ourvalue unless ourvalue == nil
