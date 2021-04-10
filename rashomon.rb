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
  ii = []
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
    # index by word:
    infile = File.join(cache_dir,file+".index")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    ii.push(JSON.parse(slurp_file(infile)))
  }
  # make conveniently indexed frequency tables
  ff = [{},{}]
  0.upto(1) { |i|
    f[i].each { |x|
      ff[i][x[0]] = x[1]/s[i].length.to_f
    }
  }
  # JSON doesn't let you have integers as keys in a hash, so convert each entry to a set of integers
  word_index = []
  ii.each { |json_index|
    cleaned_index = {}
    json_index.keys.each { |w|
      cleaned_index[w] = json_index[w].keys.map {|x| x.to_i}.to_set
    }
    word_index.push(cleaned_index)
  }
  match_with_recursion(s,ff,word_index,3,10)
end

def match_with_recursion(s,f,word_index,m,n)
  # s[0] and s[1] are arrays of sentences; f[0] and f[1] look like {"the"=>15772,"and"=>7138],...}
  # word_index[...] is word index, looks like {"bestowed": {165,426,3209,11999},...}, where the value is a set of integers
  # m = number of pieces
  # n = number of trials
  uniq = [[],[]] # uniqueness score for each sentence
  0.upto(1) { |i|
    0.upto(s[i].length) { |j|
      #combine = lambda {|a| sum_of_array(a)}
      combine = lambda {|a| sum_weighted_to_highest(a)}
      score = uniqueness(s[i][j],f[i],f[1-i],combine)
      uniq[i].push(score)
    }
  }
  ii,max_score = greatest(uniq[0])
  median_score = find_median(uniq[0])
  print "scores: max=#{max_score}, median=#{median_score}\n"
  cand = [[],[]] # list of unique-looking sentences in each text
  wt = [[],[]]
  0.upto(1) { |i|
    #filter = lambda {|x| Math::exp([x,1.0].max)}
    #filter = lambda {|x| [[x,10].max,30].min}
    #filter = lambda {|x| x}
    filter = lambda {|x| Math::exp(x)}
    wt[i] = weighted_tree(uniq[i],nil,filter)
  }
  0.upto(10) { |x|
    i = choose_randomly_from_weighted_tree(wt[0])
    print "i=#{i}, score=#{uniq[0][i]}, #{s[0][i]}\n"
    j,score = best_match(s[0][i],f[0],s[1],f[1],word_index[1])
    if not j.nil? then print "  best match: j=#{j} #{s[1][j]}, correlation score=#{score}\n" end
  }
end

def uniqueness(s,freq,other,combine=lambda {|a| sum_of_array(a)})
  a = []
  to_words(s).to_set.each { |word|
    if not other.has_key?(word) then next end # optional heuristic: a word doesn't help us if it never occurs in the other text
    a.push(freq_to_score(freq[to_key(word)]))
  }
  return combine.call(a)
end

def freq_to_score(lambda)
  prob = 1-Math::exp(-lambda) # probability of occurrence, if lambda is the mean of the Poisson distribution
  score = -Math::log(prob)
  return score
end

def best_match(s,freq_self,text,freq,index)
  # returns [index of best candidate,score of best candidate]
  w = {}
  to_words(s).to_set.each { |word|
    w[word] = freq_to_score(freq_self[to_key(word)])
  }
  key_words = w.keys.sort {|a,b| w[b] <=> w[a]} # from most unusual to least
  candidates = [Set[],Set[],Set[]] # single-match candidates, double-match, and triple-match
  dig = [4,key_words.length-1].min # how deep to dig down the list of key words
  0.upto(dig) { |i|
    w1 = key_words[i]
    if not index.include?(w1) then next end
    m1 = index[w1]
    candidates[0].union(m1)
    0.upto(i-1) { |j|
      w2 = key_words[j]
      if not index.include?(w2) then next end
      m2 = index[w2]
      dbl = m1 & m2 # intersection of the sets: all double matches in which j<i
      if dbl.length==0 then next end
      candidates[1].union(dbl)
      0.upto(j-1) { |k|
        w3 = key_words[k]
        if not index.include?(w3) then next end
        m3 = index[w3]
        triple = dbl & m3 # triple matches in which k<j<i
        if triple.length==0 then next end
        candidates[2].union(triple)
      }
    }
  }
  max_tries = 1000
  candidates = candidates[2].union(candidates[1].union(candidates[0])) # try triples, then doubles, then singles
  if candidates.length==0 then print("no candidates found for #{s}\n"); return [nil,nil] end
  words1 = to_words(s).to_set
  best = -9999.9
  best_c = nil
  0.upto(max_tries-1) { |i|
    c = candidates[i]
    words2 = to_words(text[c]).to_set
    goodness = correl(words1.intersection(words2),freq_self,freq)
    if goodness>best then best=goodness; best_c=c end
  }
  return [best_c,best]
end

def correl(words,f1,f2)
  score = 0.0
  words.each { |w|
    score = score + freq_to-score(f1) + freq_to-score(f2)
  }
  return score
end

def sum_weighted_to_highest(a)
  a = a.sort {|p,q| q<=>p} # sort in reverse order
  sum = 0.0
  0.upto(4) { |i|
    if i>=a.length then break end
    sum = sum + a[i]/(i+3.0)
  }
  return sum
end

def choose_randomly_from_weighted_tree(t)
  if t[0] then
    # leaf node
    return t[2]
  else
    b0,b1 = t[2][0],t[2][1] # two branches
    p = b0[1]/(b0[1]+b1[1]) # probability of lower-probability branch; this avoids probability rounding to zero
    r = rand()
    if r<p then b=b0 else b=b1 end
    stats = t[3]
    #print "#{r}, #{p}, #{r<p}, weights=#{b0[1]}, #{b1[2]}, n=#{stats['n']}, depth=#{stats['depth']}\n"
    return choose_randomly_from_weighted_tree(b)
  end
end

def weighted_tree(w,labels,filter=lambda {|x| return x})
  # create a binary tree structure for use in randomly choosing elements
  # w is an array of floats giving the weights
  # labels is an array of integers or other keys to be used as labels; if nil, then as a convenience we create a list of integer labels
  # filter is used to change weights in any desired nonlinear way; should be positive and nondecreasing
  # each leaf node looks like
  #   [true, weight, label,            stats]
  # each non-lead node looks like
  #   [false,weight, [branch1,branch2],stats]
  eps = 1.0e-6
  if labels.nil? then
    labels = []
    0.upto(w.length) { |i|
      labels[i] = i
    }
  end
  if w.length==1 then
    return [true,filter.call(w[0]),labels[0],{'n'=>1,'depth'=>0}]
  end
  median = find_median(w)
  w0 = []
  l0 = []
  w1 = []
  l1 = []
  near_median_count = 0
  0.upto(w.length-1) { |i|
    near_median = (w[i]-median).abs<eps
    if near_median then near_median_count += 1 end
    if w[i]<median-eps or (near_median and (w0.length==0 or (w1.length!=0 and near_median_count%2==0))) then
      w0.push(w[i])
      l0.push(labels[i])
    else
      w1.push(w[i])
      l1.push(labels[i])
    end
  }
  if w0.length==0 or w1.length==0 then die("error in weighted_tree") end
  #print "recursing, w0 has length=#{w0.length}\n"
  b0 = weighted_tree(w0,l0,filter)
  b1 = weighted_tree(w1,l1,filter)
  depth = [b0[3]['depth'],b1[3]['depth']].max+1
  result = [false,b0[1]+b1[1],[b0,b1],{'n'=>w.length,'depth'=>depth}]
  #if depth<=3 then print result,"\n" end
  return result
end

def find_median(x) # https://stackoverflow.com/a/14859546
  return nil if x.empty?
  sorted = x.sort
  len = sorted.length
  return (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
end

def sum_of_array(a)
  return a.inject(0){|sum,x| sum + x } # https://stackoverflow.com/questions/1538789/how-to-sum-array-of-numbers-in-ruby
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
  do_preprocess(file,raw_dir,cache_dir)
  do_freq(file,cache_dir)
  do_index(file,cache_dir)
end

def do_index(file,cache_dir)
  infile = File.join(cache_dir,file+".json")
  outfile = File.join(cache_dir,file+".index")
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  if FileTest.exist?(outfile) and File.mtime(outfile)>File.mtime(infile) then return end
  print "preprocessing file #{file} for indexing by word...\n"
  s = JSON.parse(slurp_file(infile))
  index = {}
  i = 0
  0.upto(s.length-1) { |i|
    sentence = s[i]
    to_words(sentence).each { |word|
      w = to_key(word)
      add_in = Hash.new
      add_in[i] = 1
      if index.has_key?(w) then index[w].merge!(add_in) else index[w] = add_in end
    }
  }
  File.open(outfile,'w') { |f|
    f.print JSON.pretty_generate(index),"\n"
  }
end

def do_freq(file,cache_dir)
  infile = File.join(cache_dir,file+".json")
  outfile = File.join(cache_dir,file+".freq")
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  if FileTest.exist?(outfile) and File.mtime(outfile)>File.mtime(infile) then return end
  print "preprocessing file #{file} for word frequencies...\n"
  s = JSON.parse(slurp_file(infile))
  freq = {}
  s.each { |sentence|
    to_words(sentence).each { |word|
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
  print "preprocessing file #{file} for sentences...\n"
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
      s = sentence.gsub(/\A\s+/,'').gsub(/\n/,' ')
      if s.length<=1 or not s=~/\p{Letter}/ or to_words(s).length<1 then next end
      sentences.push(s)
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
  t.gsub!(/[—-]/,' ')
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
