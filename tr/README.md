These are lists of words that might be strongly statistically correlated
between one language and another. Below I assume English and Greek.

Syntax:

    <file> ::= <header> '\n-\n' <entry>*

    <header> ::= JSON hash

    <entry> ::= '+'? <Greek word> <English word>* '\n' ...all delimited by whitespace; leading whitespace is ignored

The header should at a minimum state the languages used:
{"from":"grc","to":"en"}

Comments begin with #.

A + prefixed on a line indicates that I think it's likely to be a good one-to-one
correlation.

Unicode characters in the input are automatically converted to nfc canonical form.
