#!/bin/ruby
# coding: utf-8

require 'optparse'
require 'json'
require 'set'

require_relative "lib/file_util"
require_relative "lib/stat"
require_relative "lib/string_util"
require_relative "lib/prep"
require_relative "lib/fourier"
require_relative "lib/weighted_tree"
require_relative "lib/text"

def main()
  raw_dir = "raw"
  cache_dir = "cache"

  if ARGV.length<2 then die("supply two arguments, e.g., pope_iliad and lang_iliad") end
  0.upto(1) { |i|
    prep(ARGV[i],raw_dir,cache_dir)
  }
  if ARGV[0]=~/ιλιας/ or ARGV[1]=~/ιλιας/ then die("done after preprocessing, because one file is the Greek version of the Iliad") end
  do_match(ARGV,cache_dir)

end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end

def do_match(files,cache_dir)
  t = []
  0.upto(1) { |i|
    t.push(Text.new(cache_dir,files[i]))
  }
  default_options = { 
    'uniq_filter'=>lambda {|x| Math::exp(x)},
    'n_tries_max'=>1000,
    'n_matches'=>5,
    'max_freq'=>0.044, # In Pope's translation of the Iliad, "arms" has this frequency and is the most frequent word that looks at all useful.
    'kernel'=>0.1,
    'cut_off'=>0.2, # Used in improve_matches_using_light_cone(). Points with normalized scores below this are discarded. Making this too high causes gaps.
    'self_preservation'=>0.2,
    'max_v'=>0.2, # Used in uv_fourier(). If |v| is bigger than this, we throw out the point. Setting this too small won't work if one text
                  # contains extensive prefatory material or notes.
    'short_wavelengths'=>5.0 # Used in uv_fourier(). Higher values cause shorter wavelengths to be taken into account
  }
  non_default_options = { 
  }
  options = default_options.merge(non_default_options)
  match_low_level(t,options)
end

def match_low_level(t,options)
  nx,ny = [t[0].s.length,t[1].s.length]
  best = match_independent(t,options)
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
  n_disc = short_wavelengths*m+1
  du = 1/(n_disc-1).to_f
  0.upto(n_disc-1) { |i|
    u = i*du
    sum0 = 0.0
    sum1 = 0.0
    uv.each { |p|
      uu,vv,score = p
      weight = score*Math::exp(-short_wavelengths*(uu-u).abs/kernel)
      sum0 += weight
      sum1 += weight*vv
    }
    avg = sum1/sum0 # weighted average of v values
    discrete.push(avg)
  }
  b = fourier_analyze(discrete,m) # Fourier analyze on [0,1], period P=2, treating it as an odd function on [-1,1].
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

def match_independent(t,options)
  # Returns array of elements that look like [i,j,score,why].
  max_freq = options['max_freq'] # highest frequency that is interesting enough to provide any utility
  uniq = [[],[]] # uniqueness score for each sentence
  0.upto(1) { |i|
    0.upto(t[i].s.length) { |j|
      combine = lambda {|a| sum_weighted_to_highest(a)}
      score = uniqueness(t[i].s[j],t[i].f,t[1-i].f,combine,max_freq)
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
  ntries = [options['n_tries_max'],t[0].length()].min
  tried = {}
  1.upto(ntries) { |k|
    i = choose_randomly_from_weighted_tree(wt[0],tried)
    if tried.has_key?(i) then next end
    tried[i] = 1
    j,score,why = best_match(t[0].s[i],t[0].f,t[1].s,t[1].f,t[1].word_index,max_freq)
    if score.nil? then next end
    best.push([i,j,score,why])
  }
  best.sort! {|a,b| b[2] <=> a[2]} # sort in decreasing order by score
  if false
  0.upto(options['n_matches']-1) { |k|
    i,j,score,why = best[k]
    if i.nil? or j.nil? then next end
    x,y = [i/t[0].length().to_f,j/t[1].length().to_f]
    print "#{t[0].s[i]}\n\n#{t[1].s[j]} x,y=#{x},#{y}\n\n"
    print "  correlation score=#{score} why=#{why}\n\n\n---------------------------------------------------------------------------------------\n"
  }
  end
  write_csv_file("a.csv",best,100,t[0].length(),t[1].length(),nil)
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



main()
