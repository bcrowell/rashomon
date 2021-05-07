# coding: utf-8

# Code that builds up the files in the cache directory.

def prep(file,raw_dir,cache_dir)
  if not FileTest.exist?(cache_dir) then Dir.mkdir(cache_dir) end
  do_preprocess(file,raw_dir,cache_dir)
  do_freq(file,cache_dir,false)
  do_freq(file,cache_dir,true)
  do_index(file,cache_dir)
end

def do_freq(file,cache_dir,is_by_lemma)
  if is_by_lemma then
    infile = File.join(cache_dir,file+".lemmas")
    outfile = File.join(cache_dir,file+".freq_lem")
    print "preprocessing file #{file} for word frequencies by lemma...\n"
  else
    infile = File.join(cache_dir,file+".json")
    outfile = File.join(cache_dir,file+".freq")
    print "preprocessing file #{file} for word frequencies...\n"
  end
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  if FileTest.exist?(outfile) and File.mtime(outfile)>File.mtime(infile) then return end
  s = JSON.parse(slurp_file(infile))
  freq = {}
  s.each { |sentence|
    if is_by_lemma then
      words = sentence.map { |ww| ww[1] }
    else
      words = to_words(sentence)
    end
    words.each { |word|
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
    paragraph.split(/(?<=[\.\?\;\!·])(?!\w)/) { |sentence| # the negative lookahead is to avoid split at W.E.B. DuBois; · is Greek middle dot
      s = sentence.gsub(/\A\s+/,'').gsub(/\n/,' ')
      if s.length<=1 or not s=~/\p{Letter}/ or to_words(s).length<1 then next end
      sentences.push(s)
    }
  }
  File.open(cached,'w') { |f|
    f.print JSON.pretty_generate(sentences),"\n"
  }
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
