#!/usr/bin/perl -w

use strict;

# letter values
my %scores = (
    'A' => 1,
    'B' => 4,
    'C' => 4,
    'D' => 2,
    'E' => 1,
    'F' => 4,
    'G' => 3,
    'H' => 3,
    'I' => 1,
    'J' => 10,
    'K' => 5,
    'L' => 2,
    'M' => 4,
    'N' => 2,
    'O' => 1,
    'P' => 4,
    'Q' => 10,
    'R' => 1,
    'S' => 1,
    'T' => 1,
    'U' => 2,
    'V' => 5,
    'W' => 4,
    'X' => 8,
    'Y' => 3,
    'Z' => 10,
    '*' => 0,
);


my $file = shift;
my $boardFile = shift;
my $stateFile = shift;

if (! defined($file) || ! defined($boardFile)) {
    die("Usage: $0 <word_list> <board> [<state_file>]")
}

my $trie = buildWordTrie($file);
my ($board, $numRows, $numCols) = parseBoard($boardFile);
my $state = {'scores' => \%scores, 'board' => $board, 'numRows' => $numRows, 'numCols' => $numCols, 'trie' => $trie, 'moves' => [], 'allLetterBonus' => 35, 'rackSize' => 7};
if (defined($stateFile)) {
    $stateFile = uc($stateFile);
    $state = loadState($state, $stateFile);
}

while (1) {
    print "> ";
    my $cmd = <>;
    if (! defined($cmd)) {
        print "Quit\n";
        exit;
    }
    $state = processCommand($state, $cmd);
}

exit;

sub processCommand {
    my $state = shift;
    my $cmd = shift;
    chomp($cmd);
    if (length($cmd) < 1) { return $state; }
    $cmd = uc($cmd);
    my @cmdArgs = split(/\s+/, $cmd);
    $cmd = shift(@cmdArgs);
    if ($cmd eq 'P') {
        printBoard($state);
    } elsif ($cmd eq 'A') {
        # A 13,2 [V|H] WORD
        $state = addWordToBoard($state, @cmdArgs);
    } elsif ($cmd eq 'C') {
        # C 13,2
        printCellData($state, @cmdArgs);
    } elsif ($cmd eq 'S') {
        # S filename
        $state = saveMoveState($state, @cmdArgs);
    } elsif ($cmd eq 'R') {
        $state = resetBoard($state);
    } elsif ($cmd eq 'L') {
        $state = loadState($state, @cmdArgs);
    } elsif ($cmd eq 'F') {
        findOptimalMove($state, @cmdArgs);
    }
    return $state;
}

sub scoreMove {
    my $rack = shift;
    my $state = shift;
    my $left_i = shift;
    my $left_j = shift;
    my $leftPart = shift;
    my $right_i = shift;
    my $right_j = shift;
    my $rightPart = shift;
    my $print = shift;
    $print = 0
        if (! defined($print));

    # build avail letter=>count hash
    my %avail = ();
    foreach my $l (@{$rack}) {
        $avail{$l}++;
    }
    # letters needing wildcard
    my %needsWildcard = ();
    my %letterPosition = ();

    # save row state
    my @origRowState = ();
    for (my $j = 0; $j < $state->{numCols}; $j++) {
        my $cell = $state->{board}->[$left_i]->[$j];
        push(@origRowState, exists($cell->{letter}) ? 1 : 0);
    }

    if (length($leftPart) > 0) {
        my @letters = split(//, $leftPart);
        my $numLetters = scalar(@letters);
        for (my $k = 0; $k < $numLetters; $k++) {
            my $j = $left_j + $k;
            my $l = $letters[$k];
            $state->{board}->[$left_i]->[$j]->{letter} = $l;
            $state->{board}->[$left_i]->[$j]->{placed} = 1;
            if (! exists($letterPosition{$l})) {
                $letterPosition{$l} = [];
            }
            push(@{$letterPosition{$l}}, [$left_i, $j]);
            if (exists($avail{$l}) && ($avail{$l} > 0)) {
                $avail{$l}--;
            } elsif (exists($avail{'_'}) && ($avail{'_'} > 0)) {
                $avail{'_'}--;
                $needsWildcard{$l}++;
            } else {
                print STDERR "ERROR: leftPart [$leftPart] contains letter [$l] which isn't in the rack"
            }
        }
    }
    if (length($rightPart) > 0) {
        my @letters = split(//, $rightPart);
        my $numLetters = scalar(@letters);
        for (my $k = 0; $k < $numLetters; $k++) {
            my $j = $right_j + $k;
            my $l = $letters[$k];
            if (! exists($state->{board}->[$right_i]->[$j]->{letter})) {
                $state->{board}->[$right_i]->[$j]->{letter} = $l;
                $state->{board}->[$right_i]->[$j]->{placed} = 1;
                if (! exists($letterPosition{$l})) {
                    $letterPosition{$l} = [];
                }
                push(@{$letterPosition{$l}}, [$right_i, $j]);
                if (exists($avail{$l}) && ($avail{$l} > 0)) {
                    $avail{$l}--;
                } elsif (exists($avail{'_'}) && ($avail{'_'} > 0)) {
                    $avail{'_'}--;
                    $needsWildcard{$l}++;
                } else {
                    print STDERR "ERROR: leftPart [$leftPart] contains letter [$l] which isn't in the rack"
                }
            }
        }
    }

    # set wildcard 0 point positions based on lowest impact to overall score
    my @modified = ();
    foreach my $l (keys(%needsWildcard)) {
        my $num = $needsWildcard{$l};
        my $letterPositions = $letterPosition{$l};
        my @positions = sort { $state->{board}->[$a->[0]]->[$a->[1]]->{letterWeight} <=> $state->{board}->[$b->[0]]->[$b->[1]]->{letterWeight} } @{$letterPositions};
        for (my $k = 0; $k < $num; $k++) {
            my $position = $positions[$k];
            my ($i, $j) = @{$position};
            push(@modified, [$i, $j]);
            $state->{board}->[$i]->[$j]->{points} = 0;
        }
    }

    my $points = computePoints($state, $left_i, $left_j, 'H', 1);
    if ($print) {
        printBoard($state);
    }

    # restore row state
    foreach my $m (@modified) {
        my ($i, $j, $origPoints) = @{$m};
        delete($state->{board}->[$i]->[$j]->{points});
    }
    for (my $j = 0; $j < $state->{numCols}; $j++) {
        if (! $origRowState[$j] && exists($state->{board}->[$left_i]->[$j]->{letter})) {
            delete($state->{board}->[$left_i]->[$j]->{letter});
        }
    }

    return $points;
}

sub _findOptimalMoveProper {
    my $state = shift;
    my $rack = shift;
    my $anchors = shift;
    my $crossChecks = shift;
    my $skips = shift;
    my $board = $state->{board};
    my $numRows = $state->{numRows};
    my $numCols = $state->{numCols};
    my $trie = $state->{trie};

    my @rack = split(//, $rack);
    my $bestMove = undef;

    my @validLeftParts = sort { length($a) <=> length($b) } ('', generateAllValidLeftParts(\@rack, scalar(@rack), $trie));

    foreach my $anchor (@{$anchors}) {
        my ($i, $j) = @{$anchor};
        #print "Anchor ($i, $j)\n";
        my $middlePart = _getMiddlePart($board, $numRows, $numCols, $i, $j + 1);
        #print "middlePart:[$middlePart]\n";
        my $start_j = $j;
        while (($start_j > 0) && ! exists($board->[$i]->[$start_j - 1]->{letter})) {
            $start_j--;
        }
        my $maxLeftPartLen = $j - $start_j + ($start_j == 0 ? 1 : 0);
        #print "maxLeftPartLen:[$maxLeftPartLen]\n";
	    #if ($i == 11 && $j == 2) { print "Anchor ($i, $j) middlePart:[$middlePart] start_j:[$start_j] maxLeftPartLen:[$maxLeftPartLen]\n"; }
        if ($maxLeftPartLen > 0) {
            foreach my $leftPart (@validLeftParts) {
                last if (length($leftPart) > $maxLeftPartLen);
		        #if ($i == 11 && $j == 2) { print "\t - leftPart:[$leftPart]\n"; }
                my $leftPartLen = length($leftPart);
                my @letters = split(//, $leftPart);
                my $invalid = 0;
                for (my $k = 0; $k < $leftPartLen; $k++) {
                    my $coord = $i . "," . ($j - $leftPartLen + 1 + $k);
                    if (exists($crossChecks->{$coord}) && ! exists($crossChecks->{$coord}->{$letters[$k]})) {
                        #if ($i == 11 && $j == 2) { print "($coord) letter $letters[$k] not valid from $leftPart\n"; }
                        $invalid = 1;
                        $k = $leftPartLen;
                    }
                }
                if (! $invalid) {
                    my $prefix = $leftPart . $middlePart;
                    if (length($leftPart) || length($middlePart)) {
                        my $prefixNode = getPrefixNode($trie, $prefix);
                        if (defined($prefixNode)) {
                            #if ($i == 11 && $j == 2) { print "($i, $j) leftPart:[$leftPart] middlePart:[$middlePart] - VALID\n"; }
                            # extend?
                            my $right_j = $j + 1 + length($middlePart);
                            if ($right_j >= $numCols) {
                                # can't - see if it's valid
                                if (length($leftPart) > 0 && exists($prefixNode->{_valid}) && $prefixNode->{_valid}) {
                                    my $points = scoreMove(\@rack, $state, $i, $j - length($leftPart) + 1, $leftPart, $i, $j + 1 + length($middlePart), '');
                                    my $start_j = $j;
                                    my $start_i = $i;
                                    if (length($leftPart) == 0) {
                                        $start_j++;
                                    } else {
                                        $start_j -= (length($leftPart) - 1);
                                    }
                                    if (! exists($skips->{$prefix}) && (! defined($bestMove) || ($points > $bestMove->{points}))) {
                                        $bestMove = {'points' => $points, 'start_i' => $start_i, 'start_j' => $start_j, 'i' => $i, 'j' => $j, 'word' => $prefix, 'left_i' => $i, 'left_j' => $j - length($leftPart) + 1, 'leftPart' => $leftPart, 'right_i' => $i, 'right_j' => $j + 1 + length($middlePart), 'rightPart' => ''};
                                    }
                                    print "($start_i, $start_j) leftPart:[$leftPart] middlePart:[$middlePart] => [$prefix] - VALID (score $points)\n";
                                }
                            } else {
                                my %avail = ();
                                foreach my $l (@rack) { $avail{$l}++; }
                                foreach my $l (split(//, $leftPart)) {
                                    # handle wildcard '_' availability
                                    if ((! exists($avail{$l}) || ($avail{$l} < 1)) && (exists($avail{'_'}) && ($avail{'_'} > 0))) {
                                        # use one wildcard
                                        $avail{'_'}--;
                                    } elsif (exists($avail{$l}) && ($avail{$l} > 0)) {
                                        $avail{$l}--;
                                    } else {
                                        print STDERR "ERROR: leftPart [$leftPart] contains letter [$l] which isn't available in the rack!\n";
                                    }
                                }
                                my @rest = ();
                                foreach my $l (keys(%avail)) {
                                    for (my $z = 0; $z < $avail{$l}; $z++) {
                                        push(@rest, $l);
                                    }
                                }
                                my @rightParts = findRightParts('', $prefixNode, \@rest, $board, $i, $right_j, $numCols, $crossChecks);
                                #if ($i == 11 && $j == 2) { print "rest:[", join(",", @rest), "] numRightParts:[", scalar(@rightParts), "] rightParts:[", join(",", @rightParts), "]\n"; }
                                foreach my $rightPart (@rightParts) {
                                    if (length($rightPart) > 0 || (length($leftPart) > 0 && validWord($state->{trie}, $prefix))) {
                                        my $points = scoreMove(\@rack, $state, $i, $j - length($leftPart) + 1, $leftPart, $i, $j + 1 + length($middlePart), $rightPart);
                                        my $start_j = $j;
                                        my $start_i = $i;
                                        if (length($leftPart) == 0) {
                                            $start_j++;
                                        } else {
                                            $start_j -= (length($leftPart) - 1);
                                        }
                                        if (! exists($skips->{$prefix . $rightPart}) && (! defined($bestMove) || ($points > $bestMove->{points}))) {
                                            $bestMove = {'points' => $points, 'start_i' => $start_i, 'start_j' => $start_j, 'i' => $i, 'j' => $j, 'word' => $prefix . $rightPart, 'left_i' => $i, 'left_j' => $j - length($leftPart) + 1, 'leftPart' => $leftPart, 'right_i' => $i, 'right_j' => $j + 1 + length($middlePart), 'rightPart' => $rightPart};
                                        }
                                        print "($start_i, $start_j) left:[$leftPart] middle:[$middlePart] right:[$rightPart] => [$prefix${rightPart}] - VALID (score $points)\n";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return $bestMove;
}

sub findOptimalMove {
    my $state = shift;
    my $rack = shift;
    my @skipWords = @_;
    my %skip = ();

    foreach my $word (@skipWords) {
        $word =~ s/^\s+|\s+$//g;
        $word = uc($word);
        $skip{$word} = 1;
    }

    my $anchors = findAnchors($state->{board}, $state->{numRows}, $state->{numCols});
    my $crossChecks = computeCrossChecks($state->{board}, $state->{numRows}, $state->{numCols}, $anchors, $state->{trie});

    # across
    print "Finding optimal across move...\n";
    my $across = _findOptimalMoveProper($state, $rack, $anchors, $crossChecks, \%skip);
    $across->{dir} = "horizontally"
        if (defined($across));

    # down
    print "Finding optimal down move...\n";
    $state = boardTranspose($state);
#    printBoard($state);
    $anchors = findAnchors($state->{board}, $state->{numRows}, $state->{numCols});
#    foreach my $anchor (@{$anchors}) {
#        print "Anchor: (", $anchor->[0], ", ", $anchor->[1], ")\n";
#    }
    $crossChecks = computeCrossChecks($state->{board}, $state->{numRows}, $state->{numCols}, $anchors, $state->{trie});
#    foreach my $k (keys(%{$crossChecks})) {
#        print "CrossCheck: (", $k, ") -> ", join(" ", keys(%{$crossChecks->{$k}})), "\n";
#    }
    my $down = _findOptimalMoveProper($state, $rack, $anchors, $crossChecks, \%skip);
    if (defined($down)) {
        ($down->{start_i}, $down->{start_j}) = ($down->{start_j}, $down->{start_i});
        $down->{dir} = "vertically";
    }

    my $transposeFirst = 1;
    my $highest = undef;
    if (defined($across) || defined($down)) {
        if (defined($across) && defined($down)) {
            if ($across->{points} > $down->{points}) {
                $highest = $across;
            } else {
                $highest = $down;
                $transposeFirst = 0;
            }
        } elsif (defined($across)) {
            $highest = $across;
        } else {
            $transposeFirst = 0;
            $highest = $down;
        }
    }

    if ($transposeFirst) { $state = boardReverseTranspose($state); }
    if (defined($highest)) {
        print "Play ", $highest->{word}, " ", $highest->{dir}, " anchored at position (", $highest->{start_i}, ", ", $highest->{start_j}, ") for ", $highest->{points}, " points.\n";
        my @rack = split(//, $rack);
        scoreMove(\@rack, $state, $highest->{left_i}, $highest->{left_j}, $highest->{leftPart}, $highest->{right_i}, $highest->{right_j}, $highest->{rightPart}, 1);
    } else {
        print "No move possible.\n";    
    }
    if (! $transposeFirst) { $state = boardReverseTranspose($state); }
}

sub boardTranspose {
    my $state = shift;
    my @board = ();
    for (my $j = 0; $j < $state->{numCols}; $j++) {
        my @row = ();
        for (my $i = 0; $i < $state->{numRows}; $i++) {
            push(@row, $state->{board}->[$i]->[$j]);
        }
        push(@board, \@row);
    }
    $state->{board} = \@board;
    ($state->{numCols}, $state->{numRows}) = ($state->{numRows}, $state->{numCols});
    $state->{transposed} = 1;
    return $state;
}

sub boardReverseTranspose {
    my $state = shift;
    $state = boardTranspose($state);
    delete($state->{transposed});
    return $state;
}

sub loadState {
    my $state = shift;
    my $file = shift;
    print "Resetting current board state\n";
    $state = resetBoard($state);
    print "Loading move state from [$file]\n";
    local *IN;
    open(IN, "<$file");
    while(<IN>) {
        chomp;
        $state = processCommand($state, $_);
    }
    close(IN);
    $state->{file} = $file;
    return $state;
}

sub resetBoard {
    my $state = shift;
    for (my $i = 0; $i < $state->{numRows}; $i++) {
        for (my $j = 0; $j < $state->{numCols}; $j++) {
            foreach my $key (qw/letter points bonusUsed/) {
                if (exists($state->{board}->[$i]->[$j]->{$key})) {
                    delete($state->{board}->[$i]->[$j]->{$key});
                }
            }
        }
    }
    $state->{moves} = [];
    return $state;
}

sub saveMoveState {
    my $state = shift;
    my $file = shift;
    if (! defined($file) && exists($state->{file})) { $file = $state->{file}; }
    if (! defined($file)) {
        print "Unable to save; no filename provided.\n";
        return $state;
    }
    local *OUT;
    open(OUT, ">$file");
    foreach my $move (@{$state->{moves}}) {
        print OUT $move, "\n";
    }
    close(OUT);
    print "Move state stored to [$file]\n";
    $state->{file} = $file;
    return $state;
}

sub printCellData {
    my $state = shift;
    my $coord = shift;
    my ($i, $j) = split(/\s*,\s*/, $coord, 2);
    my $cell = $state->{board}->[$i]->[$j];
    print "Cell ($i, $j):\n";
    foreach my $key (sort(keys(%{$cell}))) {
        print "  key:[", $key, "] value:[", $cell->{$key}, "]\n";
    }
}

sub getVerticalWordExtent {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $start_i = $i;
    my $end_i = $i;
    while (($start_i > 0) && exists($state->{board}->[$start_i - 1]->[$j]->{letter})) {
        $start_i--;
    }
    while (($end_i < $state->{numRows} - 1) && exists($state->{board}->[$end_i + 1]->[$j]->{letter})) {
        $end_i++;
    }
    return ($start_i, $j, $end_i, $j);
}

sub getHorizontalWordExtent {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $start_j = $j;
    my $end_j = $j;
    while (($start_j > 0) && exists($state->{board}->[$i]->[$start_j - 1]->{letter})) {
        $start_j--;
    }
    while (($end_j < $state->{numCols} - 1) && exists($state->{board}->[$i]->[$end_j + 1]->{letter})) {
        $end_j++;
    }
    return ($i, $start_j, $i, $end_j);
}

sub computePoints {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $dir = shift;
    my $expand = shift;
    my $wordPoints = 0;
    my $expandPoints = 0;

    my ($start_i, $start_j, $end_i, $end_j) = $dir eq 'V' ? getVerticalWordExtent($state, $i, $j) : getHorizontalWordExtent($state, $i, $j);
    my $wordMult = 1;
    my $rackLettersUsed = 0;
    for ($i = $start_i; $i <= $end_i; $i++) {
        for ($j = $start_j; $j <= $end_j; $j++) {
            my $cell = $state->{board}->[$i]->[$j];
            my $letter = $cell->{letter};
            my $letterValue = exists($cell->{points}) ? $cell->{points} : $state->{scores}->{$letter};
            my $expandWordPoints = 0;
            if (exists($cell->{placed})) {
                $rackLettersUsed++;
                if ($expand) {
                    if ($dir eq 'V') {
                        if ( (($j > 0) && (exists($state->{board}->[$i]->[$j - 1]->{letter}))) || (($j < $state->{numCols} - 1) && (exists($state->{board}->[$i]->[$j + 1]->{letter})))) {
                            $expandWordPoints += computePoints($state, $i, $j, 'H', 0);
                        }
                    } else {
                        if ( (($i > 0) && (exists($state->{board}->[$i - 1]->[$j]->{letter}))) || (($i < $state->{numRows} - 1) && (exists($state->{board}->[$i + 1]->[$j]->{letter})))) {
                            $expandWordPoints += computePoints($state, $i, $j, 'V', 0);
                        }
                    }
                }
            }
            if (! $cell->{bonusUsed}) {
                $letterValue *= $cell->{letterWeight};
                $wordMult *= $cell->{wordWeight};
            }
            #print "computePoints ($i, $j) [$letter] [$letterValue]\n";
            $wordPoints += $letterValue;
            $expandPoints += $expandWordPoints;
        }
    }
    $wordPoints *= $wordMult;
    my $points = $wordPoints + $expandPoints;
    if ($rackLettersUsed >= $state->{rackSize}) { $points += $state->{allLetterBonus}; }
    return $points;
}

sub useBonuses {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $dir = shift;

    my ($start_i, $start_j, $end_i, $end_j) = $dir eq 'V' ? getVerticalWordExtent($state, $i, $j) : getHorizontalWordExtent($state, $i, $j);
    for ($i = $start_i; $i <= $end_i; $i++) {
        for ($j = $start_j; $j <= $end_j; $j++) {
            $state->{board}->[$i]->[$j]->{bonusUsed} = 1;
            delete($state->{board}->[$i]->[$j]->{placed});
        }
    }

    return $state;
}

sub addWordVerticallyToBoard {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $word = shift;
    my $blanks = shift;

    my @letters = split(//, $word);
    my $start_i = $i;
    my $rackLettersUsed = 0;
    my $letterPos = 0;
    foreach my $letter (@letters) {
        if (! exists($state->{board}->[$i]->[$j]->{letter})) {
            $rackLettersUsed++;
            $state->{board}->[$i]->[$j]->{letter} = $letter;
            $state->{board}->[$i]->[$j]->{placed} = 1;
            if (exists($blanks->{$letterPos})) {
                $state->{board}->[$i]->[$j]->{points} = 0;
            }
        }
        $letterPos++;
        $i++;
    }
    my $points = computePoints($state, $start_i, $j, 'V', 1);
    print "Added word [$word] vertically starting at ($start_i, $j) for $points points\n";
    $state = useBonuses($state, $start_i, $j, 'V');

    return $state;
}

sub addWordHorizontallyToBoard {
    my $state = shift;
    my $i = shift;
    my $j = shift;
    my $word = shift;
    my $blanks = shift;

    my @letters = split(//, $word);
    my $start_j = $j;
    my $rackLettersUsed = 0;
    my $letterPos = 0;
    foreach my $letter (@letters) {
        if (! exists($state->{board}->[$i]->[$j]->{letter})) {
            $rackLettersUsed++;
            $state->{board}->[$i]->[$j]->{letter} = $letter;
            $state->{board}->[$i]->[$j]->{placed} = 1;
            if (exists($blanks->{$letterPos})) {
                $state->{board}->[$i]->[$j]->{points} = 0;
            }
        }
        $letterPos++;
        $j++;
    }
    my $points = computePoints($state, $i, $start_j, 'H', 1);
    print "Added word [$word] horizontally starting at ($i, $start_j) for $points points\n";
    $state = useBonuses($state, $i, $start_j, 'H');

    return $state;
}

sub addWordToBoard {
    my $state = shift;
    my $startCoord = shift;
    my $dir = shift;
    my $word = shift;
    my $blanksFlat = shift;
    my %blanks = ();
    if (defined($blanksFlat)) {
        foreach my $pos (split(/,/, $blanksFlat)) {
            $blanks{$pos} = 1;
        }
    }

    my ($i, $j) = split(/\s*,\s*/, $startCoord, 2);
    $word =~ s/[^\w]+//g;

    $state = $dir eq 'V' ? addWordVerticallyToBoard($state, $i, $j, $word, \%blanks) : addWordHorizontallyToBoard($state, $i, $j, $word, \%blanks);
    push(@{$state->{moves}}, "A $startCoord $dir $word" . (defined($blanksFlat) ? ' ' . $blanksFlat : ''));
    return $state;
}

sub printBoard {
    my $state = shift;
    my $board = $state->{board};
    my $numRows = $state->{numRows};
    my $numCols = $state->{numCols};
    for (my $i = 0; $i < $numRows; $i++) {
        my @row = ();
        for (my $j = 0; $j < $numCols; $j++) {
            my ($ni, $nj) = exists($state->{transposed}) ? ($j, $i) : ($i, $j);
            if (exists($board->[$ni]->[$nj]) && exists($board->[$ni]->[$nj]->{letter})) {
                push(@row, $board->[$ni]->[$nj]->{letter});
            } else {
                push(@row, '.');
            }
        }
        print join(' ', @row), "\n";
    }
}

sub findRightParts {
	my $suffix = shift;
	my $nodePrefix = shift;
	my $rest = shift;
	my $board = shift;
	my $i = shift;
	my $j = shift;
	my $numCols = shift;
	my $crossChecks = shift;
	my @parts = ('');

	if ($j >= $numCols) {
		if (exists($nodePrefix->{_valid}) && $nodePrefix->{_valid}) {
			return ('', $suffix);
		} else {
			return ('');
		}
	}

    if (! exists($board->[$i]->[$j]->{letter})) {
		my $numRest = scalar(@{$rest});
		for (my $k = 0; $k < $numRest; $k++) {
			my $l = $rest->[$k];
			my $coord = $i . "," . $j;
			if ($l ne '_') {
                #print "findRightParts ($i, $j) suffix:[$suffix] k:[$k] rest:[", join(@{$rest}), "]\n";
                next if (exists($crossChecks->{$coord}) && ! exists($crossChecks->{$coord}->{$l}));
                if (exists($nodePrefix->{$l})) {
                    my @newrest = ();
                    push(@newrest, @{$rest}[0..$k-1]) if ($k > 0);
                    push(@newrest, @{$rest}[$k+1..$numRest-1]) if ($k < $numRest - 1);
                    if (($j < $numCols - 1) && exists($nodePrefix->{$l}->{_valid}) && ! exists($board->[$i]->[$j + 1]->{letter})) {
                        push(@parts, $suffix . $l);
                    }
                    push(@parts, findRightParts($suffix . $l, $nodePrefix->{$l}, \@newrest, $board, $i, $j + 1, $numCols, $crossChecks));
                }
            } else {
                foreach my $l (qw/A B C D E F G H I J K L M N O P Q R S T U V W X Y Z/) {
                    next if (exists($crossChecks->{$coord}) && ! exists($crossChecks->{$coord}->{$l}));
                    if (exists($nodePrefix->{$l})) {
                        my @newrest = ();
                        push(@newrest, @{$rest}[0..$k-1]) if ($k > 0);
                        push(@newrest, @{$rest}[$k+1..$numRest-1]) if ($k < $numRest - 1);
                        if (($j < $numCols - 1) && exists($nodePrefix->{$l}->{_valid}) && ! exists($board->[$i]->[$j + 1]->{letter})) {
                            push(@parts, $suffix . $l);
                        }
                        push(@parts, findRightParts($suffix . $l, $nodePrefix->{$l}, \@newrest, $board, $i, $j + 1, $numCols, $crossChecks));
                    }
                }
            }
		}
	} else {
		if (exists($nodePrefix->{$board->[$i]->[$j]->{letter}})) {
			push(@parts, findRightParts($suffix . $board->[$i]->[$j]->{letter}, $nodePrefix->{$board->[$i]->[$j]->{letter}}, $rest, $board, $i, $j + 1, $numCols, $crossChecks));
        }
	}
	return @parts;
}

sub _getMiddlePart {
	my $board = shift;
	my $numRows = shift;
	my $numCols = shift;
	my $i = shift;
	my $j = shift;

	my $part = '';
	while (($j < $numCols) && exists($board->[$i]->[$j]->{letter})) {
		$part .= $board->[$i]->[$j]->{letter};
		$j++;
	}
	return $part;
}

sub _generateLeftPartsProper {
	my $rack = shift;
	my $len = shift;
	my @leftParts = ();
	#print STDERR "_generateLeftPartsProper(", join("", @{$rack}), ", $len)\n";
	my $rackSize = scalar(@{$rack});
	if ($len == 0) { return ['']; }
	if ($len == 1) {
	    my @leftParts = ();
	    foreach my $letter (@{$rack}) {
	        if ($letter ne '_') {
	            push(@leftParts, $letter);
	        } else {
			    foreach my $letter (qw/A B C D E F G H I J K L M N O P Q R S T U V W X Y Z/) {
			        push(@leftParts, $letter);
			    }
			}
	    }
	    return \@leftParts;
	}

	for (my $i = 0; $i < $rackSize; $i++) {
		my @letters = @{$rack};
		my $letter = $letters[$i];
		my @rest = ();
		push(@rest, @letters[0..$i-1])	if ($i > 0);
		push(@rest, @letters[$i+1..$rackSize-1])	if ($i < $rackSize - 1);
		#print STDERR "   [", join("", @letters), "] $i -> $letter [", join("", @rest), "]\n";
		foreach my $suffix (@{_generateLeftPartsProper(\@rest, $len - 1)}) {
		    if ($letter ne '_') {
			    push(@leftParts, $letter . $suffix);
			} else {
			    foreach my $letter (qw/A B C D E F G H I J K L M N O P Q R S T U V W X Y Z/) {
			        push(@leftParts, $letter . $suffix);
			    }
			}
		}
	}
	return \@leftParts;
}

sub generateLeftParts {
	my $rack = shift;
	my $maxLen = shift;
	my %unique = ();
	for (my $i = 0; $i <= $maxLen; $i++) {
		#print STDERR "generateLeftParts(", join("", @{$rack}), ", $i)\n";
		foreach my $leftPart (@{_generateLeftPartsProper($rack, $i)}) {
			$unique{$leftPart} = 1;
		}
	}
	return keys(%unique);
}

sub generateAllValidLeftParts {
    my $rack = shift;
    my $rackLen = shift;
    my $trie = shift;
    my $prefix = shift;
    $prefix = ''    if (! defined($prefix));
    my $prefixLen = length($prefix);

    if ($rackLen == 0) {
        return ();
    }

    my @valid = ();
    for (my $i = 0; $i < $rackLen; $i++) {
        my $letter = $rack->[$i];
        my $newPrefix = $prefix . $letter;
        my $node = getPrefixNode($trie, $newPrefix);
        if (defined($node)) {
            push(@valid, $newPrefix);
            my @restRack = ();
            for (my $j = 0; $j < $rackLen; $j++) {
                push(@restRack, $rack->[$j])    if ($j != $i);
            }
            push(@valid, generateAllValidLeftParts(\@restRack, $rackLen - 1, $trie, $newPrefix));
        }
    }
    return @valid;
}

sub _getTopPart {
	my $board = shift;
	my $numRows = shift;
	my $numCols = shift;
	my $i = shift;
	my $j = shift;
	my $part = '';

	if ($i == 0) { return $part; };
	$i--;
	while (($i >= 0) && exists($board->[$i]->[$j]->{letter})) {
		$part = $board->[$i]->[$j]->{letter} . $part;
		$i--;
	}

	return $part;
}

sub _getBottomPart {
    my $board = shift;
    my $numRows = shift;
    my $numCols = shift;
    my $i = shift;
    my $j = shift;
    my $part = '';

    if ($i == $numRows - 1) { return $part; };
    $i++;
    while (($i < $numRows) && exists($board->[$i]->[$j]->{letter})) {
        $part = $part . $board->[$i]->[$j]->{letter};
        $i++;
    }

    return $part;
}

sub computeCrossChecks {
	my $board = shift;
	my $numRows = shift;
	my $numCols = shift;
	my $anchors = shift;
	my $trie = shift;
	my %crossChecks = ();

	foreach my $anchor (@{$anchors}) {
		my ($i, $j) = @{$anchor};
		my $topPart = _getTopPart($board, $numRows, $numCols, $i, $j);
		my $bottomPart = _getBottomPart($board, $numRows, $numCols, $i, $j);
		if (length($topPart) < 1 && length($bottomPart) < 1) {
			#print STDERR "($i, $j) computeCrossChecks: no restrictions\n";
			next;
		}
		#print STDERR "($i, $j) computeCrossChecks; topPart:[$topPart] bottomPart:[$bottomPart]\n";
		my $key = "$i,$j";
		$crossChecks{$key} = {};
		foreach my $letter ('A'..'Z') {
			my $word = $topPart . $letter . $bottomPart;
			if (validWord($trie, $word)) {
				$crossChecks{$key}->{$letter} = 1;
			}
		}
		#print STDERR "($i, $j) computeCrossChecks; valid letters: ", join(" ", sort(keys(%{$crossChecks{$key}}))), "\n";
	}

	return \%crossChecks;
}

sub getPrefixNode {
	my $trie = shift;
	my $prefix = shift;
	my @letters = split(//, $prefix);
	my $node = $trie;
	foreach my $letter (@letters) {
		if (! exists($node->{$letter})) { return undef; }
		$node = $node->{$letter};
	}
	return $node;
}

sub validWord {
    my $trie = shift;
    my $word = shift;
    my @letters = split(//, $word);
    my $node = $trie;
    foreach my $letter (@letters) {
        if (! exists($node->{$letter})) { return 0; }
        $node = $node->{$letter};
    }
    return exists($node->{_valid}) && $node->{_valid} ? 1 : 0;
}

sub buildWordTrie {
    my $file = shift;
    local *IN;
    my %trie = ();
    print "Building word trie [$file] ...\n";
    open(IN, "<$file");
    while(<IN>) {
        s/[^\w]//g;
        my @letters = split(//, $_);
        my $numLetters = scalar(@letters);
        my $node = \%trie;
        for (my $i = 0; $i < $numLetters; $i++) {
            my $letter = $letters[$i];
            if (! exists($node->{$letter})) { $node->{$letter} = {}; }
            $node = $node->{$letter};
            if ($i == $numLetters - 1) {
                $node->{_valid} = 1;
            }
        }
    }
    close(IN);
    return \%trie;
}

sub findAnchors {
	my $board = shift;
	my $numRows = shift;
	my $numCols = shift;
	my @anchors = ();
	for (my $i = 0; $i < $numRows; $i++) {
		for (my $j = 0; $j < $numCols; $j++) {
			if (! exists($board->[$i]->[$j]->{letter})) {
				# empty square, see if adjacent to non-empty square
				if (
					(($i > 0) && exists($board->[$i-1]->[$j]->{letter})) ||
					(($j > 0) && exists($board->[$i]->[$j-1]->{letter})) ||
					(($i < $numRows - 1) && exists($board->[$i+1]->[$j]->{letter})) ||
					(($j < $numCols - 1) && exists($board->[$i]->[$j+1]->{letter}))
				   ) {
					push(@anchors, [$i, $j]);
				}
			}
		}
	}
	if (scalar(@anchors) == 0) {
		push(@anchors, [7, 7]);
	}
	return \@anchors;
}

sub parseBoard {
	my $file = shift;
	local *IN;
	my @board = ();
	my $colCount = undef;
	open(IN, "<$file");
	while(<IN>) {
		chomp;
		my @rowRaw = split(/,/, $_);
		my @row = ();
		if (! defined($colCount)) { $colCount = scalar(@rowRaw); }
		foreach my $cell (@rowRaw) {
		    my @cellData = split(//, $cell);
		    my %cell = ('letterWeight' => $cellData[0], 'wordWeight' => $cellData[1], 'bonusUsed' => 0);
		    push(@row, \%cell);
		}
		push(@board, \@row);
	}
	close(IN);
	my $rowCount = scalar(@board);
	print STDERR "Parsed board weights [$file] ${rowCount}x${colCount}\n";
	return (\@board, $rowCount, $colCount);
}
