#!/bin/ruby
# coding: utf-8

# This doesn't really work. Does detect hapax legomena, but also gets tons of
# false positives, which seem to be mainly cases where there is some confusion
# in my preprocessing about punctuation.

require 'optparse'
require 'json'
require 'set'

require_relative "lib/file_util"
require_relative "lib/stat"
require_relative "lib/string_util"
require_relative "lib/text"

def main()
  raw_dir = "raw"
  cache_dir = "cache"
  data_dir = "data"

  if ARGV.length<1 then die("supply an argument, e.g., ιλιας") end
  file = ARGV[0]
  infile = File.join(cache_dir,file+".lemmas")
  t = JSON.parse(slurp_file(infile))
  orig =   JSON.parse(slurp_file(File.join(cache_dir,file+".json")))
  freq = {}
  source = {}
  k = 0
  t.each { |sentence|
    k +=1
    sentence.each { |word|
      lexical = word[1]
      source[lexical] = [word[0],k]
      if freq.has_key?(lexical) then
        freq[lexical] += 1
      else
        freq[lexical] = 1
      end
    }
  }
  hapax = []
  freq.keys.each { |w|
    if freq[w]>1 then next end
    if w=~/᾽$/ then next end # may get some false negatives this way
    if source[w][0]!=source[w][0].downcase then next end # kludgy way of avoiding proper nouns
    hapax.append(w)
  }
  $stderr.print "found #{hapax.length} lexical items that occurred only once, out of #{freq.keys.length} total lexical items\n"
  alphabetical_sort(hapax).each { |lexical|
    sentence_num = source[lexical][1]
    source_sentence = orig[sentence_num] # this doesn't actually work, is off by some amount
    print "#{lexical}         #{source[lexical][0]}\n"
  }
end

def die(message)
  $stderr.print message,"\n"
  exit(-1)
end


main()
