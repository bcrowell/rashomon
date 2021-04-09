#!/bin/ruby

require 'optparse'

def main()
  options = opts()
  data_dir = "raw"

  if ARGV.length<1 then die("supply an argument") end
  file = ARGV[0]

end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end

def opts()
  # https://ruby-doc.org/stdlib-2.4.2/libdoc/optparse/rdoc/OptionParser.html
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: example.rb [options]"
  
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      options[:verbose] = v
    end
  end.parse!
  return options
end

main()
