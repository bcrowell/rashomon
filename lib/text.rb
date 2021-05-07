require 'json'

class Text
  def initialize(cache_dir,data_dir,file)
    # .s is an array of sentences
    # .f is a hash like {"the"=>1.8,"and"=>0.7,...}
    # .f_lem is like f, but keys are lemmatized forms
    # .lem is a data structure of lemmatizations, from the .lemmas file
    # .rev is reverse lemmatization
    # .word_index[...] is word index, looks like {"bestowed": {165,426,3209,11999},...}, where the value is a set of integers
    # .language is a language code such as "en" for English, "grc" for ancient Greek
    # sentences:
    infile = File.join(cache_dir,file+".json")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    @s = JSON.parse(slurp_file(infile))
    # frequency tables:
    n = self.length
    @f = get_freq(File.join(cache_dir,file+".freq"),n)
    @f_lem = get_freq(File.join(cache_dir,file+".freq_lem"),n)
    # index by word:
    infile = File.join(cache_dir,file+".index")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    i = JSON.parse(slurp_file(infile))
    # JSON doesn't let you have integers as keys in a hash, so convert each entry to a set of integers
    @word_index = {}
    i.keys.each { |w|
      @word_index[w] = i[w].keys.map {|x| x.to_i}.to_set
    }
    # lemmatization-related stuff:
    @lem = get_lemmas(file,cache_dir)
    @rev = reverse_lemmatizations(@lem) # a hash of sets
    # metadata:
    infile = File.join(data_dir,file+".meta")
    if not FileTest.exist?(infile) then die("file #{infile} not found") end
    meta = JSON.parse(slurp_file(infile))
    @language = meta['language']
  end

  attr_reader :s,:f,:word_index,:language,:lem,:rev,:f_lem

  def length()
    return @s.length()
  end

  def sentence_comparison_form(i,lemmatize)
    # If lemmatize is false, return the unlemmatized ith sentence as an array of words.
    # If lemmatize is true, do this using the lemmatized words.
    if lemmatize then
      if self.lem[i].nil? then die("i=#{i}, self.lem.length=#{self.lem.length}") end
      return self.lem[i].map { |w| w[1]}
    else
      return to_words(self.s[i])
    end
  end

  def index(word,use_lem)
    # returns a set of sentence numbers
    # If use_lem is true, then word is assumed to be lemmatized.
    if use_lem then
      r = self.rev # hash of sets
      if not r.has_key?(word) then return Set.new([]) end
      result = Set.new([])
      r[word].each { |infl| # loop over possible inflected forms
        result = result.union(self.index(infl,false))
      }
      return result
    else
      if not self.word_index.has_key?(word) then return Set.new([]) end
      return self.word_index[word]
    end
  end

end

def get_freq(infile,n_sentences)
  if not FileTest.exist?(infile) then die("file #{infile} not found") end
  return tidy_freq_table(JSON.parse(slurp_file(infile)),n_sentences)
end

def tidy_freq_table(raw,n_sentences)
  # make a frequency table into a form that's more conveniently indexed and that is normalized
  cooked = {}
  raw.each { |x|
    cooked[x[0]] = x[1]/n_sentences.to_f
  }
  return cooked
end
