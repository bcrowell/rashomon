#!/bin/ruby
# coding: utf-8

require 'optparse'
require 'json'
require 'set'

def main()
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
  default_options = { 
    'uniq_filter'=>lambda {|x| Math::exp(x)},
    'n_tries_max'=>1000,
    'n_matches'=>5,
    'max_freq'=>0.044, # In Pope's translation of the Iliad, "arms" has this frequency and is the most frequent word that looks at all useful.
    'kernel'=>0.1,
    'cut_off'=>0.2, # Used in improve_matches_using_light_cone(). Points with normalized scores below this are discarded. Making this too high causes gaps.
    'self_preservation'=>0.2,
    'max_v'=>0.2, # Used in uv_fourier(). If |v| is bigger than this, we throw out the point.
    'short_wavelengths'=>2.0 # Used in uv_fourier(). Higher values cause shorter wavelengths to be taken into account
  }
  non_default_options = { 
  }
  options = default_options.merge(non_default_options)
  match_low_level(s,ff,word_index,options)
end

def match_low_level(s,f,word_index,options)
  nx,ny = [s[0].length,s[1].length]
  best = match_independent(s,f,word_index,options)
  # ... best = array of elements that look like [i,j,score,why]
  1.upto(2) { |i|
    # Iterating more than once may give a slight improvement, but doing it many times, like 10, causes gaps and still doesn't get rid of outliers.
    best = improve_matches_using_light_cone(best,nx,ny,options)
  }
  fourier,best = uv_fourier(best,nx,ny,options)
  write_csv_file("a.csv",best,1000,nx,ny,fourier)
end

def uv_fourier(best,nx,ny,options)
  # u=(x+y)/2, v=y-x ... both range from 0 to 1
  # x=u-v/2, y=u+v/2
  kernel = options['kernel']
  max_v = options['max_v']
  short_wavelengths = options['short_wavelengths']
  uv = []
  best.each { |match|
    i,j,score,why = match
    x = i/nx.to_f
    y = j/ny.to_f
    u,v = xy_to_uv(x,y)
    if v.abs>max_v then next end
    uv.push([u,v,score])
  }
  m = (short_wavelengths/kernel).round # highest fourier terms; cut off any feature with a half-wavelength smaller than 1/kernel
  if m<1 then m=1 end
  # Calculate a discrete approximation to the function, with n evenly spaced points.
  discrete = []
  n_disc = 4*m+1 # The factor of 4 is semi-arbitrary.
  du = 1/(n_disc-1).to_f
  0.upto(n_disc-1) { |i|
    u = i*du
    sum0 = 0.0
    sum1 = 0.0
    uv.each { |p|
      uu,vv,score = p
      weight = score*Math::exp(-4.0*(uu-u).abs/kernel) # The factor of 4 is semi-arbitrary.
      sum0 += weight
      sum1 += weight*vv
    }
    avg = sum1/sum0 # weighted average of v values
    discrete.push(avg)
  }
  # Find the Fourier series of the discrete approximation, period P=2, treating it as an odd function on [-1,1].
  # https://en.wikipedia.org/wiki/Fourier_series
  b = [] # sine coefficients
  0.upto(m) { |j|
    b.push(0.0)
    u = 0.0
    discrete.each { |v|
      b[-1] += 2*v*Math::sin(Math::PI*j*u)*du # factor of 2 is because we have the fictitious [-1,0].
      if j==1 then
        #if Math::sin(Math::PI*j*u)<0.0 then die("negative sine, j=#{j}, du=#{du}, u=#{u}, input=#{Math::PI*j*u}") end
      end
      u = u+du
    }
  }
  print "b=#{b}\n"
  errs = []
  best.each { |match|
    i,j,score,why = match
    u,v = xy_to_uv(i/nx.to_f,j/ny.to_f)
    v_pred = evaluate_fourier(b,u)
    errs.push((v-v_pred).abs)
  }
  bad_error = find_percentile(errs,0.8)
  print "bad_error=#{bad_error}\n" # qwe
  improved = []
  best.each { |match|
    i,j,score,why = match
    u,v = xy_to_uv(i/nx.to_f,j/ny.to_f)
    v_pred = evaluate_fourier(b,u)
    if (v-v_pred).abs>bad_error+2.0/nx then next end
    improved.push(match)
  }
  return b,improved
end

def xy_to_uv(x,y)
  u=(x+y)/2.0
  v=y-x
  return [u,v]
end

def evaluate_fourier(b,x)
  # Period is 2, odd function on [-1,1].
  y = 0.0
  0.upto(b.length-1) { |i|
    y = y + b[i]*Math::sin(Math::PI*i*x)
  }
  return y
end

def improve_matches_using_light_cone(best,nx,ny,options)
  # Now we have candidates (i,j). The i and j can be transformed into (x,y) coordinates on the unit square.
  # The points consist partly of a "path" of correct matches close to the main diagonal and partly of a uniform background of false matches.
  # Now use the relationships between the points to improve the matches.
  # For speed, make an index of matches by j.
  by_j = []
  0.upto(ny-1) { |j|
    by_j.push([])
  }
  best.each { |match|
    i,j,score,why = match
    by_j[j].push(match)
  }
  # For each point (x,y), we have a "light cone" of points (x',y') such that x'-x and y'-y have the same sign.
  # If two points are both valid, then they should be inside each other's light cones.
  # Look at correlations with nearby points to get a new, improved set of scores.
  improved = []
  kernel = options['kernel']
  cut_off = options['cut_off']
  self_preservation = options['self_preservation']
  best.each { |match|
    i,j,score,why = match
    # draw a box around (i,j).
    i0 = kernel_helper(i-kernel*nx,-0.5,nx)
    i1 = kernel_helper(i+kernel*nx, 0.5,nx)
    j0 = kernel_helper(j-kernel*ny,-0.5,ny)
    j1 = kernel_helper(j+kernel*ny, 0.5,ny)
    # The box contains four quadrants, two inside the light cone and two outside. Sum over scores
    # in the quadrants, with weights of +1 and -1. The result averages to zero if we're just in a region of background.
    # The edges of the box can go outside the unit square, which is OK -- see below.
    sum = 0.0
    j0.upto(j1) { |j_other|
      by_j[j_other%ny].each { |match_other|
        # Mod by ny means we wrap around at edges; this is kind of silly, but actually makes sense statistically for bg 
        # and in terms of the near-diagonal path of good matches. Similar idea for logic involving wrap and nx below.
        i_other,dup,score_other,why_other = match_other
        i_other_unwrapped = nil
        (-1).upto(1) { |wrap|
          ii = i_other+wrap*nx
          if i0<=ii and ii<=i1 then i_other_unwrapped=ii end
        }
        if i_other_unwrapped.nil? then next end
        sign = (i_other <=> i)*(j_other <=> j) # +1 if inside light cone, -1 if outside, 0 if on boundary
        sum = sum + score_other*sign
      }
    }
    sum = sum + self_preservation*score # Otherwise an isolated point gets a score of zero. But don't preserve outliers too much, either.
    joint = score*sum
    if joint<0 then next end
    joint = Math::sqrt(joint)
    improved.push([i,j,joint,why])
  }
  improved.sort! {|a,b| b[2] <=> a[2]} # sort in decreasing order by score
  best_score = improved[0][2]
  improved = improved.select {|match| match[2]>=cut_off*best_score}.map {|match| [match[0],match[1],match[2]/best_score,match[3]]}
  0.upto(options['n_matches']-1) { |k|
    i,j,score,why = improved[k]
    if i.nil? or j.nil? then next end
    x,y = [i/nx.to_f,j/ny.to_f]
    print "x,y=#{x},#{y}\n\n"
    print "  correlation score=#{score} why=#{why}\n\n\n---------------------------------------------------------------------------------------\n"
  }
  write_csv_file("a.csv",improved,1000,nx,ny,nil)
  return improved
end

def kernel_helper(i,d,n)
  ii = (i+d).round
  if ii==i and d<0.0 then ii=i-1 end
  if ii==i and d>0.0 then ii=i+1 end
  return ii
end

def match_independent(s,f,word_index,options)
  # s[0] and s[1] are arrays of sentences; f[0] and f[1] look like {"the"=>15772,"and"=>7138],...}
  # word_index[...] is word index, looks like {"bestowed": {165,426,3209,11999},...}, where the value is a set of integers
  # Returns array of elements that look like [i,j,score,why].
  max_freq = options['max_freq'] # highest frequency that is interesting enough to provide any utility
  uniq = [[],[]] # uniqueness score for each sentence
  0.upto(1) { |i|
    0.upto(s[i].length) { |j|
      combine = lambda {|a| sum_weighted_to_highest(a)}
      score = uniqueness(s[i][j],f[i],f[1-i],combine,max_freq)
      uniq[i].push(score)
    }
  }
  ii,max_score = greatest(uniq[0])
  median_score = find_median(uniq[0])
  pct = find_percentile(uniq[0],0.99)
  print "scores: max=#{max_score}, median=#{median_score} pct=#{pct}\n"
  cand = [[],[]] # list of unique-looking sentences in each text
  wt = [[],[]]
  0.upto(1) { |i|
    wt[i] = weighted_tree(uniq[i],nil,options['uniq_filter'])
  }

  best = []
  ntries = [options['n_tries_max'],s[0].length].min
  tried = {}
  1.upto(ntries) { |t|
    i = choose_randomly_from_weighted_tree(wt[0],tried)
    if tried.has_key?(i) then next end
    tried[i] = 1
    j,score,why = best_match(s[0][i],f[0],s[1],f[1],word_index[1],max_freq)
    if score.nil? then next end
    best.push([i,j,score,why])
  }
  best.sort! {|a,b| b[2] <=> a[2]} # sort in decreasing order by score
  if false
  0.upto(options['n_matches']-1) { |k|
    i,j,score,why = best[k]
    if i.nil? or j.nil? then next end
    x,y = [i/s[0].length.to_f,j/s[1].length.to_f]
    print "#{s[0][i]}\n\n#{s[1][j]} x,y=#{x},#{y}\n\n"
    print "  correlation score=#{score} why=#{why}\n\n\n---------------------------------------------------------------------------------------\n"
  }
  end
  write_csv_file("a.csv",best,100,s[0].length,s[1].length,nil)
  return best
end

def uniqueness(s,freq,other,combine,max_freq)
  a = []
  to_words(s).to_set.each { |word|
    if not other.has_key?(word) then next end # optional heuristic: a word doesn't help us if it never occurs in the other text
    f = freq[to_key(word)]
    if f>max_freq then next end
    a.push(freq_to_score(f))
  }
  return combine.call(a)
end

def freq_to_score(lambda)
  prob = 1-Math::exp(-lambda) # probability of occurrence, if lambda is the mean of the Poisson distribution
  score = -Math::log(prob)
  return score
end

def best_match(s,freq_self,text,freq,index,max_freq)
  # returns [index of best candidate,score of best candidate,why]
  w = {}
  to_words(s).to_set.each { |word|
    f = freq_self[to_key(word)]
    if f>max_freq then next end
    w[word] = freq_to_score(f)
  }
  key_words = w.keys.sort {|a,b| w[b] <=> w[a]} # from most unusual to least
  candidates = [Set[],Set[],Set[]] # single-match candidates, double-match, and triple-match
  dig = [4,key_words.length-1].min # how deep to dig down the list of key words
  0.upto(dig) { |i|
    w1 = key_words[i]
    #if index.has_key?(w1) then print "  found #{w1}, #{index[w1]}\n" else print "  didn't find #{w1}\n" end
    if not index.has_key?(w1) then next end
    m1 = index[w1]
    candidates[0] = candidates[0].union(m1)
    0.upto(i-1) { |j|
      w2 = key_words[j]
      if not index.has_key?(w2) then next end
      m2 = index[w2]
      dbl = m1 & m2 # intersection of the sets: all double matches in which j<i
      if dbl.length==0 then next end
      candidates[1] = candidates[1].union(dbl)
      0.upto(j-1) { |k|
        w3 = key_words[k]
        if not index.has_key?(w3) then next end
        m3 = index[w3]
        triple = dbl & m3 # triple matches in which k<j<i
        if triple.length==0 then next end
        candidates[2] = candidates[2].union(triple)
      }
    }
  }
  max_tries = 1000
  candidates = candidates[2].to_a.concat(candidates[1].to_a.concat(candidates[0].to_a)) # try triples, then doubles, then singles
  #if candidates.length==0 then print "  no luck, key_words=#{key_words}\n" end
  if candidates.length==0 then return [nil,nil] end
  words1 = to_words(s).to_set
  best = -9999.9
  best_c = nil
  best_why = ''
  #print "  candidates=#{candidates}\n"
  0.upto(max_tries-1) { |i|
    if i>=candidates.length then break end
    c = candidates[i]
    words2 = to_words(text[c]).to_set
    goodness,why = correl(words1.intersection(words2),words1.length,words2.length,freq_self,freq,max_freq)
    if goodness>best then best=goodness; best_c=c; best_why=why end
  }
  return [best_c,best,best_why]
end

def correl(words,len1,len2,f1,f2,max_freq)
  score = 0.0
  why = []
  words.each { |w|
    if f1[w]>max_freq or f2[w]>max_freq then next end
    score = score + freq_to_score(f1[w]) + freq_to_score(f2[w])
    why.push(w)
  }
  heuristic = 1.0
  heuristic = heuristic*words.length # don't pay attention to, e.g., the single rare word "descended" in Pope's 3-word sentence "Jove descended flood!"
  heuristic = heuristic/(len1+len2) # don't give undue preference to longer sentences, which may just have more matches because of their length
  score = score*heuristic
  return [score,why]
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

def choose_randomly_from_weighted_tree(t,used)
  max_tries = 100
  1.upto(max_tries) { |i| # try this many times, max, to find one we haven't done before
    j = choose_randomly_from_weighted_tree_recurse(t)
    if not used.has_key?(j) or i==max_tries then return j end
  }
end

def choose_randomly_from_weighted_tree_recurse(t)
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
    return choose_randomly_from_weighted_tree_recurse(b)
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

def find_percentile(x,f)
  return nil if x.empty?
  sorted = x.sort
  len = sorted.length
  i = ((len-1)*f).to_i # this could be improved as in find_median()
  return sorted[i]
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

def write_csv_file(filename,best,n,nx,ny,fourier)
  File.open(filename,'w') { |f|
    0.upto(n-1) { |k|
      if k>=n then break end
      i,j,score,why = best[k]
      if i.nil? or j.nil? then next end
      x,y = [i/nx.to_f,j/ny.to_f]
      u,v = xy_to_uv(x,y)
      if fourier.nil? then
        stuff = ""
      else
        stuff = ",#{evaluate_fourier(fourier,u)}"
      end
      f.print "#{score},#{u},#{v}#{stuff}\n"
    }
  }
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
