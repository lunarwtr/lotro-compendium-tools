#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Encode;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
use JSON;
$|=1;

my $itemdb = loaditemdb();


exit;

sub loaditemdb {
    my $itemdbfile = 'item.db';
    if (-e $itemdbfile) {
        return retrieve($itemdbfile);
    }

    my $statdb = loadstatsdb();
    my $setdb = loadsetsdb();
    my $classdb = loaditemclassdb();

    my $filename = 'data/source/lc/items/items.xml';
    my $outputdir = 'data/output/Compendium/Items';

    my $dom = XML::LibXML->load_xml(location => $filename);
    my @items = ();

    my %bindmap = (
        BIND_ON_ACQUIRE => 'BoA', BIND_ON_EQUIP => 'BoE', BOUND_TO_ACCOUNT_ON_ACQUIRE => 'Bind on Acct'
    );
    my %catmap = (
        ARMOUR             => 'Armour',
        CARRY_ALL          => 'Carry All',
        ITEM               => 'Item',
        LEGENDARY_ITEM     => 'Legendary Item',
        LEGENDARY_ITEM2    => 'Legendary Item',
        LEGENDARY_WEAPON   => 'Legendary Weapon',
        LEGENDARY_WEAPON2  => 'Legendary Weapon',
        WEAPON             => 'Weapon'
    );
    my %qualmap = ('COMMON' => 'c', 'INCOMPARABLE' => 'i', 'LEGENDARY' => 'l', 'RARE' => 'r', 'UNCOMMON' => 'u');

    foreach my $item ($dom->findnodes('/items/item')) {

        my %att = attmap($item);
        # <item 
        # key="1879049234" 
        # name="Cloak of Cardolan" 
        # icon="1090522482-1090519042-1090522484-1090522483"
        # level="15" 
        # slot="BACK" 
        # category="ARMOUR" 
        # class="45" 
        # binding="BIND_ON_ACQUIRE" 
        # durability="40" 
        # sturdiness="NORMAL" 
        # quality="UNCOMMON" 
        # valueTableId="1879049501" 
        # armourType="LIGHT">

        # my %rec = ( type => $type, name => $title, id => $id, 
        # rt => $rt, quality => $quality, level => $level, rlevel => $rlevel );
        my %rec = (
            id => tohex($att{key}),
            class => $classdb->{$att{class}}{name},
            name => $att{name},
            level => $att{level}
        );

        $rec{quality} = $qualmap{$att{quality}} if ($att{quality});
        $rec{binding} = $bindmap{$att{binding}} if ($att{binding});
        $rec{cat} = $catmap{$att{category}} if ($att{category});

        # property, grants, 
        foreach my $n ($item->findnodes('./stats/stat')) {
            my $stat = $statdb->{$n->findvalue('./@name')};
            push(@{$rec{stats}}, $stat->{name});
        }

        my $set = $setdb->{$att{key}};
        if ($set) {
            $rec{itemset} = $set->{name};
        }
        # my %keymap = (
        #     'cat' => 'c',
        #     'name' => 'n',
        #     'id' => 'id',
        #     'quality' => 'q',
        #     'level' => 'l',
        #     'rlevel' => 'rl',
        #     'class' => 'cl',
        #     'legacy' => 'lg',
        #     'itembind' => 'ib',
        #     'nt' => 'nt'
        # );

        push(@items, \%rec);
        
    }

    store(\@items, $itemdbfile);
    return \@items;
}

sub loadstatsdb {
    return loadmap('stat.db', 'data/source/lc/general/common/stats.xml', '/stats/stat', 'legacyKey');
}
sub loadsetsdb {
    my $dbfile = 'set.db';
    if (-e $dbfile) {
        return retrieve($dbfile);
    }
    my %items = ();
    my $dom = XML::LibXML->load_xml(location => 'data/source/lc/general/items/sets.xml');
    foreach my $s ($dom->findnodes('/sets/set')) {
        my %set = attmap($s);
        foreach my $i ($s->findnodes('./item')) {
            $items{$i->findvalue('./@id')} = \%set;
        }
    }
    store(\%items, $dbfile);
	return \%items;
}
sub loaditemclassdb {
    return loadmap('itemclass.db', 'data/source/lc/general/common/enums/ItemClass.xml', '//entry', 'code');
}
sub loadmap {
    my($dbfile, $xmlfile, $nodexpath, $keyattr) = @_;
    if (-e $dbfile) {
        return retrieve($dbfile);
    }
    my %db = ();
    my $dom = XML::LibXML->load_xml(location => $xmlfile);
    foreach my $p ($dom->findnodes($nodexpath)) {
        my %rec = attmap($p);
        $db{$rec{$keyattr}} = \%rec if (defined $rec{$keyattr});
    }
    store(\%db, $dbfile);
	return \%db;
}

sub sortkey {
    if ($a eq $b) {
        return 0;
    } elsif ($a =~ m/^(id|name)$/ && $b =~ m/^(id|name)$/) {
        return $a cmp $b;
    } elsif ($a =~ m/^(id|name)$/ && $b ne $a) {
        return -1;
    } elsif ($b =~ m/^(id|name)$/ && $b ne $a) {
        return 1;
    } else {
        return $a cmp $b;
    }
}

sub string {
	my($val) = @_;
	if (ref($val) eq 'HASH') {
		my $newval = "{";
		my $count = 0;
		#while (my($k,$v) = each %{ $val }) {
		foreach my $k (sort sortkey keys %{ $val }) {
			my $v = $val->{$k};
			my $hk = string($k);
			if ($hk =~ m/^"(next|\d+)"$/) {
				$hk = "[".$hk."]";
			} else {
				$hk =~ s/^"(.*?)"$/$1/is;
			}
			my $hv = string($v);
			$newval .= "," if ($count > 0);
			$newval .= "$hk=$hv";
			$count++;
		}
		$newval .= "}";
		return $newval;
	} elsif (ref($val) eq 'ARRAY') {
		my $newval = "{";
		my $count = 0;
		foreach my $item (sort @{ $val }) {
			$newval .= "," if ($count > 0);
			$newval .= string($item); 
			$count++;
		}
		$newval .= "}";
		return $newval;
    # } elsif ($val =~ /[^[:print:]]/s) {
    #     $val =~ s/"/\\"/gs;
    #     return "\"$val\"";
	} else {
		return escapelua($val);
	}
}

sub escapelua {
	my($val) = @_;
	$val =~ s/\s+$//s;
	$val =~ s/^\s+//s;
	$val =~ s/\\/\\\\/gis;
	$val =~ s/\s*\n\s*/\\n/gis;
	$val =~ s/\s*\r\s*/\\r/gis;
	$val =~ s/"/\\"/gis;
	$val = $val =~ m/^\d+$/ ? "$val" : "\"$val\"";
	return $val;
}

sub attmap {
    my($n) = @_;
    return map { $_->name => $_->value } $n->attributes();
}

sub itemmap {
    my($n) = @_;
    my %rec = attmap($n);
    my %item = ( id => uc(sprintf("%x", $rec{id})), val => $rec{name} );
    $item{q} = $rec{quantity} if ($rec{quantity});
    return %item;
}

sub tohex {
    my($id) = @_;
    return uc(sprintf("%x", $id));
}

sub loadfile {
    my ($file, $encoding) = @_;
	#print "$file\n";
    my $data = do {
        local $/ = undef;
        open my $fh, "<$encoding", $file or die "Cannot open $file";
        <$fh>;
    };	
    return $data;
}
