RAW = $(wildcard raw/*.txt)
LEMMAS =    $(patsubst raw/%.txt,cache/%.lemmas,$(RAW))
.PRECIOUS: cache/%

cache/%.lemmas: cache/%.json
	lemmatize.py $< $@

cache/%.json: raw/%.txt
	./rashomon.rb $*

default:
	./rashomon.rb match ιλιας pope_iliad
	#./rashomon.rb match pope_iliad lang_iliad

lemmas: $(LEMMAS)


