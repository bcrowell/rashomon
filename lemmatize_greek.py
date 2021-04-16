#!/bin/python3

import json,sys,re
from cltk.stem.lemma import LemmaReplacer

# usage:
#   lemmatize_greek.py foo.json bar.json
# The file foo.json should be a json array of strings to be lemmatized.
# Writes a new json data structure to bar.json.

if len(sys.argv)<3:
  print('supply two filenames')
  sys.exit(-1)

infile = sys.argv[1]
outfile = sys.argv[2]

with open(infile,'r') as f:
  data = json.load(f)

lemmatizer = LemmaReplacer('greek')

result = []
for sentence in data:
  sentence = re.sub(r"[.·;]\s*$",'',sentence) # remove sentence-ending punctuation; all other punctuation has already been removed
  result.append(lemmatizer.lemmatize(sentence))

# The following is a little complicated in order to make it more human readable, one sentence per line.
with open(outfile, 'w', encoding='utf8') as f:
  f.write("[")
  first = True
  for sentence in result:
    if not first:
      f.write(",")
    first = False
    f.write("\n")
    json.dump(sentence, f, ensure_ascii=False)
  f.write("\n]\n")
