#!/bin/python3

import json,sys,re

# usage:
#   lemmatize_greek.py grc ιλιας.json lemmatized.json
#   lemmatize_greek.py en  foo.json bar.json
# The file foo.json should be a json array of strings to be lemmatized.
# Writes a new json data structure to bar.json.

if len(sys.argv)<4:
  print('see usage in comments at the top of the source code')
  sys.exit(-1)

language = sys.argv[1]
infile = sys.argv[2]
outfile = sys.argv[3]

with open(infile,'r') as f:
  print(f"reading {infile}")
  data = json.load(f)

if language=='grc':
  from cltk.stem.lemma import LemmaReplacer
  lemmatizer = LemmaReplacer('greek')
else:
  import spacy
  nlp = spacy.load("en_core_web_trf") # English

result = []
count = 0
for sentence in data:
  sentence = re.sub(r"[\.\?·;]\s*$",'',sentence) # remove sentence-ending punctuation; all other punctuation has already been removed
  if language=='grc':
    result.append(lemmatizer.lemmatize(sentence))
  else:
    doc = nlp(sentence)
    lemmas = [w.lemma_ for w in doc if (w.pos_!='PUNCT' and w.lemma_!='-PRON-')]
    result.append(lemmas)
  count = count+1
  if count%500==0:
    print(f"Did {count} of {len(data)} sentences.")

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