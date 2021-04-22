SRCS = $(wildcard raw/*.txt)
LEMMMAS = $(patsubst raw/%.txt,cache/%.lemmas,$(SRCS))

cache/%.lemmas: cache/%.json
	lemmatize.py $< $@

default:
	./rashomon.rb pope_iliad lang_iliad

lemmas: $(LEMMAS)
