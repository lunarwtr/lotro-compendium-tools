#!/usr/bin/perl

use lib '/home/kriley/workspace/lotro-compendium-tools/';
use strict;
use warnings;
use utf8;
use Encode;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
use Compendium;
use JSON;

$|=1;

my $deeddb = loaddeeddb();

open INDEX, ">:utf8", "data/output/Compendium/Deeds/CompendiumDeedsDB.lua";

print INDEX <<EOB;
---\@diagnostic disable
---\@class POI
---\@field name string name of deed
---\@field area? string
---\@field zone string
---\@field dungeon? string
---\@field locs string[]

---\@class Deed
---\@field id string hex id of deed
---\@field name string name of deed
---\@field area string
---\@field zone string
---\@field t string type / category of deed
---\@field d string description
---\@field level number | '"Scaling"'
---\@field mobs POI[]
---\@field pois POI[]
---\@field ndx number

---\@type Deed[]
deedtable = {
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
my %deeditems = ();
my %levels = ();
my %zones = ();
my %arcs = ();
my %indexes = ();
my $index = 1;
my %deedtoindex = ();
my @levelranges = ();
foreach my $q (@{ $deeddb }) {
	$deedtoindex{$q->{id}} = $index;
	$index++;
}
for (my $i = 1; $i <= 150; $i += 5) {
	push(@levelranges,[ $i, $i + 4]);
}
$index = 1;
foreach my $q (sort { $a->{name} cmp $b->{name} } @{ $deeddb }) {
	my $mobs = $q->{'mobs'};
	my $locs = $q->{'pois'};
	
	if ($q->{'next'}) {
        # replace next with deed offsets
		my @newnext = ();
		foreach my $id (@{ $q->{'next'} }) {
			my $index = $deedtoindex{$id};			
			push(@newnext, $deedtoindex{$id}) if ($index);
		}
		if (scalar @newnext > 0) {
			$q->{'next'} = \@newnext;
		} else {
			delete $q->{'next'};
		}		
	}
	if ($q->{'prev'}) {
        # replace prev with deed offsets
		my @newprev = ();
		foreach my $id (@{ $q->{'prev'} }) {
			my $index = $deedtoindex{$id};
			push(@newprev, $index) if ($index);
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
		push(@{$indexes{'Deed Chains'}}, $index);
		push(@{$indexes{$aname}}, $index);
		if ($aname =~ m/^((Vol.|Volume) \w+)/i) {
			$menu{'Deed Chains'}{'Epics'}{$1}{$aname} = 1;
		} elsif ($aname =~ m/Epic Prologue/i) {
			$menu{'Deed Chains'}{'Epics'}{'Prologue'}{$aname} = 1;
		} elsif ($aname =~ m/(The Black Book of Mordor|The Legacy of Durin and the Trials of the Dwarves)/i) {
			$menu{'Deed Chains'}{'Epics'}{$aname} = 1;
		} elsif ($aname =~ m/^The\s+([a-i])/i) {
			$menu{'Deed Chains'}{'A-I'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^The\s+([j-z])/i) {
			$menu{'Deed Chains'}{'J-Z'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^([a-i])/i) {
			$menu{'Deed Chains'}{'A-I'}{uc($1)}{$aname} = 1;
		} elsif ($aname =~ m/^([j-z])/i) {
			$menu{'Deed Chains'}{'J-Z'}{uc($1)}{$aname} = 1;
		} else {
			$menu{'Deed Chains'}{'Other'}{$aname} = 1;
		}
	}
	# build level & zone indexes
	my $level = $rec{level};
	if ($level) {
        if ($level eq 'Scaling') {
            push(@{$indexes{'Scaling'}}, $index);
            $menu{'Level Ranges'}{'Scaling'} = 1;
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
	$zone =~ s/^The\s+//is;
	$area =~ s/^The\s+//is;

	$zone = 'Unknown' unless ($zone);
	$area = 'Unknown' unless ($area);
	
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
                    $deeditems{hex($itm->{id})} = $q->{id};
                }
            }
        }
        if ($rew->{so}) {
            foreach my $itm (@{ $rew->{so} }) {
                if ($itm->{id}) {
                    $deeditems{hex($itm->{id})} = $q->{id};
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
        if ($q->{t} eq 'Class') {
            my $class = $q->{cat};
    		push(@{$indexes{$class}}, $index);
            $menu{'Deed Type'}{'Class'}{$class} = 1;
        } else {
		    $menu{'Deed Type'}{$q->{t}} = 1;
        }
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
store(\%deeditems, 'deeditems.db');

print INDEX <<EOB;
};

-----------------
-- deed category indexes
-----------------
deedindexes = {
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
open OUT, ">:utf8", "deedmenu.lua";
print OUT generatemenu("", \%menu, "", 0);
close OUT;

exit;

sub loaddeeddb {
    my $deeddbfile = 'deed.db';
    if (-e $deeddbfile) {
        return retrieve($deeddbfile);
    }
    my %typemap = (
        CLASS => "Class", EVENT => "Event", EXPLORER => "Explorer",
        LORE => "Lore", RACE => "Race", REPUTATION => "Reputation", SLAYER => "Slayer"
    );
    my %attrmap = ( 
        name => 'name', description => 'd', category => 'cat', 
        level => 'level', minLevel => 'minlevel', type => 't',
        id => 'id', monsterPlay => 'faction', requiredClass => 'class'
    );
    my %rewardmap = (
        XP => 'xp', classPoints => 'cp', craftingXp => 'cx', emote => 'em', glory => 'gl', itemXP => 'ix', lotroPoints => 'lp', 
        money => 'mo', mountXP => 'mx', object => 'rc', reputationItem => 'ri', selectOneOf => 'so', title => 'ti', trait => 'tr', 
        virtue => 'vr', virtueXP => 'vx'
    );
    my %objectfuncs = buildobjectivefunctions();
    my $factions = loadfactiondb();
    my %moneymap = ( gold => 'g', silver => 's', copper => 'c' );
    my $geodb = loadgeodb();
    my $poidb = loadpoidb($geodb);
    my $craftdb = loadcraftdb();
    my %geobyname = ();
    while (my($geoid,$r) = each %{$geodb}) {
        my $gname = $r->{name};
        $gname =~ s/^The\s+//i;
        $geobyname{$gname} = $r unless (defined $geobyname{$gname});
    }
    my $commentdb = decode_json(loadfile('deed-commentdb.json', ':raw'));
    my $deedlabeldb = loadlabels('deeds');
    my $questlabeldb = loadlabels('quests');
    my $catlabeldb = loadlabels('enum-DeedCategory');
    my $catdb = loadmap('deedcats.db', 'data/source/lc/general/lore/enums/DeedCategory.xml', '/enum/entry', 'code', $catlabeldb);

    my $filename = 'data/source/lc/general/lore/deeds.xml';
    my $outputdir = 'data/output/Compendium/Deeds';

    my $dom = XML::LibXML->load_xml(location => $filename);

    my %questnamesbyid = ();
    foreach my $deed ($dom->findnodes('//deed')) {
        my %att = attmap($deed, $deedlabeldb);
        $questnamesbyid{$att{id}} = $att{name};
    }
    my $questfilename = 'data/source/lc/general/lore/quests.xml';
    my $qdom = XML::LibXML->load_xml(location => $questfilename);
    foreach my $quest ($qdom->findnodes('//quest')) {
        my %att = attmap($quest, $questlabeldb);
        $questnamesbyid{$att{id}} = $att{name};
    }
    $qdom = undef;

    my @deeds = ();
    my %deeddeps = ();
    foreach my $deed ($dom->findnodes('//deed')) {
        my %rec = ();
        my %att = attmap($deed, $deedlabeldb);
        while (my($name, $val) = each %att) {
            my $key = $attrmap{$name};
            if ($key) {
                $rec{$key} = $val;
            }
        }
        next if ($rec{name} =~ /\bDNT\b/);
        $rec{d} =~ s/\s*\(\$\{\w+\}\/(\$\{\w+\}|\d+)\)//gis if ($rec{d});
        $rec{id} = tohex($rec{id});
        $rec{faction} = $rec{faction} ? 'Mon' : 'FrP';
        my $t = $rec{t} = $typemap{$rec{t}};
        my $catrec = $catdb->{$rec{cat}};
        $rec{cat} = $catrec ? $catrec->{name} : 'Unknown';

        my $commentkey = "$rec{name}|$t";
        if ($t eq 'Slayer') {
            $commentkey = "$rec{name}|Slayer|$rec{cat}";
        } elsif ($t eq 'Class' && $rec{class}) {
            $commentkey = "$rec{name}|$rec{class}";
        }
        my $comments = $commentdb->{$commentkey};
        $rec{c} = $comments if (defined $comments);

        # SOME deeds use category for the zone they apply to
        my $possiblezone = $rec{cat};
        $possiblezone =~ s/^The\s+//i;        
        # some explorer deeds are named with zone according to various patterns
        if ($t eq 'Explorer' && !defined $geobyname{$possiblezone}) {
            if ($rec{name} =~ m/^(.+)\s+(Traveller|Exploration|Explorer)$/i) {
                $possiblezone = $1;
            } elsif ($rec{name} =~ m/^(Reclaiming|Scouting|Discovering|Exploring)\s+(.+)$/i) {
                $possiblezone = $1;
            } elsif ($rec{name} =~ m/^(.+) (to|of|in)( the)? (.+)$/i) {
                $possiblezone = $4;                
            } elsif ($rec{name} =~ m/^(Discovery|Missions):\s+(.+?)(,.*)?$/i) {
                $possiblezone = $2;        
            } else {
                #print "EXPLORE PATTERN: $rec{name}\n";
                $possiblezone = $rec{name};
            }
        }
        $possiblezone =~ s/^The\s+//i;
        my $georef = $geobyname{$possiblezone};
        if ($georef) {
            $rec{zone} = $possiblezone;
            foreach my $key (qw(territory area)) {
                my $to = $key eq 'territory' ? 'zone' : $key;
                $rec{$to} = $georef->{$key} if ($georef->{$key});
            }
        }

        if (!$rec{zone}) {
            ##  USING THE MAPS IN DEEDS IS PROBLEMATIC.. THEY HAVE MAP REFERENCES THAT 
            ## have nothign to do with the deed persay.. i.e. Ring-lore of Tham M�rdain
            foreach my $m ($deed->findnodes('./map[@mapId]')) {
                my $mapId = $m->findvalue('./@mapId');
                my $geo = $geodb->{$mapId};
                if ($geo) {
                    foreach my $key (qw(territory area)) {
                        my $to = $key eq 'territory' ? 'zone' : $key;
                        $rec{$to} = $geo->{$key} if ($geo->{$key});
                    }
                    last;
                }
            }
        }

        $rec{zone} = 'Unknown' unless ($rec{zone});
        $rec{area} = 'Unknown' unless ($rec{area});

        foreach my $p ($deed->findnodes('./objectives/objective/questComplete')) {
            # only add prereqs that have a deed name
            my $prev = $p->findvalue('./@achievableId');
            #push(@{$rec{prev}}, tohex($prev)) 
            if ($prev) {
                $prev = tohex($prev);
                push(@{$deeddeps{$rec{id}}{prev}}, $prev);
                push(@{$deeddeps{$prev}{next}}, $rec{id});
            }
        }

        my %rew = ();
        foreach my $reward ($deed->findnodes('./rewards/*')) {
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
            } elsif ($type eq 'title') {
                my %atts = attmap($reward, $deedlabeldb);
                push(@{$rew{$rewkey}}, { val => $atts{name} });
            } elsif ($type eq 'trait') {
                my %atts = attmap($reward, $deedlabeldb);
                push(@{$rew{$rewkey}}, { val => $atts{name} });
            } elsif ($type =~ m/^(XP|glory|virtueXP|itemXP|mountXP|classPoints|lotroPoints)$/i) {
                push(@{$rew{$rewkey}}, { val => $reward->findvalue('./@quantity') });
            } elsif ($type eq 'craftingXp') {
                # <craftingXp profession="COOK" tier="4" XP="36"/>
                my $craft = $craftdb->{$reward->findvalue('./@profession')}{name};
                push(@{$rew{$rewkey}}, { craft => $craft, val => $reward->findvalue('./@XP') });
            } elsif ($type eq 'virtue') {
                # dont see this much other than single deed 
            } else {
                # unknown
                #print "Unknown Reward Type!!! $type\n";
            }
            # destinypoints not given for deeds anymore
        }
        if (keys %rew > 0) {
            $rec{r} = \%rew;
        }

        my %poilookups = ();
        my @objectives = ();
        foreach my $o ($deed->findnodes('./objectives/objective')) {
            my %ob = attmap($o, $deedlabeldb);
            my $desc = '';
            # TODO: handle <objective index="3" text="${RACE:Jon Brackenbrook wishes to speak with you.&#10;&#10;After the assault on Archet, Jon Brackenbrook returned to the town to assist and rebuild, taking up his father's legacy.'[U,D,L]|'Mundo Sackville-Baggins wishes to speak with you.&#10;&#10;After the assault on Archet, you helped Mundo Sackville-Baggins and Celandine Brandybuck on their return trip to the Shire.'[O]}" progressOverride="${RACE:Speak with Mundo Sackville-Baggins[O]|Speak with Jon Brackenbrook in Archet[U,D,L]}">
            $desc .= "$ob{text}\n" if ($ob{text});
            $desc .= "$ob{progressOverride}" if ($ob{progressOverride});
            my @sub = ();
            foreach my $prog ($o->nonBlankChildNodes()) {
                my $nodename = $prog->localname;
                #$o->findnodes('./*[@progressOverride or @name]')) {
                my %att = attmap($prog, $deedlabeldb);
                my $po = $att{progressOverride};
                if (!defined $po || $nodename eq 'emote') {
                    my $func = $objectfuncs{$nodename};
                    if ($func) {
                        $po = $func->(\%att, \%questnamesbyid, $factions);
                        next unless ($po);
                    }
                }
                push(@sub, "* $po");
                # my @points = $prog->findnodes('./point');
                
                # if (scalar @points == 0) {
                #     foreach my $key (qw(npcId itemId mobId)) {
                #         my $id = $att{$key};
                #         $poilookups{$key eq 'mobId' ? 'mobs' : 'pois'}{$id}++ if ($id);
                #     }
                # } else {
                #     my $objName = $po;
                #     foreach my $key (keys %att) {
                #         if ($key =~ m/Name/) {
                #             $objName = $att{$key};
                #             last;
                #         }
                #     }
                #     $objName =~ s/^(Defeat|Discover|Find) (the|a)\s*//;
                #     my %poi = ( name => $objName, zone => $rec{zone} );
                #     $poi{area} = $rec{area} if ($rec{area} ne 'Unknown'); 
                #     my %uniq = ();
                #     #print "POINTS: $nodename, keys : " . join(", ", sort keys %att) . "\n";
                #     foreach my $point (@points) {
                #         my %coors = attmap($point);
                #         my $ew = coorround($coors{longitude});
                #         $ew = $ew < 0 ?  (- $ew)."W" : "${ew}E";
                #         my $ns = coorround($coors{latitude});
                #         $ns = $ns < 0 ?  (- $ns)."S" : "${ns}N";
                #         $uniq{"$ns, $ew"}++;
                #     }
                #     my @locs = sort keys %uniq;
                #     $poi{loc} = \@locs;
                #     push(@{$rec{pois}}, \%poi);
                # }
            }
            if (scalar @sub > 0 || $desc) {
                unshift(@sub, "Obj $ob{index}:\n$desc");
            }
            
            push(@objectives, join("\n", @sub)) if (scalar @sub > 0);
            next;

            foreach my $prog ($o->findnodes('./*[@npcId or @itemId or @mobId]')) {
                my %att = attmap($prog);
                foreach my $key (qw(npcId itemId mobId)) {
                    my $id = $att{$key};
                    $poilookups{$key eq 'mobId' ? 'mobs' : 'pois'}{$id}++ if ($id);
                }
            }
            ## TODO: find a way to get the coords for things that have a <point coordinate tag w/o a parent npc/item/mob id.
            ## ex <condition type="WORLD_EVENT_CONDITION" loreInfo="key:620841726:118018276" progressOverride="key:620841726:22075076" showBillboardText="false">
            # <point key="skirmish_ford_bruinen_arrows" longitude="-11.370723" latitude="-33.501923"/>
            # </condition>

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
        push(@deeds, \%rec);
        
    }
    # link up prev / next relationships to deeds
    foreach my $rec (@deeds) {
        my $ref = $deeddeps{$rec->{id}};
        if ($ref) {
            foreach my $k (keys %{$ref}) {
                $rec->{$k} = $ref->{$k};
            }
        }
    }
    store(\@deeds, $deeddbfile);
    return \@deeds;
}

sub buildobjectivefunctions {
    return (
        hobby => sub { my($att) = @_; return "Catch a $att->{itemName}"; },
        inventoryItem => sub { my($att) = @_; return "Collect $att->{itemName}"; },
        itemTalk => sub { my($att) = @_; return "Discover $att->{itemName}"; },
        itemUsed => sub { my($att) = @_; return "Use $att->{itemName}"; },
        landmarkDetection => sub { my($att) = @_; return "Discover $att->{landmarkName}"; },
        monsterDied => sub { 
            my($att) = @_; 
            my $name = $att->{mobName};
            return undef unless ($name);
            return $att->{count} ? "Defeat $att->{count} $name" : "Defeat $name"; 
        },
        npcTalk => sub { my($att) = @_; return "Speak with $att->{npcName}"; },
        skillUsed => sub { my($att) = @_; return "Use the skill $att->{skillName}"; },
        questComplete => sub {
            my($att,$dbyid) = @_;
            return undef unless ($att->{achievableId});
            my $quest = $dbyid->{$att->{achievableId}};
            return $quest ? "Complete '$quest'": undef;
        },
        questBestowed => sub {
            my($att,$dbyid) = @_;
            my $quest = $dbyid->{$att->{achievableId}};
            return $quest ? "Accept $quest": undef;
        },
        enterDetection => sub {
            my($att,$dbyid) = @_;
            return $att->{progressOverride};
        },
        emote => sub {
            my($att,$dbyid) = @_;
            if ($att->{npcName}) {
                return "Perform $att->{command} emote at $att->{npcName}";
            } elsif ($att->{count}) {
                return "Receive $att->{command} emote $att->{count} times ($att->{maxDaily} times/day)";
            } else {
                return "Perform $att->{command} emote";
            }
        },
        factionLevel => sub {
            my($att,$dbyid,$fdb) = @_;
            my $f = $fdb->{$att->{factionId}};
            return undef unless($f);
            my $tier = $att->{tier};

            my $l = $f->{levels}{$tier}{name};
            if (!$l && $tier >= 8 && $tier <= 10) {
                # this is a hack coz lc data doesn't fully defined all faction
                # tiers for some reason
                if ($tier == 8) {
                    $l = 'Respected';
                } elsif ($tier == 9) {
                    $l = 'Honoured';
                } else {
                    $l = 'Celebrated';
                }
            }
            return "You must earn $l standing with $f->{name}";
        },
        condition => sub {
            my($att,$dbyid,$fdb) = @_;
            return $att->{progressOverride};
        },
        level => sub {
            my($att,$dbyid,$fdb) = @_;
            return "Reach level $att->{level}";
        }
    );
}
