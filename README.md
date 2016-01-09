Some Perl code I wrote when I worked at the Associated Press to find the leading sentence for some text (news stories).

It uses heuristics for sentence ends:

* Space or quote and space after a dot
* Not space before puctuation mark
* Word with punctuation mark isn't capitalized (could be an abbreviation)
* Word after space is capitalized (Next word starts a sentence)
* Word with punctuation mark isn't capitalized (could be an abbreviation)
* Word with punctuation mark isn't known abbreviation
* Following word with capitalization is known sentence begin word, e.g. The
* Sentence length is at least so many characters
* Sentence length is no more than so many characters.

We rank possible endings and pick the highest one.
