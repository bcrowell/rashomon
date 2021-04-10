#!/bin/ruby
# coding: utf-8

require 'optparse'
require 'json'
require 'set'

def main()
  options = opts()
  raw_dir = "raw"
  cache_dir = "cache"

  if ARGV.length<2 then die("supply two arguments, e.g., pope_iliad and lang_iliad") end
  0.upto(1) { |i|
    prep(ARGV[i],raw_dir,cache_dir)
  }
  do_match(ARGV,cache_dir)

end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end

def do_match(files,cache_dir)
  # s[0] and s[1] are arrays of sentences; f[0] and f[1] look like [["the",15772],["and",7138],...]
  s = []
  f = []
  0.upto(1) { |i|
    file = files[i]
    # sentences:
    infile = File.join(cache_dir,file+".json")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    s.push(JSON.parse(slurp_file(infile)))
    # frequency table:
    infile = File.join(cache_dir,file+".freq")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    f.push(JSON.parse(slurp_file(infile)))
  }
  # make conveniently indexed frequency tables
  ff = [{},{}]
  0.upto(1) { |i|
    f[i].each { |x|
      ff[i][x[0]] = x[1]/s[i].length.to_f
    }
  }
  match_with_recursion(s,ff,3,10)
end

def match_with_recursion(s,f,m,n)
  # s[0] and s[1] are arrays of sentences; f[0] and f[1] look like {"the"=>15772,"and"=>7138],...}
  # m = number of pieces
  # n = number of trials
  uniq = [[],[]] # uniqueness score for each sentence
  0.upto(1) { |i|
    0.upto(s[i].length) { |j|
      uniq[i].push(uniqueness(s[i][j],f[i],f[1-i]))
    }
  }
  ii,score = greatest(uniq[0])
  print "ii=#{ii}, score=#{score}, #{s[0][ii]}\n"
  cand = [[],[]] # list of unique-looking sentences in each text
end

def uniqueness(s,freq,other)
  score = 0
  to_words(s).to_set.each { |word|
    if not other.has_key?(word) then next end # optional heuristic: a word doesn't help us if it never occurs in the other text
    lambda = freq[to_key(word)] # mean of Poisson distribution
    prob = 1-Math::exp(-lambda) # probability of occurrence
    score = score - Math::log(prob)
  }
  return score
end

def to_words(sentence)
  if sentence.nil? then return [] end
  x = sentence.split(/[^\p{Letter}]+/)  # won't handle "don't"
  x = x.map { |word| to_key(word)}
  x.delete('')
  return x
end

def to_key(word)
  return word.unicode_normalize(:nfkc).downcase
end

def greatest(a)
  g = -2*(a[0].abs)
  ii = nil
  0.upto(a.length) { |i|
    if not a[i].nil? and a[i]>g then ii=i; g=a[i] end
  }
  return [ii,g]
end

def prep(file,raw_dir,cache_dir)
  if not FileTest.exist?(cache_dir) then Dir.mkdir(cache_dir) end
  print "preprocessing file #{file}...\n"
  do_preprocess(file,raw_dir,cache_dir)
  do_freq(file,cache_dir)
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
      w = to_key(word)
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
    paragraph.split(/(?<=[\.\?\;\!])(?!\w)/) { |sentence| # the negative lookahead is to avoid splitting at W.E.B. DuBois
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
  #   . etc. inside quotation marks
  t.gsub!(/—/,' ')
  t.gsub!(/\./,'aaPERIODaa')
  t.gsub!(/\?/,'aaQUESTIONMARKaa')
  t.gsub!(/\;/,'aaSEMICOLONaa')
  t.gsub!(/\!/,'aaEXCLaa')
  t.gsub!(/[[:punct:]]/,'')
  t.gsub!(/aaPERIODaa/,'.')
  t.gsub!(/aaQUESTIONMARKaa/,'?')
  t.gsub!(/aaSEMICOLONaa/,';')
  t.gsub!(/aaEXCLaa/,'!')
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
