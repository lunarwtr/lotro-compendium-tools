#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Encode;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
#use Compress::Zlib;
# use open ':utf8';
# binmode STDOUT, ":utf8";
$|=1;

# autoBestowed, hidden, lockType, maxLevel, requiredClass, requiredFaction, requiredRace, sessionPlay, shareable, size
my %attrmap = ( 
    questArc => 'arcs', name => 'name', description => 'd', category => 'category', level => 'level', minLevel => 'minlevel', 
    id => 'id', repeatable => 'repeatable', monsterPlay => 'faction', instanced => 'instanced'
);
my %moneymap = ( gold => 'g', silver => 's', copper => 'c' );
my $geodb = loadgeodb();
my $poidb = loadpoidb($geodb);

my $filename = 'data/source/lc/general/quests/quests.xml';
# open my $fh, '<', $filename;
# binmode $fh, ':raw';
# $dom = XML::LibXML->load_xml(IO => $fh);
my $dom = XML::LibXML->load_xml(location => $filename);
my @quests = ();
foreach my $quest ($dom->findnodes('//quest')) {

    my %rec = ();
    for my $a ($quest->attributes()) {
        my $key = $attrmap{$a->name};
        next unless ($key);
        $rec{$key} = $a->value;
    }
    $rec{id} = uc(sprintf("%x", $rec{id}));
    $rec{repeatable} = $rec{repeatable} ? 'Yes' : 'No';
    $rec{faction} = $rec{faction} ? 'Mon' : 'FrP';
    $rec{instanced} = defined $rec{instanced} && $rec{instanced} eq 'true' ? 'Yes' : 'No';
    

    if ((my $mapId = $quest->findvalue('./map/@mapId'))) {
        my $geo = $geodb->{$mapId};
        if ($geo) {
            $rec{area} = $geo->{area} if ($geo->{area});
            $rec{zone} = $geo->{territory} if ($geo->{territory});
        }
    }

    my %poilookups = ();
    foreach my $b ($quest->findnodes('./bestower')) {
        $rec{b} = $b->findvalue('./@npcName');
        my $id = $b->findvalue('./@npcId');
        if ($id) {
            $poilookups{'pois'}{$id}++;
            unless (defined $rec{zone}) {
                my $poi = poilookup($id);
                if ($poi) {
                    foreach my $key (qw(zone area)) {
                        $rec{$key} = $poi->{$key} if ($poi->{$key});
                    }
                }
            }
        }
        # TODO: There can be more than one... Do something with other bestowers?
    }

    foreach my $p ($quest->findnodes('./compoundPrerequisite/prerequisite')) {
        # only add prereqs that have a quest name
        push(@{$rec{prev}}, $p->findvalue('./@id')) if ($p->findvalue('./@name'));
    }
    foreach my $p ($quest->findnodes('./prerequisite')) {
        # only add prereqs that have a quest name
        push(@{$rec{prev}}, $p->findvalue('./@id')) if ($p->findvalue('./@name'));
    }
    foreach my $n ($quest->findnodes('./nextQuest')) {
        push(@{$rec{next}}, $n->findvalue('./@id'));
    }

    foreach my $reward ($quest->findnodes('./rewards/*')) {
        my $type = $reward->localname;
        # "destinypoints","virtues","titles","traits"
        if ($type eq 'money') {
            my @moneys = ();
            foreach my $a (qw(gold silver copper)) {
                my $v = $reward->findvalue("./\@$a");
                push(@moneys, "$v$moneymap{$a}") if ($v && $v ne '0');
            }
            push(@{$rec{money}}, { val => join(' ', @moneys)});
        } elsif ($type eq 'reputationItem') {
            my $amount = $reward->findvalue('./@amount');
            $amount = "+$amount" unless ($amount =~ m/^\-/);
            push(@{$rec{reputation}}, "$amount with " . $reward->findvalue('./@faction'))
        } elsif ($type eq 'selectOneOf') {
            foreach my $o ($reward->findnodes('./object')) {
                my %item = itemmap($o);
                push(@{$rec{selectoneof}}, \%item);
            }
        } elsif ($type eq 'object') {
            my %item = itemmap($reward);
            push(@{$rec{receive}}, \%item);
        } elsif ($type eq 'title') {
            my %rec = attmap($reward);
            push(@{$rec{titles}}, { val => $rec{name} });
        } elsif ($type eq 'trait') {
            my %rec = attmap($reward);
            push(@{$rec{traits}}, { val => $rec{name} });
        } elsif ($type =~ m/^(XP|glory|virtueXP|itemXP|mountXP|classPoints|lotroPoints)$/i) {
            push(@{$rec{lc($type)}}, $reward->findvalue('./@quantity'));
        } elsif ($type eq 'craftingXp') {
            # <craftingXp profession="COOK" tier="4" XP="36"/>

        } elsif ($type eq 'virtue') {
            # dont see this much other than single quest 
        } else {
            # unknown
            print "Unknown Reward Type!!! $type\n";
        }
        # destinypoints not given for quests anymore
    }

    my @objectives = ();
    foreach my $o ($quest->findnodes('./objectives/objective')) {
        my %ob = attmap($o);
        my $desc = '';
        $desc .= "$ob{text}\n" if ($ob{text});
        $desc .= "$ob{progressOverride}" if ($ob{progressOverride});
        my @sub = ("Obj $ob{index}:\n$desc");
        foreach my $prog ($o->findnodes('./*[@progressOverride]')) {
            my %att = attmap($prog);
            push(@sub, "* $att{progressOverride}");
        }
        push(@objectives, join("\n", @sub));
        
        foreach my $prog ($o->findnodes('./*[@npcId or @itemId or @mobId]')) {
            my %att = attmap($prog);
            foreach my $key (qw(npcId itemId mobId)) {
                my $id = $att{$key};
                $poilookups{$key eq 'mobId' ? 'mobs' : 'pois'}{$id}++ if ($id);
            }
        }
    }
    if (scalar @objectives > 0) {
        my $o = join('\n', @objectives);
        $o =~ s/\n+/\n/gs;
        $rec{o} = $o;
        #$rec{o} = compress(encode('utf-8', $o), 9);
    }

    while (my($type, $pref) = each %poilookups) {
        foreach my $id (keys %{$pref}) {
            my $poi = poilookup($id);
            if ($poi) {
                push(@{$rec{$type}}, $poi);
            }
        }
    }
    push(@quests, \%rec);
    # my %reg = (
    #     arcs => "The Path of the Mischief Maker",
    #     b => "Celofa",
    #     category => "Burglar",
    #     d => "Celofa has tasked you with slaying the Orc Bidroi to further your advancement as a Burglar.",
    #     faction => "FrP",
    #     id => 1,
    #     instanced => "No",
    #     level => 58,
    #     minlevel => 58,
    #     money => {{val => "27s 65c"}},
    #     name => "A Bag of Tricks",
    #     next => {2729},
    #     o => "Obj 1:\nThe Orc Bidroi can be found on the bottom floor of the Second Hall where he fell from befuddlement. The Second Hall is north of the Foundations of Stone and east of Zelem-Melek.\nCelofa looks forward to sharing some new skills as an advanced Burglar, but has first tasked you with a simple deed: to defeat the Orc Bidroi.\n* Defeat Bidroi\nObj 2:\nCelofa can be found in the Shadowed Refuge in the northern reaches of the Foundations of Stone in Moria.\nNow that you've defeated Bidroi, you should return to Celofa so that she may begin to teach you her advanced Burglar skills.\n* Return to Celofa",
    #     prev => {2510},
    #     repeatable => "No",
    #     scope => "n/a"
    # );
    # print $quest->findvalue('./@id') . "\n";

    # <quest id="1879143801" name="A Bag of Tricks" category="Burglar" level="58" 
    # questArc="The Path of the Mischief Maker" minLevel="58" requiredClass="Burglar" 
    # description="Celofa has tasked you with slaying the Orc Bidroi to further your advancement as a Burglar.">
    # <bestower npcId="1879143752" npcName="Celofa" text="'I am glad you are here, ${PLAYER}; well met, indeed! For I'm Celofa, Mistress of Riddles. How I love riddling! I can see by the twinkle in your eye that you know just how I feel on this matter.&#10;&#10;'I shall be happy to trade some riddlish skill with you, but first I have a more mundane task. Complete it, and the riddling will begin!&#10;&#10;'There's a nasty Orc, Bidroi, down in the Eastern Deeps. He doesn't like riddles, that one. I seem to have upset him when I told him a terribly befuddling one, and he was so confused that he fell right down a set of stairs into a great hole, and had to shout and roar for his fellows to come and free him. He is not very happy now, and is rather a threat to the good people here, I'm afraid. Deal with him, and then return to me.'"/>
    # <objectives>
    # <objective index="1" text="The Orc Bidroi can be found on the bottom floor of the Second Hall where he fell from befuddlement. The Second Hall is north of the Foundations of Stone and east of Zelem-Melek.&#10;&#10;Celofa looks forward to sharing some new skills as an advanced Burglar, but has first tasked you with a simple deed: to defeat the Orc Bidroi.">
    # <dialog npcId="1879143752" npcName="Celofa" text="'Before I continue your instruction, I want you to defeat Bidroi...you should find him in the lowest level of the Second Hall.'"/>
    # <monsterDied index="0" progressOverride="Defeat Bidroi" mobId="1879143837" mobName="Bidroi"/>
    # </objective>
    # <objective index="2" text="Celofa can be found in the Shadowed Refuge in the northern reaches of the Foundations of Stone in Moria.&#10;&#10;Now that you've defeated Bidroi, you should return to Celofa so that she may begin to teach you her advanced Burglar skills.">
    # <dialog npcId="1879143752" npcName="Celofa" text="'Splendid!  Now let us begin our game of riddles.'"/>
    # <npcTalk index="0" progressOverride="Return to Celofa" showBillboardText="false" npcId="1879143752" npcName="Celofa"/>
    # </objective>
    # </objectives>
    # <compoundPrerequisite>
    # <prerequisite id="1879048563" name="Prologue: To a Ranger's Aid" operator="NOT_EQUAL" status="UNDERWAY2"/>
    # <prerequisite id="1879049232" operator="NOT_EQUAL" status="UNDERWAY"/>
    # </compoundPrerequisite>
    # <nextQuest id="1879048570" name="Book 1, Chapter 2: To a Constable's Aid"/>
    # <rewards>
    # <money gold="0" silver="1" copper="80"/>
    # <reputationItem factionId="1879091340" faction="Men of Bree" amount="900"/>
    # <XP quantity="555"/>
    # <selectOneOf>
    # <object id="1879049233" name="Hengaim"/>
    # <object id="1879085310" name="Menedgaim"/>
    # <object id="1879049234" name="Cloak of Cardolan"/>
    # </selectOneOf>
    # </rewards>
    # <itemXP quantity="4590"/>
    # </rewards>
    # </quest>
    # (
    #     #scope => "n/a"
    #     './besower/@npcName' => 'b',
    #         # repeatable="-1" lockType="DAILY" monsterPlay
    #     money => 'money',
    #     next => 'next',
    #     o => 'o',
    #     prev => 'prev',
    # )


    # {
    #     arcs = "Forts of Taur Morvith",
    #     area = "Taur Morvith",
    #     b = "Iavassúl",
    #     c = {
    #         "* There are Orc War-banners around the Orc camps in Taur Morvith, at [17.0S, 50.8W],  [17.1S, 50.4W], [17.3S, 50.6W], [17.3S, 50.9W], [17.1S, 50.1W], [16.9S, 50.3W]"
    #     },
    #     category = "Mirkwood",
    #     d = "The Elf Iavassúl and his companions are tasked with preventing the Orcs of Taur Morvith from closing in behind the main force of the Malledhrim.",
    #     faction = "FrP",
    #     id = 2,
    #     instanced = "No",
    #     level = 64,
    #     minlevel = 59,
    #     mobs = {
    #         {
    #             locations = {"16.60S, 50.55W"},
    #             name = "Iavassúl",
    #             zone = "Mirkwood"
    #         }
    #     },
    #     money = {{val = "28s 35c"}},
    #     name = "A Banner Day",
    #     ["next"] = {1338, 2286},
    #     o = "Obj 1:\nOrkish war-banners can be found in Krul Lugu below Iavassúl's Watch.\nIavassúl has asked you to destroy several of the Orcs' war-banners to demoralize the Enemy.\n* Use Orc War-banner\nObj 2:\nIavassúl is at Iavassúl's Watch, above Krul Lugu.\nYou should return to Iavassúl and inform him that the Orkish banners have been destroyed.\n* Talk to Iavassúl at Iavassúl's Watch",
    #     pois = {
    #         {
    #             locations = {
    #                 "16.60S, 50.11W", "16.74S, 50.98W", "16.90S, 50.31W",
    #                 "17.01S, 50.76W", "17.09S, 50.12W", "17.12S, 50.41W",
    #                 "17.28S, 50.56W", "17.32S, 50.92W"
    #             },
    #             name = "Orc War-banner",
    #             zone = "Mirkwood"
    #         },
    #         {
    #             locations = {"17.0S, 50.8W"},
    #             name = "Taur Morvith",
    #             zone = "Mirkwood"
    #         }
    #     },
    #     receive = {
    #         {id = "7001F099", q = "(x3)", val = "Malledhrim Bronze Feather"}
    #     },
    #     repeatable = "No",
    #     reputation = {{val = "+500 with Malledhrim"}},
    #     scope = "n/a",
    #     zone = "Mirkwood"
    # }

}


open INDEX, ">:utf8", "CompendiumQuestsDB.lua";

print INDEX <<EOB;
--[[
   Copyright 2011 Kelly Riley (lunarwater)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
]]
questtable = {
EOB
my $index = 1;
foreach my $q (@quests) {
    print INDEX ",\n" if ($index > 1) ;
	print INDEX string($q);
    $index++; 
}
print INDEX <<EOB;
};
EOB

exit;

sub geopath {
    my($geosref, $c, $r) = @_;
    if ($c->{parentId}) {
        geopath($geosref, $geosref->{$c->{parentId}}, $r);
    }
    $r->{$c->{type}} = $c->{name};
}

sub dungpath {
    my($georef, $c, $vals) = @_;
    return if (defined $georef->{$c->{id}});
    while (my($k,$v) = each %{$vals}) {
        $c->{$k} = $v;
    }
    $c->{dungeon} = $c->{name};
    #delete $c->{name};
    $georef->{$c->{id}} = $c;
    if (defined $c->{dungeons}) {
        foreach my $d (@{$c->{dungeons}}) {
            dungpath($georef, $d, $vals);
        }
    }
    if (defined $c->{parents}) {
        foreach my $d (@{$c->{parents}}) {
            dungpath($georef, $d, $vals);
        }
    }
}

sub loadgeodb {
    my $geodbfile = 'geo.db';
    if (-e $geodbfile) {
        return retrieve($geodbfile);
    }
    my %geos = ();
    my %geobyname = ();
    my $geodom = XML::LibXML->load_xml(location => 'data/source/lc/general/maps/geoAreas.xml');
    foreach my $g ($geodom->findnodes('//geoAreas/*')) {
        my %rec = attmap($g);
        $rec{type} = $g->localname;
        $geos{$rec{id}} = \%rec;
        if ($rec{parentId}) {
            geopath(\%geos, \%rec, \%rec);
        }
    }
    while (my($id,$rec) = each %geos) {
        $geobyname{$rec->{name}} = $rec;
    }
    my %maps = ();
    my $mapdom = XML::LibXML->load_xml(location => 'data/source/lc/maps/maps/maps.xml');
    foreach my $g ($mapdom->findnodes('//map')) {
        my %rec = attmap($g);
        my $id = $rec{id};
        my $geo = $geos{$id};
        $maps{$id} = \%rec;
        if (length($id) < 10 && $geobyname{$rec{name}}) {
            $geos{$id} = $geobyname{$rec{name}};
        }
    }
    $mapdom = XML::LibXML->load_xml(location => 'data/source/lc/maps/links.xml');
    my %scanme = ();
    foreach my $g ($mapdom->findnodes('//links/*')) {
        my %rec = attmap($g);
        my $id = $rec{parentId};
        if (length($id) < 10) {
            next;
        }
        my $target = $rec{target};
        my $geo = $geos{$id};

        if ($geo) {
            my $rec = $maps{$target};
            my %vals = ();
            foreach my $key (qw(region territory area)) {
                $vals{$key} = $geo->{$key} if ($geo->{$key});
            }
            $vals{parentId} = $id;
            $scanme{$target} = \%vals;
        } else {
            push(@{$maps{$target}{parents}}, $maps{$id});
            push(@{$maps{$id}{dungeons}}, $maps{$target});
        }
    }
    while (my($root,$vals) = each %scanme) {
        dungpath(\%geos, $maps{$root}, $vals);
    }
    store(\%geos, $geodbfile);
	return \%geos;
}

sub loadpoidb {
    my($geos) = @_;
    my $poidbfile = 'poi.db';
    if (-e $poidbfile) {
        return retrieve($poidbfile);
    }
   
    my %cats = ();
    my $catdom = XML::LibXML->load_xml(location => 'data/source/lc/maps/categories/categories.xml');
    foreach my $c ($catdom->findnodes('//category')) {
        $cats{$c->findvalue('./@code')} = $c->findvalue('./@name');
    }
    my %poidb = ();
    foreach my $file (glob("data/source/lc/maps/markers/*.xml")) {
        my $poidom = XML::LibXML->load_xml(location => $file);
        foreach my $m ($poidom->findnodes('//marker')) {    
            my %rec = attmap($m);
            my $cat = $cats{$rec{category}};
            my $did = $rec{did};
            if (!$rec{parentZoneId}) {
                next;
            }
            my $zoneid = $rec{parentZoneId};
            my $geo = $geos->{$zoneid};
            if ($geo) {
                delete $rec{parentZoneId};
            } else {
                #print "NO GEO DATA FOR $rec{parentZoneId}!!!\n";
                next;
            }
            $poidb{$did}{label} = $rec{label};
            $poidb{$did}{type} = $cat;
            foreach my $key (qw(dungeon region territory area)) {
                my $to = $key eq 'territory' ? 'zone' : $key;
                $poidb{$did}{zones}{$zoneid}{$to} = $geo->{$key} if ($geo->{$key});
            }
            delete $rec{label};
            delete $rec{did};
            delete $rec{category};
            push(@{$poidb{$did}{zones}{$zoneid}{coors}}, \%rec);
        }
    }
    
	store(\%poidb, $poidbfile);
	return \%poidb;
}

sub string {
	my($val) = @_;
	if (ref($val) eq 'HASH') {
		my $newval = "{";
		my $count = 0;
		#while (my($k,$v) = each %{ $val }) {
		foreach my $k (sort keys %{ $val }) {
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
    } elsif ($val =~ /[^[:print:]]/s) {
        $val =~ s/"/\\"/gs;
        return "\"$val\"";
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

sub poilookup {
    my($id) = @_;
    my $poi = $poidb->{$id};
    if ($poi) {
        my $label = $poi->{label};
        $label =~ s/\n.*$//s;
        my %rec = (
            name => $label
            #type = $poi->{type}
        );
        while (my($zid,$zref) = each %{$poi->{zones}}) {
            #unless ($rec{zone}) {
                foreach my $key (qw(zone area)) {
                    $rec{$key} = $zref->{$key} if ($zref->{$key});
                }
                foreach my $coor (@{$zref->{coors}}) {
                    my $ew = coorround($coor->{longitude});
                    $ew = $ew < 0 ?  (- $ew)."W" : "${ew}E";
                    my $ns = coorround($coor->{latitude});
                    $ns = $ns < 0 ?  (- $ns)."S" : "${ns}N";
                    push(@{$rec{locations}}, "$ns, $ew");
                }
            #}
            return \%rec;
            # TODO: Determine what to do with other zones
        }
    }

}

sub coorround {
    my($v) = @_;
    return int($v * 10)/10;
}