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
      line = line.unicode_normalize(:nfc)
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
      @corr[x] = a.to_set
      @special[x] = special
    }
  end

  def merge!(t)
    # merge the second Tr object t into myself
    if self.from!=t.from or self.to!=t.to then die("from/to languages don't match in merging Tr objects") end
    self.corr.merge!(t.corr)
    self.special.merge!(t.special)
  end

  def match(x,y)
    # Given the word x in the "from" language and y in the "to" language, see if they match up.
    # Return [match,score].
    # match = boolean, score=0 if no match, 1 if a match but not marked special, 2 if a match and marked special.
    # Before calling this repeatedly for a given x, it will be more efficient to check whether x exists as a key.
    # Rather than iterating over all y in a lengthy text, it will be more efficient to use a concordance.
    # The words x and y should already have been lexicalized before calling this method, using the data in the .lemmas file.
    if not (self.corr.has_key?(x) and self.corr[x].include?(y)) then return [false,0] end
    if self.special.has_key?(x) then return [true,2] else return [true,1] end
  end

  def match_sets(set1,set2)
    # Takes a set of words in one language and a set of words in the other language as inputs.
    # If any of the words match up, returns [true,score,m1,m2], where m1 and m2 are the subsets of set1 and set2 that matched something.
    best_score = 0
    m1 = []
    m2 = []
    set1.each { |w1|
      set2.each { |w2|
        m,score = self.match(w1,w2)
        if m then m1.push(w1); m2.push(w2) end
        if score>best_score then best_score=score end
      }
    }
    return [best_score>0,best_score,m1,m2]
  end

  def length
    return self.corr.length
  end

  attr_reader :h,:from,:to,:corr,:special

end
