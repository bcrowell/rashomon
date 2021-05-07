# coding: utf-8
def main()
  raw_dir = "raw"
  cache_dir = "cache"
  data_dir = "data"
  tr_dir = "tr"

  verb = ARGV.shift

  if verb=='prep' then
    0.upto(ARGV.length-1) { |i|
      if ARGV.length<1 then die("supply one or more arguments, e.g., pope_iliad") end
      prep(ARGV[i],raw_dir,cache_dir)
    }
    return
  end

  tr = read_tr(tr_dir)
  print "Read tr files totaling #{tr.length} entries\n"

  if verb=='match' then
    if ARGV.length!=2 then die("supply two arguments, e.g., pope_iliad lang_iliad") end
    do_match(ARGV,cache_dir,data_dir,tr)
    return
  end

  if verb=='dev' then # used to run code that I'm currently developing and playing with
    if ARGV.length!=1 then die("supply one argument, e.g., pope_iliad") end
    file = ARGV[0]
    lem = get_lemmas(file,cache_dir)
    rev = reverse_lemmatizations(lem)
    print JSON.pretty_generate(rev)
    return
  end

  die("unrecognized verb: #{verb}; see README for usage")

end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end

def get_texts(files,cache_dir,data_dir)
  t = []
  0.upto(1) { |i|
    t.push(Text.new(cache_dir,data_dir,files[i]))
  }
  return t
end

def set_up_options(non_default_options)
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
  options = default_options.merge(non_default_options)
  return options
end
