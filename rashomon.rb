#!/bin/ruby
# coding: utf-8

require 'optparse'
require 'json'

def main()
  options = opts()
  raw_dir = "raw"
  cache_dir = "cache"

  if ARGV.length<1 then die("supply an argument") end
  file = ARGV[0]

  if not FileTest.exist?(cache_dir) then Dir.mkdir(cache_dir) end

  do_preprocess(file,raw_dir,cache_dir)
  do_freq(file,cache_dir)

end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end

def do_freq(file,cache_dir)
  infile = File.join(cache_dir,file+".json")
  outfile = File.join(cache_dir,file+".freq")
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  if FileTest.exist?(outfile) and File.mtime(outfile)>File.mtime(infile) then return end
  s = JSON.parse(slurp_file(infile))
  freq = {}
  s.each { |sentence|
    sentence.scan(/\p{Letter}+/) { |word|
      w = word.downcase
      if freq.has_key?(w) then freq[w]+=1 else freq[w]=1 end
    }
  }
  table = freq.sort_by{|k,v| v}.reverse
  File.open(outfile,'w') { |f|
    f.print JSON.pretty_generate(table),"\n"
  }
end

def do_preprocess(file,raw_dir,cache_dir)
  raw = File.join(raw_dir,file+".txt")
  cached = File.join(cache_dir,file+".json")
  if not FileTest.exist?(raw) then die("file #{raw} not found") end
  if FileTest.exist?(cached) and File.mtime(cached)>File.mtime(raw) then return end
  t = slurp_file(raw).unicode_normalize
  t = clean_up_text(t)
  t.gsub!(/\r\n/,"\n") # crlf to unix newline
  # clean up whitespace in and around newlines:
    t.gsub!(/\n\s+\n/,"\n\n")
    t.gsub!(/\n[ \t]+/,"\n")
    t.gsub!(/[ \t]+\n/,"\n")
  sentences = []
  t.split(/\n{2,}/) { |paragraph|
    paragraph.split(/(?<=[\.\?])(?!\w)/) { |sentence| # the negative lookahead is to avoid splitting at W.E.B. DuBois
      sentences.push(sentence.gsub(/\A\s+/,'').gsub(/\n/,' '))
    }
  }
  File.open(cached,'w') { |f|
    f.print JSON.pretty_generate(sentences),"\n"
  }
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

def clean_up_text(t)
  # eliminate all punctuation except that which can end a sentence
  # problems:
  #   for greek, should recognize ; as question mark
  #   ? and . inside quotation marks
  t.gsub!(/—/,' ')
  t.gsub!(/\./,'aaPERIODaa')
  t.gsub!(/\?/,'aaQUESTIONMARKaa')
  t.gsub!(/[[:punct:]]/,'')
  t.gsub!(/aaPERIODaa/,'.')
  t.gsub!(/aaQUESTIONMARKaa/,'?')
  t.gsub!(/\d/,'') # numbers are footnotes, don't include them
  return t
end

# returns contents or nil on error; for more detailed error reporting, see slurp_file_with_detailed_error_reporting()
def slurp_file(file)
  x = slurp_file_with_detailed_error_reporting(file)
  return x[0]
end

# returns [contents,nil] normally [nil,error message] otherwise
def slurp_file_with_detailed_error_reporting(file)
  begin
    File.open(file,'r') { |f|
      t = f.gets(nil) # nil means read whole file
      if t.nil? then t='' end # gets returns nil at EOF, which means it returns nil if file is empty
      return [t,nil]
    }
  rescue
    return [nil,"Error opening file #{file} for input: #{$!}."]
  end
end

main()
