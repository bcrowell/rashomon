require 'json'

class Tr
  # A list of words in one language that are expected to correlate statistically with certain words in another language.
  def initialize(infile)
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    # For the syntax of the file, see tr/README.
    header = ''
    body = []
    in_header = true
    IO.foreach(infile) {|line| 
      line.gsub!(/\n$/,'') # trim trailing newline
      line.gsub!(/#.*/,'') # remove comment
      if in_header and line=='-' then 
        in_header=false
      else
        if in_header then header=header+line else body.push(line) end
      end
    }
    @h = JSON.parse(header)
    @from = @h['from']
    @to = @h['to']
    @corr = {}
    @special = {}
    body.each { |line|
      if not line=~/[[:alpha:]]/ then next end # skip blank line
      if line=~/^\s*\+\s+/ then line.gsub!(/^\s*\+\s+/,''); special=true else special=false end
      line.gsub!(/^\s+/,'') # strip leading whitespace
      line.gsub!(/\s+$/,'') # strip trailing whitespace
      a = line.split(/\s+/)
      if a.length<2 then die("line #{line} in file #{infile} contains less than two words") end
      a.each { |w|
        if w=~/[^[:alpha:]\-\']/ then die("line #{line} in file #{infile} contains a non-alphabetical character in the word #{w}") end
      }
      x = a.shift
      if @corr.has_key?(x) then die("line #{line} in file #{infile} contains the key #{x}, which is already present, mapping to #{@corr[x]}") end
      @corr[x] = a
      @special[x] = special
    }
  end

  def length
    return self.corr.length
  end

  attr_reader :h,:from,:to,:corr

end
