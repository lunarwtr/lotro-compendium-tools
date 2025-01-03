#!/usr/bin/perl
package Compendium;

use strict;
use warnings;
use utf8;
use Encode;
use Storable qw(freeze thaw store retrieve);
use XML::LibXML;
use parent 'Exporter';  # inherit all of Exporter's methods
our @EXPORT = qw(attmap coorround dungpath escapelua geopath itemmap loadlabeldb loadcraftdb loadfactiondb loadfile loadgeodb loadmap loadpoidb poilookup sortkey string tohex 
);
our @EXPORT_OK = qw(attmap coorround dungpath escapelua geopath itemmap loadlabeldb loadcraftdb loadfactiondb loadfile loadgeodb loadmap loadpoidb poilookup sortkey string tohex 
);

sub loadmap {
    my($dbfile, $xmlfile, $nodexpath, $keyattr, $labeldb) = @_;
    if (-e $dbfile) {
        return retrieve($dbfile);
    }
    my %db = ();
    my $dom = XML::LibXML->load_xml(location => $xmlfile);
    foreach my $p ($dom->findnodes($nodexpath)) {
        my %rec = attmap($p, $labeldb);
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

sub tohex {
    my($id) = @_;
    return uc(sprintf("%x", $id));
}

sub coorround {
    my($v) = @_;
    return int($v * 10)/10;
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

sub string {
	my($val, $stringonly) = @_;
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
			my $hv = string($v, $stringonly || $hk eq 'id');
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
			$newval .= string($item, $stringonly); 
			$count++;
		}
		$newval .= "}";
		return $newval;
    # } elsif ($val =~ /[^[:print:]]/s) {
    #     $val =~ s/"/\\"/gs;
    #     return "\"$val\"";
	} else {
		return escapelua($val, $stringonly);
	}
}

sub escapelua {
	my($val, $stringonly) = @_;
	$val =~ s/\s+$//s;
	$val =~ s/^\s+//s;
	$val =~ s/\\/\\\\/gis;
	$val =~ s/\s*\n\s*/\\n/gis;
	$val =~ s/\s*\r\s*/\\r/gis;
	$val =~ s/"/\\"/gis;
    if ($stringonly) {
        $val = "\"$val\"";
    } else {
	    $val = $val =~ m/^\d+$/ ? "$val" : "\"$val\"";
    }
	return $val;
}

sub attmap {
    my($n, $labels) = @_;
    return map { 
        my $att = $_;
        my $val = $att->value;
        if (defined $labels && defined $val && $val =~ /^key:/) {
            $val = $labels->{$val};
        }
        $att->name => $val;
    } $n->attributes();
}

sub geopath {
    my($geosref, $c, $r) = @_;
    if ($c->{parentId}) {
        geopath($geosref, $geosref->{$c->{parentId}}, $r);
    }
    $r->{$c->{type}} = $c->{name};
}

sub dungpath {
    my($georef, $c, $vals) = @_;
    return unless (defined $c->{id});
    return if (defined $georef->{$c->{id}});
    while (my($k,$v) = each %{$vals}) {
        $c->{$k} = $v;
    }
    #$c->{dungeon} = $c->{name};
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

sub itemmap {
    my($n) = @_;
    my %rec = attmap($n);
    my %item = ( id => uc(sprintf("%x", $rec{id})), val => $rec{name} );
    $item{q} = $rec{quantity} if ($rec{quantity});
    return %item;
}

sub loadlabeldb {
    my($dbname) = @_;
    my $labeldbfile = "${dbname}label.db";
    if (-e $labeldbfile) {
        return retrieve($labeldbfile);
    }
    my %labels = ();
    my $dom = XML::LibXML->load_xml(location => "data/source/lc/general/lore/labels/en/${dbname}.xml");
    foreach my $p ($dom->findnodes('/labels/label')) {
        my %rec = attmap($p);
        $labels{$rec{key}} = $rec{value};
    }
    store(\%labels, $labeldbfile);
	return \%labels;
}


sub loadcraftdb {
    return loadmap('craft.db', 'data/source/lc/general/lore/crafting.xml', '/crafting/profession', 'key');
}

# sub loadgeodb {
#     my $geodbfile = 'geo.db';
#     if (-e $geodbfile) {
#         return retrieve($geodbfile);
#     }
#     my $meid = 0;
#     my %geoids = ();
#     my $geodom = XML::LibXML->load_xml(location => 'data/source/lc/general/lore/parchmentMaps.xml');
#     my %regions = ();
#     foreach my $g ($geodom->findnodes('//parchmentMaps/parchmentMap')) {
#         my %rec = attmap($g);
#         my $mn = $rec{name};
#         if ($rec{region} eq '0') {
#             $meid = $rec{id};
#             next;
#         }
#         if ($rec{parentMapId} eq $meid) {
#             $rec{type} = 'region';
#             $regions{$rec{id}} = $rec{name};
#         }
#         $geoids{$rec{id}} = \%rec;
#         foreach my $a ($geodom->findnodes('./area')) {
#             my %att = attmap($a);
#             $att{parentMapId} = $rec{id};
#             $geoids{$att{id}} = \%att;

#             if ($att{parentMapId} eq $meid) {
#                 $att{type} = 'region';
#                 $regions{$att{id}} = $att{name};
#             }
#         }
#     }
#     my $dungdom = XML::LibXML->load_xml(location => 'data/source/lc/general/lore/dungeons.xml');
#     foreach my $g ($geodom->findnodes('//dungeons/dungeon')) {
#         my %rec = attmap($g);
#         $rec{type} = 'dungeon';
#         my $zoneid = $g->findvalue('./position/@zoneID');
#         if ($zoneid) {
#             $rec{parentMapId} = $zoneid;
#         }
#         $geoids{$rec{id}} = \%rec;
#     }
#     while (my($id, $rec) = each %geoids) {
#         if ($regions{$id}) {
#             # nothing to do
#             $rec->{type} = 'region';
#         } elsif ($regions{$rec->{parentMapId}}) {
#             $rec->{type} = 'territory';
#         } else {
#             $rec->{type} = 'area';
#         }
#     }
#     store(\%geoids, $geodbfile);
# 	return \%geoids;
# }

sub loadgeodb {
    my $geodbfile = 'geo.db';
    if (-e $geodbfile) {
        return retrieve($geodbfile);
    }
    my %geos = ();
    my %geobyname = ();
    my $geodom = XML::LibXML->load_xml(location => 'data/source/lc/general/lore/geoAreas.xml');
    foreach my $g ($geodom->findnodes('//geoAreas/*')) {
        my %rec = attmap($g);
        $rec{type} = $g->localname;

        # hack for misty mountains.. there is an area that keeps pointing at trollshaws
        # <area id="1879063940" name="Misty Mountains" parentId="1879072246" iconId="1091632757"/>
        if ($rec{id} eq '1879063940') {
            %rec = %{$geos{'1879072227'}};
            $rec{id} = 1879063940;
        }

        $geos{$rec{id}} = \%rec;
        if ($rec{parentId}) {
            geopath(\%geos, \%rec, \%rec);
        }
    }
    while (my($id,$rec) = each %geos) {
        if (defined $geobyname{$rec->{name}}) {
            # my $or = $geobyname{$rec->{name}};
            # print "DUPLICATE $rec->{name} ($rec->{id}|$rec->{parentId} <==> $or->{id}|$or->{parentId}\n";
        } else {
            # only allow first area by that name to be used.  There is a lot of name reuse.  
            # the early tags are the zones.. farter down are the areas.. so taking zone is better
            $geobyname{$rec->{name}} = $rec;
        }
    }
    my %maps = ();
    my $mapdom = XML::LibXML->load_xml(location => 'data/source/lc/maps/maps/maps.xml');
    foreach my $g ($mapdom->findnodes('//map')) {
        my %rec = attmap($g);
        my $id = $rec{id};
        my $geo = $geos{$id};
        $maps{$id} = \%rec;
        if (length($id) < 10 && $geobyname{$rec{name}} && !defined $geos{$id}) {
            $geos{$id} = $geobyname{$rec{name}};
        }
    }
    # $mapdom = XML::LibXML->load_xml(location => 'data/source/lc/maps/links.xml');
    # my %scanme = ();
    # foreach my $g ($mapdom->findnodes('//links/*')) {
    #     my %rec = attmap($g);
    #     # if (length($id) < 10) {
    #     #     next;
    #     # }
    #     my $target = $rec{target};
    #     if ($rec{type} && $rec{type} eq 'TO_DUNGEON') {
    #         my $targetRec = $maps{$target};
    #         $targetRec->{dungeon} = $targetRec->{name};
    #     }

    #     my $id = $rec{parentId};
    #     my $geo = $geos{$id};
    #     if ($geo) {
    #         my %vals = ();
    #         foreach my $key (qw(region territory area)) {
    #             $vals{$key} = $geo->{$key} if ($geo->{$key});
    #         }
    #         $vals{parentId} = $id;
    #         $scanme{$target} = \%vals;
    #     } else {
    #         push(@{$maps{$target}{parents}}, $maps{$id});
    #         push(@{$maps{$id}{dungeons}}, $maps{$target});
    #     }
    # }
    # while (my($root,$vals) = each %scanme) {
    #     dungpath(\%geos, $maps{$root}, $vals);
    # }
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
            my $zoneid = $rec{parentZoneId};
            if (!$zoneid) {
                next;
            }
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

sub poilookup {
    my($id, $poidb) = @_;
    my $poi = $poidb->{$id};
    if ($poi) {
        my $label = $poi->{label};
        $label =~ s/\n.*$//s;
        my %rec = (
            name => $label
            #type = $poi->{type}
        );
        foreach my $zref (values %{$poi->{zones}}) {
            #unless ($rec{zone}) {
                foreach my $key (qw(zone area dungeon)) {
                    $rec{$key} = $zref->{$key} if ($zref->{$key});
                }
                my %uniq = ();
                foreach my $coor (@{$zref->{coors}}) {
                    my $ew = coorround($coor->{longitude});
                    $ew = $ew < 0 ?  (- $ew)."W" : "${ew}E";
                    my $ns = coorround($coor->{latitude});
                    $ns = $ns < 0 ?  (- $ns)."S" : "${ns}N";
                    $uniq{"$ns, $ew"}++;
                }
                my @locs = sort keys %uniq;
                $rec{loc} = \@locs;
            #}
            return \%rec;
            # TODO: Determine what to do with other zones
        }
    }

}

sub loadfactiondb {
    my $factiondbfile = 'factions.db';
    if (-e $factiondbfile) {
        return retrieve($factiondbfile);
    }
    my $factionlabeldb = loadlabeldb('factions');
    my %factions = ();
    my $dom = XML::LibXML->load_xml(location => 'data/source/lc/general/lore/factions.xml');
    foreach my $f ($dom->findnodes('/factions/faction')) {
        my %rec = attmap($f, $factionlabeldb);
        foreach my $l ($f->findnodes('./level')) {
            my %attr = attmap($l, $factionlabeldb);
            $rec{levels}{$attr{tier}} = \%attr;
        }
        $factions{$rec{id}} = \%rec;
    }
    store(\%factions, $factiondbfile);
	return \%factions;
}

1;
