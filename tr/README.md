These are lists of words that might be strongly statistically correlated
between one language and another. Below I assume English and Greek.

Syntax:

    <file> ::= <header> '\n-\n' <entry>*

    <header> ::= JSON hash

    <entry> ::= '+'? <Greek word> <English word>* '\n' ...all delimited by whitespace; leading whitespace is ignored

Words can contain any character from the posix [:alpha:] character class, plus - and '.
The header should at a minimum state the languages used:
{"from":"grc","to":"en"}

Comments begin with #.

A + prefixed on a line indicates that I think it's likely to be a good one-to-one
correlation.

Unicode characters in the input are automatically converted to nfc canonical form.

Example of an entry:

    θώς jackal

Entries can contain multiple possible translations from one word to one word:

    ἀρετή goodness excellence virtue valor bravery

Correlates need not constitute self-contained translations, so, e.g., ἀκοντιστύς
was a game involving javelins:

    ἀκοντιστύς javelin dart contest game
