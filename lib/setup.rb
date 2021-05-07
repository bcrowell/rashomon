# coding: utf-8

# Code that reads in cached data and sets up data structures in memory.

def read_tr(tr_dir)
  # This is sloppy, just assumes that every tr file goes from Greek to English, so they can all be merged.
  tr = nil
  print "Reading tr files:...\n"
  Dir.glob( "#{tr_dir}/*.tr").each { |tr_file|
    print "  Reading #{tr_file}..."
    x = Tr.new(tr_file)
    print "found #{x.length} entries\n"
    if tr.nil? then tr=x else tr.merge!(x) end
  }
  return tr
end

def get_lemmas(file,cache_dir)
  infile = File.join(cache_dir,file+".lemmas")
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  print "reading lemmas from #{infile}\n"
  return JSON.parse(slurp_file(infile))
end

def reverse_lemmatizations(lemmas)
  # Make a one-to-many map from lemmatized forms to inflected forms found in a particular text.
  # Output is a hash of sets.
  # Input is an array of sentences, each of which is an array of words, each of which is [orig,lem,pos,other].
  rev = {}
  lemmas.each { |sentence|
    sentence.each { |word|
      orig,lem,pos,other = word
      if not rev.has_key?(lem) then rev[lem]=[] end
      rev[lem] = rev[lem].to_set.add(orig).to_a
    }
  }
  return rev
end
