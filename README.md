rashomon
========

Experimental algorithms for finding passages that match up between two
different versions or translations of the same text.

Installing the prerequisites:

pip3 install cltk
pip3 install greek-accentuation
python -c "from cltk.corpus.utils.importer import CorpusImporter corpus_importer = CorpusImporter('greek'); corpus_importer.import_corpus('greek_models_cltk')"

pip3 install nltk
python -c "import nltk; nltk.download('wordnet'); nltk.download('punkt')" ... doesn't work if you do this as root


