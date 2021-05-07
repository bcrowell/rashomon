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

## Usage

    rashomon prep foo bar baz ...

Does any necessary preparation work on the given files, which should be in the raw directory.
The results go in the cache directory.
It's not necessary to do this as a separate step unless you want to; it gets done automatically if needed.
Doing this step will not produce the .lemmas files; to do that, do a ``make lemmas.''

    rashomon match foo bar

Matches up the texts foo and bar.

## files in the cache directory
lemmas:
A json file consisting of an array of sentences, each of which is an array of words.
Each word consists of [orig,lem,pos,other], where orig is the original
word, lem is the word's lemmatized form, pos is a word describing the part of speech,
and other is other information from the lemmatizer.

## current status

Tried doing bilingual sentence alignment using a minimal change to the monolingual algorithm.
(Light cone not working for bilingual case. Fourier is basically analyzing background, gives zero.)

Runs, finds a few good matches, but mostly garbage. It tends to find cases where a single Greek
word has multiple English translations, and several of those happen to occur in the same
sentence. E.g., "The noblest power that might the world control They gave thee not a brave and virtuous soul."
This sentence has three words that are in the tr list for ἀγαθός, so we get bogus high-scoring matches
to Greek sentences that contain that word.

Possible ways of improving this:
(1) Don't add to score if one word matches multiple words from the same tr set.
(2) Ignore matches that are too far from the main diagonal.
(3) Expand the size of the tr lists, possibly by looking for correlations bewteen en->grc and grc->en dictionaries.
