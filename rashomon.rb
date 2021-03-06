#!/bin/ruby
# coding: utf-8

require 'optparse'
require 'json'
require 'set'

require_relative "lib/file_util"
require_relative "lib/stat"
require_relative "lib/string_util"
require_relative "lib/prep"
require_relative "lib/setup"
require_relative "lib/fourier"
require_relative "lib/weighted_tree"
require_relative "lib/filter_matches"
require_relative "lib/top_level"
require_relative "lib/text"
require_relative "lib/tr"

def do_match(files,cache_dir,data_dir,tr_dir)
  t = get_texts(files,cache_dir,data_dir)
  options = set_up_options({})
  match_low_level(t,options,tr_dir)
end

def match_low_level(t,options,tr_dir)
  bilingual = (t[0].language!=t[1].language)
  nx,ny = [t[0].s.length,t[1].s.length]
  best = match_independent(t,options,tr_dir)
  display_matches(t,best,nx,ny,options)
  # ... best = array of elements that look like [i,j,score,why]
  1.upto(2) { |i|
    # Iterating more than once may give a slight improvement, but doing it many times, like 10, causes gaps and still doesn't get rid of outliers.
    if bilingual then print "not using light cone improvement, not yet implemented for biligual\n"; next end
    best = improve_matches_using_light_cone(best,nx,ny,options)
  }
  fourier,best = uv_fourier(best,nx,ny,options)
  write_csv_file("a.csv",best,1000,nx,ny,fourier)
end

def match_independent(t,options,tr_dir)
  # Find sentences that seem to match, treating all probabilities as independent and not using information about one match to influence another.
  # Matches are assigned a score based on whether the two sentences both contain some of the same uncommon words.
  # Returns array of elements that look like [i,j,score,why].
  bilingual = (t[0].language!=t[1].language)
  use_lem = bilingual
  # ... look for matching lemmatized forms rather than matching inflected forms
  max_freq = options['max_freq'] # highest frequency that is interesting enough to provide any utility
  tr = nil
  if bilingual then
    tr = read_tr(tr_dir) # This is sloppy, just assumes that every tr file goes from Greek to English,	so they	can all	be merged.
    print "Read tr files totaling #{tr.length} entries\n"
  end
  uniq = [[],[]] # uniqueness score for each sentence
  0.upto(1) { |i|
    0.upto(t[i].length-1) { |j|
      combine = lambda {|a| sum_weighted_to_highest(a)}
      other_text = t[1-i]
      if use_lem then f=t[i].f_lem; f2=other_text.f_lem else f=t[i].f; f2=other_text.f end
      s = t[i].sentence_comparison_form(j,use_lem)
      score = uniqueness(s,f,f2,combine,max_freq,bilingual,tr)
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
    s = t[0].sentence_comparison_form(i,use_lem)
    if use_lem then f=t[0].f_lem; f2=t[1].f_lem else f=t[0].f; f2=t[1].f end
    j,score,why = best_match(t[0],s,f,f2,t[1],max_freq,use_lem,bilingual,tr)
    if score.nil? then next end
    if score.nan? then die("score is NaN") end
    best.push([i,j,score,why])
  }
  best.sort! {|a,b| b[2] <=> a[2]} # sort in decreasing order by score
  write_csv_file("a.csv",best,100,t[0].length(),t[1].length(),nil)
  return best
end

def uniqueness(s,freq,other,combine,max_freq,bilingual,tr)
  a = []
  s.to_set.each { |word|
    if (not bilingual) and (not other.has_key?(word)) then next end # optional heuristic: a word doesn't help us if it never occurs in the other text
    f = freq[to_key(word)]
    if f>max_freq then next end
    a.push(freq_to_score(f))
  }
  return combine.call(a)
end

def best_match(myself,s,freq_self,f2,other,max_freq,use_lem,bilingual,tr)
  # returns [index of best candidate,score of best candidate,why]
  # s is the sentence we're trying to match, represented as an array of words; if use_lem is true, these are supposed to be in lemmatized form
  # freq_self is the list of word frequences, which should be keyed be lemmas if use_lem is true
  if bilingual then
    langs = [myself.language,other.language]
  else
    langs = nil
  end
  w = {}
  s.to_set.each { |word|
    f = freq_self[to_key(word)]
    if f>max_freq then next end
    w[word] = freq_to_score(f)
  }
  key_words = w.keys.sort {|a,b| w[b] <=> w[a]} # from most unusual to least
  candidates = [Set[],Set[],Set[]] # single-match candidates, double-match, and triple-match
  dig = [4,key_words.length-1].min # how deep to dig down the list of key words
  0.upto(dig) { |i|
    w1 = kludge_tr(key_words[i],bilingual,tr,langs)
    if not f2.has_key?(w1) then next end
    m1 = other.index(w1,use_lem)
    candidates[0] = candidates[0].union(m1)
    0.upto(i-1) { |j|
      w2 = kludge_tr(key_words[j],bilingual,tr,langs)
      if not f2.has_key?(w2) then next end
      m2 = other.index(w2,use_lem)
      dbl = m1 & m2 # intersection of the sets: all double matches in which j<i
      if dbl.length==0 then next end
      candidates[1] = candidates[1].union(dbl)
      0.upto(j-1) { |k|
        w3 = kludge_tr(key_words[k],bilingual,tr,langs)
        if not f2.has_key?(w3) then next end
        m3 = other.index(w3,use_lem)
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
  words1 = s.to_set
  best = -9999.9
  best_c = nil
  best_why = ''
  0.upto(max_tries-1) { |i|
    if i>=candidates.length then break end
    c = candidates[i]
    words2 = other.sentence_comparison_form(c,use_lem).to_set
    if not bilingual then
      m1 = words1.intersection(words2)
      m2 = m1
    else
      matches,score,m1,m2 = tr.match_sets(words1,words2)
    end
    goodness,why = correl(m1,m2,words1.length,words2.length,freq_self,f2,max_freq)
    if goodness>best then best=goodness; best_c=c; best_why=why end
  }
  return [best_c,best,best_why]
end

def correl(words1,words2,len1,len2,f1,f2,max_freq)
  # In the monolingual case, words1 and words2 are going to be the same.
  score = 0.0
  why = []
  words1.each { |w|
    if f1[w]>max_freq then next end
    score = score + freq_to_score(f1[w])
    why.push(w)
  }
  words2.each { |w|
    if f2[w]>max_freq then next end
    score = score + freq_to_score(f2[w])
    why.push(w)
  }
  heuristic = 1.0
  heuristic = heuristic*Math::sqrt((words1.length*words2.length).to_f)
  # ... Don't pay attention to, e.g., the single rare word "descended" in Pope's 3-word sentence "Jove descended flood!"
  heuristic = heuristic/(len1+len2) # don't give undue preference to longer sentences, which may just have more matches because of their length
  score = score*heuristic
  return [score,why]
end

def kludge_tr(word,bilingual,tr,langs)
  if not bilingual then return word end
  # Kludge: if the tr has more than one possible correlate, just return a random choice.
  if tr.from!=langs[0] or tr.to!=langs[1] then die("languages don't match") end
  return tr.corr[word].to_a.sample # The sample method picks a random element
end

def display_matches(texts,matches,nx,ny,options)
  n = [options['n_matches'],matches.length].min-1
  0.upto(n) { |k|
    i,j,score,why = matches[k]
    if score.nil? then die("score is nil") end
    if score.nan? then die("score is NaN") end
    if i.nil? or j.nil? then next end
    x,y = [i/nx.to_f,j/ny.to_f]
    print "x,y=#{x},#{y}\n\n"
    print "  #{texts[0].s[i]}\n"
    print "  #{texts[1].s[j]}\n"
    print "  correlation score=#{score} why=#{why}\n\n\n---------------------------------------------------------------------------------------\n"
  }
  #write_csv_file("a.csv",matches,1000,nx,ny,nil)
end

main()
