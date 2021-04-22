# coding: utf-8
def clean_up_text(t)
  # Greek punctuation:
  #   modern ano teleia, https://en.wikipedia.org/wiki/Interpunct#Greek , U+0387 · GREEK ANO TELEIA
  #   middle dot, · , unicode b7 (may appear in utf-8 as b7c2 or something)
  #   koronis, https://en.wiktionary.org/wiki/%E1%BE%BD
  # eliminate all punctuation except that which can end a sentence
  # problems:
  #   . etc. inside quotation marks
  t.gsub!(/(᾽)(?=\p{Letter})/) {" #{$1}"} # e.g., Iliad has this: ποτ᾽Ἀθήνη , which causes wrong behavior by cltk lemmatizer.
  t.gsub!(/[—-]/,' ')
  t.gsub!(/\./,'aaPERIODaa')
  t.gsub!(/\?/,'aaQUESTIONMARKaa')
  t.gsub!(/\;/,'aaSEMICOLONaa')
  t.gsub!(/·/,'aaMIDDLEDOTaa')
  t.gsub!(/\!/,'aaEXCLaa')
  t.gsub!(/[[:punct:]]/,'')
  t.gsub!(/aaPERIODaa/,'.')
  t.gsub!(/aaQUESTIONMARKaa/,'?')
  t.gsub!(/aaSEMICOLONaa/,';')
  t.gsub!(/aaMIDDLEDOTaa/,'·')
  t.gsub!(/aaEXCLaa/,'!')
  t.gsub!(/\d/,'') # numbers are footnotes, don't include them
  return t
end

def to_words(sentence)
  if sentence.nil? then return [] end
  x = sentence.split(/[^\p{Letter}]+/)  # won't handle "don't"
  x = x.map { |word| to_key(word)}
  x.delete('')
  return x
end

def to_key(word)
  return word.unicode_normalize(:nfkc).downcase
end

