rashomon
========

Experimental algorithms for finding passages that match up between two
different versions or translations of the same text.

Installing the prerequisites:

pip3 install cltk
pip3 install greek-accentuation
python -c "from cltk.corpus.utils.importer import CorpusImporter corpus_importer = CorpusImporter('greek'); corpus_importer.import_corpus('greek_models_cltk')"

pip3 install spacy
python3 -m spacy download en_core_web_trf

files in the cache directory
============================
lemmas:
A json file consisting of an array of sentences, each of which is an array of words.
Each word consists of [orig,lem,pos,other], where orig is the original
word, lem is the word's lemmatized form, pos is a word describing the part of speech,
and other is other information from the lemmatizer.

