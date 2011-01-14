#!/usr/bin/env ruby
# 
# Removes duplicate systems in spacewalk.
# 
# Make yaml file for properties exists/has right data, and PROP_FILE constant is set how you need it.
# PROP_FILE could be defined here, just make sure it's set before loading spk library.
# Execute from whereever you can interact with Spacewalk API.
# 

$: << 'lib'

require 'spk'

space = Spk::Spacewalk.new
# get system names:
system_names = space.list_systems.map { |n| n["name"] }

# Using Enumerable#inject to make a hash of name=>count out of the array, 
# default value of the hash is set to 0 so we can increment.
# picking items that appear more then once:
systems_dups = system_names.inject(Hash.new(0)) {|h,i| h[i] += 1; h}.reject { |k,v| v == 1 }

puts "No duplicates found." and exit 0 if systems_dups.empty?

systems_dups.each_key do |name|
  # Using Enumerable#sort_by to sort by last checkin time array of systems duplicate objects
  sorted_a = space.find_system("^#{name}$").sort_by {|c| c["last_checkin"].to_time}.reverse
  
  # keep user informed
  puts "\n\tSystems sorted in order of last checkin:"
  sorted_a.each do |system|
    puts "#{system["name"]} --> #{system["last_checkin"].to_time}"
  end
  
#  print "Confirm removal of the duplicate nodes. (y|yes):"
#  begin
#    Timeout::timeout(5) do
#      confirmed = STDIN.gets.chomp
#    end
#  rescue Timeout::Error
#    puts "\nTimed out waiting for response."
#    next
#  end
#  
#  puts "Won't remove dups for #{name}" and next unless confirmed.match(/^y$|^yes$/)

  # Removing the first element and delete the rest
  sorted_a.shift
  del_ids = sorted_a.map {|s| s["id"]}
  puts "Removing duplicates for #{name}..."
  space.delete_systems(del_ids)
  puts "Done."
end
