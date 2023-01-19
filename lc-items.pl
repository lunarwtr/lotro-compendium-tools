#!/usr/bin/perl

use lib '.';
use strict;
use warnings;
use utf8;
use Encode;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
use Compendium;
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

