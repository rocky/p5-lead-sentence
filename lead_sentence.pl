#!/usr/bin/perl -w
# $Id: lead_sentence.pl,v 1.3 2005/06/22 00:52:07 rocky Exp $
# Todo:
#   Make into a module? Callable interface...
#   Easier to add to customize--split off words into other tables.
# (c) 1998 R. Bernstein, AP Multimedia services (rocky@thewire.ap.org)
my $vcid= '$Id: lead_sentence.pl,v 1.3 2005/06/22 00:52:07 rocky Exp $';
sub usage {
print "
 usage: $program [--help] | [--version]
        $program [--debug] [--sentence *string* | --file *file* ] 
                 [--rating] [--newline] [--maxout n] [--minsent n] 
                 [--ellipsis] 

 Find the first sentence, or first part of the input that has a good 
 chance of being a sentence. 

 The desired length of the first sentence is at least $MIN_OUTPUT characters and
 is no longer than $MAX_OUTPUT characters. However the minimum number of
 characters and maximum number of characters desired can be controlled
 by the options --minsent and --maxout respectively.

 Use option --newline if want a the sentence to end with a line end.
 Use option --ellipsis if you want the program to indicate that 
 it exceeded --maxout ($MAX_OUTPUT) before finding a good place
 to break.

 The input is taken from STDIN unless it is given by option --sentence 
 or option --file.
  

 Algorithm:
 Search for the end-of-sentence punctuation. Try to parse the 
 context around that into the word before the punctuation, any
 enclosing punctuation like close quotes or close parentheses,
 spaces and the next word. 

 From this evaluate how likely it is we've got the beginning of a sentence
 In the first $MAX_OUTPUT characters, return the text up to the first point 
 that is the most likely sentence end.
";

exit 100;
}


initialize();
process_options();

$_ = $alltext;
$bw = ''; $cont = '';
while (/(^.*?$end_punct)/) {

    $rating = 0; $oq=$sp=$cp=$bw='';
    $pos = length($1);
    
    ($punct) = /^.*?($end_punct)/;
    if ($punct =~ /$strict_end_punct/) {
	$rating += $GOOD_RATING;
    }
    
    # Get the part up to the end of the sentence.
    $offset += $pos;
    $sentence_try = $cont . substr($_, 0, $pos);
    if ($oq) {
	$sentence_try = $oq . substr($_, 0, $pos);
	$oq = '';
    }
    $_ = substr($_, $pos);
    $pos = 0;
    
    # Pass a bit of forward context...
    $remaining = $_;
    if (/^($clause_punct)/) {
	$rating = $CLAUSE_RATING;
	;
    } else {
	if (/^($close_punct)/) {
	    $cp = $1;
	    advance_pos($cp);
	    $rating = $GOOD_RATING;
	}
	if (/^($spaces)/) {
	    $sp = $1;
	    advance_pos2($sp);
	    if (/^($open_quote)/) {
		$oq = $1;
		advance_pos2($oq);
	    }
	    # We use \S+ (nonspace) rather than \w+ (word) in picking out
	    # the lead word of the proposed "sentence" below: we *do*
	    # want punctuation. For example "I." is different from "I," 
	    # "A." is different from "A" and "We." different from "We"
	    # We also get common contractions this way too.
	    if (/^(\S+)/) {
		$bw = $1;
		advance_pos2($bw);
	    }
	} elsif (length($_) != 0) {
	    # No space after punctuation. Could be number like 0.1 percent
	    # or an abbeviation like a.m.
	    
	    $cont = $sentence_try;
	    next;
	}
	$rating = sentence_rate2($sentence_try, $punct, 
				 $cp, $sp, $oq, $bw, $rating);
    } 
    # Evaluate sentence

    # Give demerit if the sentence is too long or too short.
    if ($offset+$pos > $MAX_OUTPUT) {
	$rating -= $MAXLENGTH_DEMERIT; 
    } elsif ($offset+$pos <= $MIN_OUTPUT) {
	$rating -= $MINLENGTH_DEMERIT; 
    }
    
    if ($rating >  $max_rating) {
	# Found the next potential winner.
	$max_rating = $rating;
	$max_pos    = $offset+$pos;

    }
    print "rating: $rating, close punct: '$cp', max: $max_rating, ",
    "open quote: '$oq', begin word: $bw\n"
	if $debug;
    print "sentence:\n$sentence_try\n"
	if $debug;
    $cur_pos = $offset + $pos;

    # Done if we exceeded the lenght limit, or we found something which
    # is acceptable given the text length. 
    last if $offset >= $MAX_OUTPUT
	    || ($max_rating > $GOODNESS_THRESHOLD && $cur_pos > $MIN_OUTPUT)
	    || ($max_rating >= $OK_THRESHOLD && $cur_pos > $MED_SENTENCE)  ;
    $_ = $remaining;
    $cont = '';
}

# Increase MAX_OUTPUT if the best sentence is the last one.
# This will reduce cutoff of the last sentence.
$MAX_OUTPUT += $MAX_OUTPUT_STRETCH if $max_pos > $MAX_OUTPUT;

if ($max_pos > $MAX_OUTPUT && $ellipsis) {
    $max_pos = $MAX_OUTPUT;
    $ending = "...$nl";
} else {
    $ending = "$nl";
}

print substr($alltext, 0, $max_pos), $ending;

print "\nRating is $max_rating.\n" if $debug || $show_rating;

exit 0;

 
# We are given a string with exactly one punctuation and
# perhaps some leading context. Now return how good we think this
# match is.  The higher the number, the better we think so. 

sub sentence_rate2 {
    my($sentence, $punct, $cp, $sp, $oq, $begin_word, $rating) = @_;

    # Bonus points for tidiness.
    $rating += $SPACES_MERIT if length($sp) > 1;

    # If the word at the beginning of the "sentence" is not capitalized
    # that's not good. Recall that this is after a period, not a semicolon.
    # Also we leave a hook for other nonstarter symbols/words.
    # Example: Intl. Fed. of Druids. 
    #                     ^
    if ($begin_word) {
	if (($begin_word =~ /^[a-z]/) || $sentence_nonstarters{$begin_word}) {
	    $rating -= $NONSTARTER_DEMERIT;
	} elsif ($begin_word =~ /^[A-Z]/) {
	    $rating += $CAPITAL_MERIT;
	}
        # On the other hand, if the word following is a common sentence
	# beginning, give a merit.		 
	$rating += $STARTER_MERIT if $sentence_starters{$begin_word};
    }

    # The rest deals only with period-terminated sentences.
    return $rating if $punct ne '.';


    if ($sentence =~ /($spaces|^)(\S+)($end_punct)$/) {
	$tail_word = $2;
    }
    
    # If the word before the end of sentence is capitalized
    # or is in a list of known abbreviations, we are less 
    # likely to have found the end of a sentence.
    # Example: Corp. and Mr. Jones
    #          ^ capital ^ known abbreviation.
    if ($tail_word) {
	if (!$abbrevs{$tail_word}) {
	    if ($tail_word !~ /^[A-Z]/) {
		$rating += $PERIOD_RATING;
	    } else {
		# Not an known abbreviation, but still could be one.
		# The below sets to overlook demerits if 
		# there are multiple spaces. Otherwise we are $SPACES_MERIT
		# Down.
		$rating += $PERIOD_RATING-$SPACES_MERIT;
		# Well, one more small glitch. If the last word is a
		# single letter, then it probably is an abbreviation.
		# as in Robert L. Bernstein or U.N.
		if (length($tail_word) == 1 || $tail_word =~ /\.[A-Z]/) {
		    $rating -= $SINGLE_LETTER_DEMERIT;
		}
	    }
	}
    }

    return $rating;
}

sub max {
    my($a, $b) = @_;
    return $a > $b ? $a : $b ;
}

sub min {
    my($a, $b) = @_;
    return $a < $b ? $a : $b ;
}

sub initialize {

    ($program = $0) =~ s,.*/,,;   # Who am I today, anyway? 

    $debug = 0;

    $MIN_OUTPUT         =  40; # Abstract must be longer than this.
    $MAX_OUTPUT         = 400; # Abstract must be shorter than this.
    $MAX_OUTPUT_STRETCH =  50; # Extra stretch to avoid truncation.
    $MIN_SENTENCE       =  15; # Sentences shorter than this preceding
                               # a period are suspect. Length includes
                               # trailing period and leading spaces.
    $MED_SENTENCE       = 120; # Abstract should be about this.
                               # Needs to include byline. 
    $CLAUSE_RATING      =  30;
    $GOOD_RATING        =  40;
    # $SURE_RATING        =  50;
    $GOODNESS_THRESHOLD =  50; # Rating at which we are happy with.
    $OK_THRESHOLD       =  $CLAUSE_RATING+5; # Rating at which we are 
                                             # moderately happy with.
    $PERIOD_RATING       =  $OK_THRESHOLD;   # Rating for ambiguous period-ended
                                             # sentences;
    $MAXLENGTH_DEMERIT     =  15; # Demerit for sentence end going past 
                                  # $MAX_OUTPUT
    $MINLENGTH_DEMERIT     =  15; # Demerit for sentence end going less than
                                  # $MIN_OUTPUT
    $NONSTARTER_DEMERIT    =  30; # Demerit "beginning" sentence word being 
                                  # in %sentence_nonstarters or uncapitalized
                                  # word
    $SINGLE_LETTER_DEMERIT =   7; # Demerit last word being a single letter
                                  # as in Robert L.
    $STARTER_MERIT      =  25; # Merit for "beginning" sentence word being
                               # in %sentence_starters
    $CAPITAL_MERIT      =   5; # Merit for "beginning" sentence word being
                               # a capitalized word.
    $SPACES_MERIT       =  30; # Merit for having more than one space
                               # after the end punctuation.
    $offset = 0;          # How far we are into the string.
    $max_rating = 0;      # Largest rating--Initially set low.


    #############
    ## Patterns #
    #############


    # Punctuation that could end a sentence.
    $end_punct='((\.+)|([!?]+))'; 

    # Something that would more strictly end a sentence.
    $strict_end_punct='((\.{3,})|([!?]+))'; 

    # Punctuation that could end a phrase---not as good as something that
    # could end a phrase.
    # $end_phrase='((;)|(--)|(":"))'; #"

    # Something that would close a quotation or parenthetical remark:
    # '', ", ', ], or )
    $close_punct='((\'\')|(["\')\]]))'; # Note: '' has to come before single

    # Something that could open a quotation or parenthetical remark.
    # ``, ", `, [, or (
    $open_quote='((``)|(["`[(]))'; # Note `` has to come before `

    # Something that could open a quotation or parenthetical remark.
    # ", `, [, (, or ``
    $clause_punct='[,;]';

    # A symbol other than some sort of a quotation. Good for starting sentences
    # However we may do further refinement later...
    # $no_punct='[^"\.\'`?!;:-]+'; #"

    # Something that might begin a sentence, not including leading spaces.
    # $begin_of_sentence="$open_quote?$no_punct"; #

    $spaces='\s+';

    # Some known abbreviations without the trailing dot which 
    # are not likely to end a sentence.
    # `etc.' is not put in here since that often ends a sentence.
    # Jr. I'm not sure about since that too could end a sentence.
    %abbrevs = ('vs'  => 1, 'Mr'  => 1, 'Ms' => 1, 'Dr' => 1,
		'Mrs' => 1, 'Msgr'=> 1, 
		'a.m' => 1, 'p.m' => 1);


    # Some words that are likely to follow an abbreviation and not
    # begin a sentence. Note these words are case sensitive,
    # words like 'and' are not needed since they'll be 
    # removed by virtue of the fact that the are not capitalized.
    %sentence_nonstarters = ( 
	         '&' => 1 
			    );

    # Words that are likely to start a sentence, mainly prepositions and 
    # pronouns.
    %sentence_starters = ( 
	 # Articles
         'The'  => 1, 'A'     => 1, 'An'    => 1, 
         # Prepositions
	 'In'   => 1, 'We'    => 1, 'However' => 1, 'But' => 1,
	 'When' => 1, 'If'    => 1, 'For' => 1, 'Also' => 1,
	 'After'=> 1, 'Before'=> 1,
	 'This' => 1, 'That'  => 1, 'There' => 1,
         # Pronouns
	 'He'   => 1, 'She'   => 1, 'I'   => 1, 'They' => 1, 'We' => 1,
         'It'   => 1, 
         # Prossessives
         'Their' => 1, 'Our'  => 1,
			 );
}

sub process_options {
    use Getopt::Long;
    $Getopt::Long::autoabbrev = 1;
    
    my $result = &GetOptions
	(
	 'debug',       \$debug,
	 'rating',      \$show_rating,
	 'help',        \$help,
	 'newline',     \$nl,
	 'ellipsis',    \$ellipsis,
	 'nl',          \$nl,
	 'file=s',      \$file,
	 'sentence=s',  \$sentence,
	 'maxout=i',    \$MAX_OUTPUT,
	 'minsent=i',   \$MIN_SENTENCE
	 );

    $nl = "\n" if $nl;
    usage if $help;
    if ($sentence) {
	@LINES = ($sentence);
	print $sentence if $debug;
    } else {
	if ($file) {
	    close(STDIN);
	    open(STDIN, "<$file") || die "Can't open file $file: $!";
	}
	@LINES = <STDIN>;
    }
    foreach (@LINES) {
	chomp;
	$alltext = join(" ", @LINES);
    }
}

sub advance_pos {
    my($str) = @_;
    $pos = length($str);
    $offset += $pos;
    $_ = substr($_, $pos);
    $pos = 0;
}

sub advance_pos2 {
    my($str) = @_;
    my($pos) = length($str);  # This one doesn't affect global $pos!
    $_ = substr($_, $pos);
}
