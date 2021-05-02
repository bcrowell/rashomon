#!/bin/python3

import json,sys,re,unicodedata

# usage:
#   lemmatize.py foo.json bar.json
# The file foo.json should be a json array of strings to be lemmatized.
# Writes a new json data structure to bar.json.

def spacy_ignored(pos,lemma):
  return (pos=='SYM' or pos=='PUNCT' or lemma=='-PRON-')
  # I can't find a complete list of its parts of speech, their links don't lead to any actual documentation.
  # https://spacy.io/usage/linguistic-features

def cltk_ignored(pos,lemma):
  # Greek pos tags: https://github.com/cltk/greek_treebank_perseus
  return (lemma=='·' or lemma=='᾽' or lemma==';' or lemma=='.')
  # ... I would like to do a regex to see if it contains any letters of the greek alphabet, but python doesn't have posix character classes.
  #     Preprocessing should already have eliminated all punctuation except for sentence-ending punctuation.

def cltk_pos_code_to_pos(code):
  if code.lower()=='unk':
    return 'unknown'
  return dict_lookup_or_echo(
         {'v':'verb','n':'noun','a':'adjective','d':'adverb','1':'article','g':'particle','c':'conjunction','r':'preposition','p':'pronoun',
         't':'participle','m':'numeral','i':'interjection','u':'punctuation'},
         code[0].lower())

def spacy_pos_code_to_pos(code):
  return dict_lookup_or_echo(
          {'PROPN':'noun','VERB':'verb','NOUN':'noun','CCONJ':'conjunction','ADP':'preposition','DET':'article','PART':'particle','ADJ':'adjective',
           'ADV':'adverb','PRON':'pronoun','AUX':'aux'},
          code)

def dict_lookup_or_echo(dict,key):
  if key in dict:
    return dict[key]
  else:
    return key

def die(message):
  print(message)
  sys.exit(-1)

if len(sys.argv)<3:
  die('see usage in comments at the top of the source code')

infile = sys.argv[1]
outfile = sys.argv[2]

meta_file = re.sub(r"^cache\/(.*)\.json",r"data/\1.meta",infile)
if meta_file==infile:
  die(f"input file {infile} doesn't match regex, is not of the form cache/---.json")
with open(meta_file,'r') as f:
  meta = json.load(f)
language = meta["language"]

with open(infile,'r') as f:
  data = json.load(f)

print(f"Lemmatizing {infile} to {outfile}, language={language}\n")

if language=='grc':
  # https://github.com/cltk/tutorials/blob/master/8%20Part-of-speech%20tagging.ipynb
  from cltk.stem.lemma import LemmaReplacer
  from cltk.tag.pos import POSTag
  lemmatizer = LemmaReplacer('greek')
  tagger = POSTag('greek')
else:
  import spacy
  nlp = spacy.load("en_core_web_trf") # English

result = []
count = 0
for sentence in data:
  sentence = re.sub(r"[\.\?·;]\s*$",'',sentence) # remove sentence-ending punctuation; all other punctuation has already been removed
  if language=='grc':
    lemmas = lemmatizer.lemmatize(sentence)
    tagged = tagger.tag_tnt(sentence)
    tagged = [[w[1],w[0]] for w in tagged if not cltk_ignored(w[1],w[0])]
    a = []
    i = 0
    for w in lemmas:
      if i>=len(tagged):
        break
      pos = tagged[i][0]
      a.append([tagged[i][1],lemmas[i],cltk_pos_code_to_pos(pos),f"cltk:{pos}"]) # original, lemma, part of speech, cltk part of speech
      i = i+1
    if len(lemmas)!=len(tagged):
      print(lemmas,"\n",tagged,"\n",len(lemmas),len(tagged),"\n",a)
      sys.exit("len(lemmas)!=len(tagged)")
    result.append(a) 
  else:
    analysis = nlp(sentence)
    a = [[w.text,w.lemma_,spacy_pos_code_to_pos(w.pos_),f"spacy:{w.pos_}"] for w in analysis if not spacy_ignored(w.pos_,w.lemma_)]
    result.append(a)
  count = count+1
  if count%500==0 or (count%50==0 and language=='grc'):
    print(f"  Did {count} of {len(data)} sentences.")

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
