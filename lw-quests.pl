#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use JSON;
use Storable qw(store retrieve);
use File::Path qw(make_path);
use Time::HiRes ();
use XML::LibXML;
use HTML::Entities;
use List::Util qw(first);

$|=1;

my $wikidb = loadwikidb();
print "Done\n";

############################################################
# MAIN LOADER
############################################################
sub loadwikidb {

    my $questdbfile = 'wiki-quest.db';
    if (-e $questdbfile) {
        return retrieve($questdbfile);
    }

    my $lcquestdbfile = 'quest.db';
    die "No compendium quest db found!" unless (-e $lcquestdbfile);
    
    my $compquest = retrieve($lcquestdbfile);
    my %questsbyname = ();
    my %questsbynac = ();
    foreach my $q (@$compquest) {
        foreach my $name (title_variants(lc($q->{name}), 1)) {
            $questsbyname{$name} = $q;
            my $cat = lc($q->{category});
            $cat = lc($q->{area}) if ($cat eq 'introduction' && defined $q->{area});
            $cat =~ s/^The\s+//si;
            $questsbynac{"$name|$cat"} = $q;
        }
    }
    my %quests;

    ############################################################
    # FIRST: Get all pages that embed the Infobox_Quests template
    ############################################################
    my $base_url =
        'https://lotro-wiki.com/w/api.php?action=query&list=embeddedin'
      . '&eititle=Template:Infobox_Quests'
      . '&einamespace=102'
      . '&eilimit=max'
      . '&format=json';

    my %continue;
    my $page = 1;
    my @pageids;

    while (1) {
        my $url = $base_url;

        if (%continue) {
            $url .= "&eicontinue=$continue{eicontinue}" if $continue{eicontinue};
            $url .= "&continue=$continue{continue}"     if $continue{continue};
        }

        my $json = decode_json(
            get_page($url, "$page.json", ".cache", undef)
        );

        push @pageids, map { $_->{pageid} } @{ $json->{query}{embeddedin} };

        if ($json->{continue}) {
            %continue = %{ $json->{continue} };
        } else {
            last;
        }

        $page++;
    }

    print "Found " . scalar(@pageids) . " quest pages\n";

    ############################################################
    # NEXT: Fetch parsed HTML for each page immediately
    ############################################################
    foreach my $id (@pageids) {

        my $html_json = fetch_parsed_html($id);
        next unless $html_json->{parse}{text}{'*'};

        my $title = $html_json->{parse}{title} // "Unknown";
        my $html = $html_json->{parse}{text}{'*'};

		# $html is the HTML string returned from action=parse
		my $parser = XML::LibXML->new();
		$parser->recover(1);               # tolerate malformed HTML
		my $dom = $parser->load_html(
			string => $html,
			recover         => 1,
    		suppress_errors => 1,
		);

        my ($region_node) = $dom->findnodes('//td[normalize-space()="Start Region"]/following-sibling::td[1]');
        # my $name = lc($title);
        # $name =~ s/^Quest\:\s*//i;        
        # my $cat = '';
        # if ($region_node) {
        #     $cat = lc(trim($region_node->textContent));
        #     $cat =~ s/^The\s+//i;
        # }
        # my $qrec = $questsbynac{"$name|$cat"} if ($region_node);
        # $qrec = $questsbyname{$name} unless ($qrec);
        # unless ($qrec) {
        #     $name =~ s/\s+\([^)]+\)\s*$//;
        #     if ($region_node) {
        #         $qrec = $questsbynac{"$name|$cat"};
        #     }
        #     $qrec = $questsbyname{$name} unless ($qrec);
        # }
        my $qrec = match_quest($title, $region_node, \%questsbynac, \%questsbyname);

		# XPath that checks the first TH under the table (case-insensitive)
		my $lc_translate = "translate(normalize-space(.//th[1]), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')";
		my $xpath = qq{//table[ contains( $lc_translate, 'walkthrough' ) ]//tr[2]/td};

		my ($node) = $dom->findnodes($xpath);
        
        if ($node) {
            if ($qrec) {
                my $walkhtml = $node->toString(1);
                my $clean = sanitize(html_to_text($node));
                $quests{$qrec->{id}} = [$clean] if ($clean !~ /walkthrough and notes pending/i);
            } else {
                print "No quest match ($id) $title\n";
            }
            #print "Extracted Walkthrough for $title\n";
        } elsif ($html =~ /walkthrough/is) {
            print "Funky walkthrough ($id) $title\n";
        } else {
            #print "No Walkthrough found for $title\n";
        }
    }

    store \%quests, $questdbfile;
    return \%quests;
}

############################################################
# FETCH PARSED HTML USING action=parse
############################################################
sub fetch_parsed_html {
    my ($pageid) = @_;

    my $url = "https://lotro-wiki.com/w/api.php?action=parse&pageid=$pageid&prop=text&format=json";

    my $json = get_page($url, "page-$pageid.json", ".cache/parsed", undef);
    return decode_json($json);
}

############################################################
# GET WITH CACHE + RETRIES
############################################################
sub get_page {
    my ($url, $name, $path, $refresh) = @_;

    make_path($path) unless -e $path;

    my $file;

    if ($name) {
        $file = "$path/$name";
    } else {
        $file = $url;
        $file =~ s/^https?:\/\///i;
        $file =~ s/\W+/_/g;
        $file = "$path/$file.json";
    }

    if ($refresh && -e $file) {
        unlink($file);
    }

    if (-e $file) {
        open(my $in, "<:utf8", $file) or die "Cannot open $file";
        local $/;
        return <$in>;
    }

    my $ua = LWP::UserAgent->new();
    $ua->timeout(15);
    $ua->agent('Mozilla/5.0');

    my $response;
    my $failcount = 0;

    do {
        Time::HiRes::sleep(0.5) if $failcount > 0;
        $response = $ua->get($url);
    } while ($failcount++ < 25 && !$response->is_success);

    die "Failed to fetch $url" unless $response->is_success;

    my $content = $response->decoded_content();

    open(my $out, ">:utf8", $file) or die "Cannot write $file";
    print $out $content;
    close $out;

    #Time::HiRes::sleep(0.25);
	sleep(1);

    return $content;
}

############################################################
# Placeholder for your later cleanup function
############################################################
# sub cleanup_walkthrough {
#     my ($html) = @_;
#     ... your DOM cleanup here ...
#     return $clean;
# }

sub htmldecode {
	my($html) = @_;
	$html =~ s/(&nbsp;|&#160;)/ /gis;
	$html = HTML::Entities::decode($html);	
	return $html;
}

sub striptags {
	my ($html) = @_;
	$html =~ s/<[^>]+>//gis;
	$html = htmldecode($html);
	return trim($html);
}
sub sanitize {
	my ($html, $nonl) = @_;
	$html =~ s/\\n/\n/gs;
	$html =~ s/<br\s*?\/?>/\n/gs;
	$html = striptags($html);
	$html =~ s/\r\n/\n/gis;
	$html =~ s/\r/\n/gis;
	if ($nonl) {
		$html =~ s/\n+/ /gs;
		$html =~ s/\s+/ /gs;
	}
	return trim($html);
}
sub trim {
	my($str) = @_;
	$str =~ s/^\s+//s;
	$str =~ s/\s+$//s;
	return $str;
}

use XML::LibXML;

use XML::LibXML;

sub html_to_text {
    my ($node, $depth) = @_;
    $depth ||= 0;
    my $indent = '  ' x $depth;
    my $out = '';

    # Text node (nodeType == 3)
    if ($node->nodeType == 3) {
        my $t = $node->textContent;
        return '' if $t =~ /^\s*$/;        # skip pure whitespace nodes
        $t =~ s/\s+/ /g;                   # collapse internal whitespace
        return $t;
    }

    # Element nodes (nodeType == 1)
    return '' unless $node->nodeType == 1;
    my $name = lc $node->nodeName;

    # Inline/flow controls
    if ($name eq 'br') {
        return "\n";
    }

    # Paragraphs and headings
    if ($name =~ /^p$|^div$|^h[1-6]$|^header$|^section$/) {
        for my $child ($node->childNodes) { $out .= html_to_text($child, $depth) }
        $out =~ s/^\s+|\s+$//g;
        return $out . "\n\n";
    }

    # Definition lists: show dt then dd on next line
    if ($name eq 'dl') {
        for my $child ($node->childNodes) {
            next unless $child->nodeType == 1;
            if (lc $child->nodeName eq 'dt') {
                my $t = html_to_text($child, $depth);
                $t =~ s/^\s+|\s+$//g;
                $out .= $t . "\n";
            }
            elsif (lc $child->nodeName eq 'dd') {
                my $t = html_to_text($child, $depth + 1);
                $t =~ s/^\s+|\s+$//g;
                $out .= $indent . $t . "\n";
            }
            else {
                $out .= html_to_text($child, $depth);
            }
        }
        return $out . "\n";
    }

    # Unordered list
    if ($name eq 'ul') {
        for my $li ($node->findnodes('./li')) {
            my $li_text = html_to_text($li, $depth + 1);
            $li_text =~ s/^\s+|\s+$//g;
            $out .= $indent . '* ' . $li_text . "\n";
        }
        return $out . "\n";
    }

    # Ordered list
    if ($name eq 'ol') {
        my $i = 1;
        for my $li ($node->findnodes('./li')) {
            my $li_text = html_to_text($li, $depth + 1);
            $li_text =~ s/^\s+|\s+$//g;
            $out .= $indent . $i . '. ' . $li_text . "\n";
            $i++;
        }
        return $out . "\n";
    }

    # List item: concatenate children but leave newline handling to parent
    if ($name eq 'li') {
        for my $child ($node->childNodes) { $out .= html_to_text($child, $depth) }
        $out =~ s/\s+/ /g;
        $out =~ s/^\s+|\s+$//g;
        return $out;
    }

    # Tables: iterate rows; join cells with " — " then newline per row
    if ($name eq 'table') {
        for my $tr ($node->findnodes('.//tr')) {
            my @cells;
            for my $cell ($tr->findnodes('./th|./td')) {
                my $cell_text = html_to_text($cell, $depth);
                $cell_text =~ s/^\s+|\s+$//g;
                push @cells, $cell_text if length $cell_text;
            }
            next unless @cells;
            $out .= join(" — ", @cells) . "\n";
        }
        return $out . "\n";
    }

    # Table cell fallback (td/th) - just return concatenated children
    if ($name eq 'td' || $name eq 'th') {
        for my $child ($node->childNodes) { $out .= html_to_text($child, $depth) }
        $out =~ s/^\s+|\s+$//g;
        return $out;
    }

    # Generic element: walk children
    for my $child ($node->childNodes) {
        $out .= html_to_text($child, $depth);
    }

    return $out;
}

# Post-process helper to clean up stray spacing/newlines (call after conversion)
sub normalize_text {
    my ($txt) = @_;
    # trim
    $txt =~ s/^\s+|\s+$//g;
    # collapse spaces at line starts
    $txt =~ s/^[ \t]+//mg;
    # collapse 3+ newlines into 2
    $txt =~ s/\n{3,}/\n\n/g;
    return $txt . "\n";
}

sub normalize_title {
    my ($t) = @_;
    $t = lc($t);
    $t =~ s/^quest:\s*//i;
    $t =~ s/^\s+|\s+$//g;
    $t =~ s/\s+/ /g;
    return $t;
}

sub title_variants {
    my ($t, $skip_parens) = @_;

    my @variants;

    push @variants, $t;

    if (!$skip_parens && $t =~ /\(.*\)/) {
        # Remove trailing parentheses: "Something (Solo)" → "Something"
        (my $no_paren = $t) =~ s/\s*\([^)]+\)\s*$//;
        push @variants, $no_paren unless $no_paren eq $t;
        (my $nopunct = $no_paren) =~ s/[[:punct:]]//g;
        push @variants, $nopunct unless $nopunct eq $t;
    }

    # Remove punctuation entirely
    (my $nopunct = $t) =~ s/[[:punct:]]//g;
    push @variants, $nopunct unless $nopunct eq $t;

    # Remove "the" prefix (common region/title noise)
    # (my $nothe = $t) =~ s/^the\s+//;
    # push @variants, $nothe unless $nothe eq $t;

    # Deduplicate while preserving order
    my %seen;
    @variants = grep { !$seen{$_}++ } @variants;

    return @variants;
}

sub match_quest {
    my ($title, $region_node, $questsbynac, $questsbyname) = @_;

    my $norm = normalize_title($title);

    my $region = '';
    if ($norm =~ m/^(intro:.*?)\s*\(([^)]+)\)/i) {
        $region = lc($2);
        $norm = $1;
    } elsif ($region_node) { 
        $region = lc($region_node->textContent);
    }
    $region =~ s/^\s+|\s+$//g;
    $region =~ s/^the\s+//i;

    my @candidates = title_variants($norm);

    # Try region-specific matches first
    if ($region) {
        foreach my $c (@candidates) {
            my $key = "$c|$region";
            return $questsbynac->{$key} if exists $questsbynac->{$key};
        }
    }

    # Fallback: match by name only
    return first { defined $_ } map { $questsbyname->{$_} } @candidates;
}
