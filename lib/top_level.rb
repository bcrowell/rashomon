# coding: utf-8
def main()
  raw_dir = "raw"
  cache_dir = "cache"
  data_dir = "data"
  tr_dir = "tr"

  if ARGV.length<1 then die("supply one or two arguments, e.g., pope_iliad and lang_iliad") end
  0.upto(ARGV.length-1) { |i|
    prep(ARGV[i],raw_dir,cache_dir)
  }
  if ARGV.length<2 then exit(0) end
  read_tr(tr_dir)
  do_match(ARGV,cache_dir,data_dir)

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
