#!/usr/bin/perl

use lib '/home/kriley/workspace/lotro-compendium-tools/';
use strict;
use warnings;
use utf8;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
use Compendium;
use JSON;
$|=1;

my $questdb = loadquestdb();

open INDEX, ">:utf8", "data/output/Compendium/Quests/CompendiumQuestsDB.lua";

print INDEX <<EOB;
---\@diagnostic disable
---\@alias boolstr '"Yes"' | '"No"'

---\@class POI
---\@field name string name of quest
---\@field area? string
---\@field zone string
---\@field dungeon? string
---\@field locs string[]

---\@class Quest
---\@field id string hex id of quest
---\@field name string name of quest
---\@field area string
---\@field zone string
---\@field dungeon string
---\@field b string
---\@field category string
---\@field d string description
---\@field faction '"FrP"' | '"Mob"'
---\@field instance boolstr
---\@field level number | '"Scaling"'
---\@field minlevel number | '"Scaling"'
---\@field mobs POI[]
---\@field pois POI[]
---\@field ndx number
---\@field o string
---\@field repeatable boolstr

---\@type Quest[]
questtable = {
EOB

my %rewardlabels = (
    xp => 'XP',
    cp => 'Class Points',
    cx => 'Crafting XP',
    em => 'Emotes',
    gl => 'Glory',
    ix => 'Item XP',
    lp => 'Lotro Points',
    mo => 'Money',
    mx => 'Mount XP',
    rc => 'Items',
    ri => 'Rep Item',
    so => 'Items',
    ti => 'Titles',
    tr => 'Traits',
    vr => 'Virtues',
    vx => 'Virtue XP'
);

my %menu = (
    "Progression" => {
        "Complete" => 1,
        "Incomplete" => 1
    }
);
my %questitems = ();
my %levels = ();
my %zones = ();
my %arcs = ();
my %indexes = ();
my $index = 1;
my %questtoindex = ();
my @levelranges = ();
my @orderedquests = sort { $a->{name} cmp $b->{name} } @{ $questdb };
foreach my $q (@orderedquests) {
	$questtoindex{$q->{id}} = $index;
	$index++;
}
for (my $i = 1; $i <= 150; $i += 5) {
	push(@levelranges,[ $i, $i + 4]);
}
$index = 1;
foreach my $q (@orderedquests) {
	my $mobs = $q->{'mobs'};
	my $locs = $q->{'pois'};
	
	if ($q->{'next'}) {
        # replace next with quest offsets
		my @newnext = ();
		foreach my $id (@{ $q->{'next'} }) {
			my $nindex = $questtoindex{$id};			
			push(@newnext, $nindex) if ($nindex);
		}
		if (scalar @newnext > 0) {
			$q->{'next'} = \@newnext;
		} else {
			delete $q->{'next'};
		}		
	}
	if ($q->{'prev'}) {
        # replace prev with quest offsets
		my @newprev = ();
		foreach my $id (@{ $q->{'prev'} }) {
			my $pindex = $questtoindex{$id};
			push(@newprev, $pindex) if ($pindex);
		}
		if (scalar @newprev) {
			$q->{'prev'} = \@newprev;
		} else {
			delete $q->{'prev'};
		}		
	}
    $q->{'ndx'} = $index;
	my %rec = %{ $q };
	# build arc index
	if ($q->{'arcs'}) {
		my $aname = $q->{'arcs'};
		push(@{ $arcs{$aname} }, $index);
		push(@{$indexes{'Quest Chains'}}, $index);
		push(@{$indexes{$aname}}, $index);
		if ($aname =~ m/^((Vol.|Volume) \w+)/i) {
			$menu{'Quest Chains'}{'Epics'}{$1}{$aname} = 1;
		} elsif ($aname =~ m/Epic Prologue/i) {
			$menu{'Quest Chains'}{'Epics'}{'Prologue'}{$aname} = 1;
		} elsif ($aname =~ m/(The Black Book of Mordor|The Legacy of Durin and the Trials of the Dwarves)/i) {
			$menu{'Quest Chains'}{'Epics'}{$aname} = 1;
		} elsif ($aname =~ m/^The\s+([a-i])/i) {
			$menu{'Quest Chains'}{'A-I'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^The\s+([j-z])/i) {
			$menu{'Quest Chains'}{'J-Z'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^([a-i])/i) {
			$menu{'Quest Chains'}{'A-I'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^([j-z])/i) {
			$menu{'Quest Chains'}{'J-Z'}{uc($1)}{$aname} = 1;
		} else {
			$menu{'Quest Chains'}{'Other'}{$aname} = 1;
		}
	}
	# build level & zone indexes
	my $level = $rec{level};
	if ($level) {
        if ($level eq 'Scaling') {
            push(@{$indexes{'Scaling'}}, $index);
            $menu{'Level Ranges'}{'Scaling'} = 1;
            $menu{'Level Ranges'}{'Non-Scaling'} = 1;
        } else {
            push(@{$indexes{'Non-Scaling'}}, $index);
            $menu{'Level Ranges'}{'Non-Scaling'} = 1;
        }
        my $curlevel = $level eq 'Scaling' ? -1 : int($level);
        my $minlevel = defined $rec{minlevel} ? int($rec{minlevel}) : 0;
        my $rc = 0;
        for my $range (@levelranges) {
            if (
                ($curlevel == -1 && $range->[0] >= $minlevel) ||
                ($range->[0] <= $curlevel && $curlevel <= $range->[1])
            )
            {
                my $rtext = "$range->[0]-$range->[1]";
                push(@{$levels{$rc}}, $index);
                push(@{$indexes{$rtext}}, $index);
                $menu{'Level Ranges'}{$rtext} = 1;
                last;
            }
            $rc++;
        }
	}

	my $zone = $q->{'zone'};
	my $area = $q->{'area'};
	$zone = 'Unknown' unless ($zone);
	$area = 'Unknown' unless ($area);
    $zone =~ s/^The\s+//is;
	$area =~ s/^The\s+//is;

	if ($zone ne 'Unknown' && $area ne 'Unknown' && $area ne $zone) {
		#$area .= " ($zone)";
	}
	
	push(@{$zones{$zone}}, $index);
	push(@{$zones{$area}}, $index) unless(lc($area) eq lc($zone));
    if ($q->{r}) {
        my $rew = $q->{r};
        if ($rew->{rc}) {
            foreach my $itm (@{ $rew->{rc} }) {
                if ($itm->{id}) {
                    $questitems{hex($itm->{id})} = $q->{id};
                }
            }
        }
        if ($rew->{so}) {
            foreach my $itm (@{ $rew->{so} }) {
                if ($itm->{id}) {
                    $questitems{hex($itm->{id})} = $q->{id};
                }
            }
        }

        while (my($rewardtype, $display) = each %rewardlabels) {
            if ($rew->{$rewardtype}) {
                push(@{$indexes{$display}}, $index);
                if ($rewardtype eq 'cx') {
                    foreach my $cr (@{$rew->{$rewardtype}}) {
                        $menu{'Rewarded'}{$display}{$cr->{craft}} = 1;
                        push(@{$indexes{$cr->{craft}}}, $index);
                    }
                } else {
                    $menu{'Rewarded'}{$display} = 1;
                }
            }
        }
    }
	print INDEX ",\n" if ($index > 1) ;
	print INDEX string(\%rec); 

	if ($q->{t}) {
		push(@{$indexes{$q->{t}}}, $index);
		$menu{'Quest Type'}{$q->{t}} = 1;
	}
	if ($q->{repeatable} eq 'Yes') {
		push(@{$indexes{'Repeatable'}}, $index);
		$menu{'Quest Type'}{'Repeatable'} = 1;
	}
	if ($q->{instance} eq 'Yes') {
		push(@{$indexes{'Instance'}}, $index);
		$menu{'Quest Type'}{'Instance'} = 1;
	}	
	if ($q->{faction}) {
		if ($q->{faction} eq 'Mon') {
			push(@{$indexes{'Monster'}}, $index);
			$menu{'Faction'}{'Monster'} = 1;
		} else {
			push(@{$indexes{'Free People'}}, $index);
			$menu{'Faction'}{'Free People'} = 1;
		}
	}
	
	push(@{$indexes{$zone}}, $index);
	unless (lc($area) eq lc($zone)) {
		if ($zone =~ m/^[a-e]/i) {
			$menu{'Zone'}{'A-E'}{$zone}{$area} = 1;	
		} else {
			$menu{'Zone'}{'F-Z'}{$zone}{$area} = 1;	
		}
		push(@{$indexes{$area}}, $index);
	} else {
		if ($zone =~ m/^[a-e]/i) {
			$menu{'Zone'}{'A-E'}{$zone} = {} unless ($menu{'Zone'}{'A-E'}{$zone});	
		} else {
			$menu{'Zone'}{'F-Z'}{$zone} = {} unless ($menu{'Zone'}{'F-Z'}{$zone});
		}		
	}
	$index++;
}
while (my($fsub, $frec) = each %{$menu{'Zone'}}) {
    while (my($zone, $zrec) = each %{$frec}) {
        if (ref($zrec) eq 'HASH' && scalar keys %{$zrec} == 1 && defined $zrec->{'Unknown'}) {
            $menu{'Zone'}{$fsub}{$zone} = 1;
        }
    }
}
store(\%questitems, 'questitems.db');

print INDEX <<EOB;
};

-----------------
-- quest category indexes
-----------------
questindexes = {
EOB

my $catcount = 0;
while (my($cat, $idsref) = each %indexes) {
	print INDEX ",\n" if ($catcount > 0);
	print INDEX "[".string($cat)."] = " . string($idsref);
	$catcount++;
}

print INDEX "};\n";
close INDEX;

#print INDEX <<EOB;
#
#};
#
#
#-----------------
#-- arc index
#-----------------
#arcindex = {
#EOB
#my $count = 0;
#foreach my $arc (sort keys %arcs) {
#	print INDEX ",\n" if ($count > 0) ;
#	print INDEX "[" . string($arc) . "] = " . string($arcs{$arc});
#	$count++;
#}
#print INDEX <<EOB;
#
#};
#
#-----------------
#-- level index
#-----------------
#levelindex = {
#EOB
#$count = 0;
#foreach my $index (sort keys %levels) {
#	my $range = $levelranges[$index];
#	print INDEX ",\n" if ($count > 0) ;
#	print INDEX "[" . string("$range->[0]\-$range->[1]") . "] = " . string($levels{$index});
#	$count++;
#}
#print INDEX <<EOB;
#
#};
#
#-----------------
#-- zone index
#-----------------
#zoneindex = {
#EOB
#$count=0;
##while (my($zone,$ref) = each %zones) {
#foreach my $zone (sort keys %zones) {
#	my $ref = $zones{$zone};
#	print INDEX ",\n" if ($count > 0) ;
#	print INDEX "[" .string($zone). "] = " . string($ref);
#	$count++;
#}
#print INDEX "\n};";
#close INDEX;
#
my @za = sort keys %zones;
open OUT, ">:utf8", "placesandlevels.lua";
print OUT "zones = " . string( \@za ) . ";\n\n";
close OUT;
#print OUT "levels = {";
#for (my $i = 0; $i < $#levelranges; $i ++) {
#	my $range = $levelranges[$i];
#	print OUT "," if ($i > 0) ;
#	print OUT string("$range->[0]\-$range->[1]");
#}
#print OUT "};\n";
#my @aa= sort keys %arcs;
#print OUT "arcs = " . string(\@aa) . ";\n\n";
close INDEX;

$menu{'Level Ranges'}{'Custom'} = 1;
open OUT, ">:utf8", "questmenu.lua";
print OUT generatemenu("", \%menu, "", 0);
close OUT;



exit;

sub loadquestdb {
    my $questdbfile = 'quest.db';
    if (-e $questdbfile) {
        return retrieve($questdbfile);
    }

    my %attrmap = ( 
        questArc => 'arcs', name => 'name', description => 'd', category => 'category', level => 'level', minLevel => 'minlevel', 
        id => 'id', repeatable => 'repeatable', monsterPlay => 'faction', instanced => 'instance'
    );
    my %rewardmap = (
        XP => 'xp', classPoints => 'cp', craftingXp => 'cx', emote => 'em', glory => 'gl', itemXP => 'ix', lotroPoints => 'lp', 
        money => 'mo', mountXP => 'mx', object => 'rc', reputationItem => 'ri', selectOneOf => 'so', title => 'ti', trait => 'tr', 
        virtue => 'vr', virtueXP => 'vx'
    );

    my %moneymap = ( gold => 'g', silver => 's', copper => 'c' );
    my $geodb = loadgeodb();
    my $poidb = loadpoidb($geodb);
    my $labeldb = loadlabels('quests');
    my $craftdb = loadcraftdb();
    my $commentdb = decode_json(loadfile('quest-commentdb.json', ':raw'));
    my $catlabeldb = loadlabels('enum-QuestCategory');
    my $catdb = loadmap('questcats.db', 'data/source/lc/general/lore/enums/QuestCategory.xml', '/enum/entry', 'code', $catlabeldb);

    my $filename = 'data/source/lc/general/lore/quests.xml';
    my $outputdir = 'data/output/Compendium/Quests';

    my $dom = XML::LibXML->load_xml(location => $filename);
    my @quests = ();
    foreach my $quest ($dom->findnodes('//quest')) {

        my %rec = ();
        my %att = attmap($quest, $labeldb);
        while (my($name, $val) = each %att) {
            my $key = $attrmap{$name};
            next unless ($key);
            $rec{$key} = $val;
        }
        my $autobestowed = defined $att{autoBestowed} && $att{autoBestowed} eq 'true';
        $rec{d} =~ s/\s*\(\$\{\w+\}\/(\$\{\w+\}|\d+)\)//gis if ($rec{d});
        $rec{id} = tohex($rec{id});
        $rec{repeatable} = $rec{repeatable} ? 'Yes' : 'No';
        $rec{faction} = $rec{faction} ? 'Mon' : 'FrP';
        $rec{instance} = defined $rec{instance} && $rec{instance} eq 'true' ? 'Yes' : 'No';
        my $catrec = $catdb->{$rec{category}};
        $rec{category} = $catrec ? $catrec->{name} : 'Unknown';
        my $comments = $commentdb->{"$rec{name}|$rec{category}"};
        $rec{c} = $comments if (defined $comments);
        if ($att{size} && $att{size} =~ m/(SMALL_FELLOWSHIP|FELLOWSHIP)/) {
            $rec{t} = $1 eq 'SMALL_FELLOWSHIP' ? 'Small Fellowship' : 'Fellowship';
        }
        $rec{level} = 'Scaling' if (defined $rec{level} && $rec{level} < 0);

        if (! defined $rec{arcs}) {
            if ($rec{category} =~ m/^Epic \- (.*)/is) {
                $rec{arcs} = $1;
                $rec{arcs} =~ s/Vol\. /Volume /s;
            } elsif ($rec{category} =~ m/(The Black Book of Mordor|The Legacy of Durin and the Trials of the Dwarves)/i) {
                $rec{arcs} = $1;
            }
        }

        # foreach my $m ($quest->findnodes('./map[@mapId]')) {
        #     my $mapId = $m->findvalue('./@mapId');
        #     my $geo = $geodb->{$mapId};
        #     if ($geo) {
        #         foreach my $key (qw(dungeon territory area)) {
        #             my $to = $key eq 'territory' ? 'zone' : $key;
        #             $rec{$to} = $geo->{$key} if ($geo->{$key});
        #         }
        #         last;
        #     } else {
        #         #print "Unknown Map: $mapId\n";
        #     }
        # }

        my %poilookups = ();
        foreach my $b ($quest->findnodes('./bestower')) {
            $rec{b} = $b->findvalue('./@npcName');
            my $id = $b->findvalue('./@npcId');
            if ($id) {
                if ($id =~ m/^(1879184967|1879184968)$/ && !$rec{b}) {
                    $rec{b} = 'Inn League Tavern Keep';
                }
                $poilookups{'pois'}{$id}++;
                unless (defined $rec{zone}) {
                    my $poi = poilookup($id, $poidb);
                    if ($poi) {
                        foreach my $key (qw(dungeon zone area)) {
                            $rec{$key} = $poi->{$key} if ($poi->{$key});
                        }
                    }
                }
            }
            # TODO: There can be more than one... Do something with other bestowers?
        }
        if (!$rec{zone} && $autobestowed) {
            ##  USING THE MAPS IN QUESTS IS PROBLEMATIC.  Their presence doesn't mean it starts there
            foreach my $m ($quest->findnodes('./map[@mapId]')) {
                my $mapId = $m->findvalue('./@mapId');
                my $geo = $geodb->{$mapId};
                if ($geo) {
                    foreach my $key (qw(dungeon territory area)) {
                        my $to = $key eq 'territory' ? 'zone' : $key;
                        $rec{$to} = $geo->{$key} if ($geo->{$key});
                    }
                    last;
                }
            }
        }
        #$rec{zone} = 'Unknown' unless ($rec{zone});
        #$rec{area} = 'Unknown' unless ($rec{area});
        my %pseen = ();
        foreach my $p ($quest->findnodes('./compoundPrerequisite/prerequisite')) {
            # only add prereqs that have a quest name
            my $curid = tohex($p->findvalue('./@id'));
            push(@{$rec{prev}}, $curid) if ($p->findvalue('./@name') && !$pseen{$curid}++);
        }
        foreach my $p ($quest->findnodes('./prerequisite')) {
            # only add prereqs that have a quest name
            my $curid = tohex($p->findvalue('./@id'));
            push(@{$rec{prev}},  $curid) if ($p->findvalue('./@name') && !$pseen{$curid}++);
        }
        my %nseen = ();
        foreach my $n ($quest->findnodes('./nextQuest')) {
            my $curid = tohex($n->findvalue('./@id'));
            push(@{$rec{next}}, $curid) if (!$nseen{$curid}++);
        }

        my %rew = ();
        foreach my $reward ($quest->findnodes('./rewards/*')) {
            my $type = $reward->localname;
            my $rewkey = $rewardmap{$type};
            # "destinypoints","virtues","titles","traits"
            if ($type eq 'money') {
                my @moneys = ();
                foreach my $a (qw(gold silver copper)) {
                    my $v = $reward->findvalue("./\@$a");
                    push(@moneys, "$v$moneymap{$a}") if ($v && $v ne '0');
                }
                push(@{$rew{$rewkey}}, { val => join(' ', @moneys)});
            } elsif ($type eq 'reputationItem') {
                my $amount = $reward->findvalue('./@amount');
                $amount = "+$amount" unless ($amount =~ m/^\-/);
                push(@{$rew{$rewkey}}, { val => "$amount with " . $reward->findvalue('./@faction') })
            } elsif ($type eq 'selectOneOf') {
                foreach my $o ($reward->findnodes('./object')) {
                    my %item = itemmap($o);
                    #{id="700005F3",q="(x3)",val="Mushroom Pie"}
                    push(@{$rew{$rewkey}}, \%item);
                }
            } elsif ($type eq 'object') {
                my %item = itemmap($reward);
                push(@{$rew{$rewkey}}, \%item);
            } elsif ($type =~ m/^(title|emote)$/i) {
                my %atts = attmap($reward, $labeldb);
                push(@{$rew{$rewkey}}, { val => $atts{name} });
            } elsif ($type eq 'trait') {
                my %atts = attmap($reward, $labeldb);
                push(@{$rew{$rewkey}}, { val => $atts{name} });
            } elsif ($type =~ m/^(XP|glory|virtueXP|itemXP|mountXP|classPoints|lotroPoints)$/i) {
                push(@{$rew{$rewkey}}, { val => $reward->findvalue('./@quantity') });
            } elsif ($type eq 'craftingXp') {
                # <craftingXp profession="COOK" tier="4" XP="36"/>
                my $craft = $craftdb->{$reward->findvalue('./@profession')}{name};
                push(@{$rew{$rewkey}}, { craft => $craft, val => $reward->findvalue('./@XP') });
            } elsif ($type eq 'virtue') {
                # dont see this much other than single quest 
            } else {
                # unknown
                #print "Unknown Reward Type!!! $type\n";
            }
            # destinypoints not given for quests anymore
        }
        if (keys %rew > 0) {
            $rec{r} = \%rew;
        }

        my @objectives = ();
        foreach my $o ($quest->findnodes('./objectives/objective')) {
            my %ob = attmap($o, $labeldb);
            my $desc = '';
            # TODO: handle <objective index="3" text="${RACE:Jon Brackenbrook wishes to speak with you.&#10;&#10;After the assault on Archet, Jon Brackenbrook returned to the town to assist and rebuild, taking up his father's legacy.'[U,D,L]|'Mundo Sackville-Baggins wishes to speak with you.&#10;&#10;After the assault on Archet, you helped Mundo Sackville-Baggins and Celandine Brandybuck on their return trip to the Shire.'[O]}" progressOverride="${RACE:Speak with Mundo Sackville-Baggins[O]|Speak with Jon Brackenbrook in Archet[U,D,L]}">
            $desc .= "$ob{text}\n" if ($ob{text});
            $desc .= "$ob{progressOverride}" if ($ob{progressOverride});
            my @sub = ("Obj $ob{index}:\n$desc");
            foreach my $prog ($o->findnodes('./*[@progressOverride]')) {
                my %att = attmap($prog, $labeldb);
                push(@sub, "* $att{progressOverride}");
            }
            push(@objectives, join("\n", @sub));
            
            foreach my $prog ($o->findnodes('./*[@npcId or @itemId or @mobId or @landmarkId]')) {
                my %att = attmap($prog, $labeldb);
                foreach my $key (qw(npcId itemId mobId landmarkId)) {
                    my $id = $att{$key};
                    $poilookups{$key eq 'mobId' ? 'mobs' : 'pois'}{$id}++ if ($id);
                }
            }
        }
        if (scalar @objectives > 0) {
            my $o = join("\n", @objectives);
            $o =~ s/[\n]+/\n/gs;
            $o =~ s/\s*\(\$\{\w+\}\/(\$\{\w+\}|\d+)\)//gis;
            $o =~ s/\\q/"/gis;
            $rec{o} = $o;
            #$rec{o} = compress(encode('utf-8', $o), 9);
        }

        while (my($type, $pref) = each %poilookups) {
            foreach my $id (keys %{$pref}) {
                my $poi = poilookup($id, $poidb);
                if ($poi) {
                    push(@{$rec{$type}}, $poi);
                }
            }
        }
        push(@quests, \%rec);
        
    }
    store(\@quests, $questdbfile);
    return \@quests;
}
