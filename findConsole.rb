#!/usr/bin/env ruby
#
# Looking for a ACS to which a host connected to.
# wp 2009

require "snmp"

# function for usage
def usage
	print <<USAGE

 To find which ACS a host connected to.
 Script will look for a string (first argument) on across all of the ACSs)
 Example: findConsole.rb web0

USAGE
	exit
end 

# Expecting one argument
usage unless ARGV.length == 1
lookfor 	= ARGV.to_s
community 	= "***"
oid 		= "1.3.6.1.4.1.2925.4.3.1.1.3"

# generating a list of the ACSs
row 	= [ "a", "b" ]
rack 	= (1..7).to_a
acs 	= row.collect { |r| rack.collect { |ra| "sddc-acs-#{r}#{ra}01.mgmt.pages" } }.flatten

for con in acs
	print "\tLooking on #{con}.\t"
	# we need to define an array to store lables.
	b 	= []
	# collecting lables from each port on ACS with snmpwalk
	begin
		snmp 	= SNMP::Manager.new(:Host => con, :Community => community)
		snmp.walk(oid) { |r| b << r.value.reject {|l| l =~ /0E-|^-/} }
	rescue
		puts "\nError: can't connect to #{con}, skipping"
		next
	end
	
	# trying to match our string to lables on this ACS 
	mylable 	= b.flatten.find_all { |lable| lable =~ Regexp.new(lookfor) }
	if mylable.length > 0
		puts "\nFound #{mylable.join(', ')} on #{con}"
	else
		puts "Nothing found."
	end
end

