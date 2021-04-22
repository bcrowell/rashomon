RAW = $(wildcard raw/*.txt)
LEMMAS =    $(patsubst raw/%.txt,cache/%.lemmas,$(RAW))

cache/%.lemmas: cache/%.json
	lemmatize.py $< $@

cache/%.json: raw/%.txt
	./rashomon.rb $*

default:
	./rashomon.rb pope_iliad lang_iliad

lemmas: $(LEMMAS)


