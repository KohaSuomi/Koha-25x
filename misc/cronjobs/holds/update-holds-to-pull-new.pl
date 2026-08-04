#!/usr/bin/perl

# Copyright 2000-2002 Katipo Communications
# Copyright 2016-2026 Koha-Suomi Oy
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use C4::Context;
use Koha::Biblios;
use Koha::Biblioitems;
use Koha::Holds;
use Koha::Patrons;
use Koha::DateUtils qw(dt_from_string output_pref);
use Koha::CirculationRules qw(get_effective_rule);
use Koha::Database;
use DateTime::Duration;
use List::MoreUtils qw(uniq);
use Storable;
use Time::HiRes qw(time);

use constant PULL_INTERVAL => 2;

sub active_hold_where {
    return (
        'me.found'    => undef,
        'me.priority' => { '!=' => 0 },
        -or           => [
            'me.suspend' => 0,
            'me.suspend' => undef,
        ],
    );
}

sub active_holds_by_biblio {
    my @hold_candidates = Koha::Holds->search(
        { active_hold_where() },
        {
            order_by => [ { -asc => 'me.biblionumber' }, { -asc => 'me.priority' } ],
            prefetch => [ 'borrowernumber', 'biblio' ],
        }
    )->as_list;

    my %holds_by_biblio;
    for my $hold (@hold_candidates) {
        push @{ $holds_by_biblio{ $hold->biblionumber } }, $hold;
    }

    return \%holds_by_biblio;
}

sub valid_items_for_hold {
    my ( $hold, $patron, $items, $items_in_transfer ) = @_;

    my %valid_items;
    my @valid_itypes;
    my @valid_holdingbranches;
    my $requested_itemnumber = $hold->itemnumber;

    foreach my $item (@$items) {
        # If hold is item-level, only that exact item is considered.
        next if $requested_itemnumber && $item->itemnumber != $requested_itemnumber;

        # If item is notforloan, damaged, lost, or withdrawn, it cannot fill this hold.
        next if $item->notforloan;
        next if $item->damaged;
        next if $item->itemlost;
        next if $item->withdrawn;

        # If itemtype is configured as not for loan, it cannot fill this hold.
        my $itemtype = Koha::ItemTypes->find( $item->itype );
        next if $itemtype && $itemtype->notforloan;

        # If item is checked out, it cannot fill this hold.
        my $checkout = $item->checkout;
        next if $checkout;

        # If item is in active transfer, it cannot fill this hold (precomputed via SQL query).
        next if $items_in_transfer->{ $item->itemnumber };

        # If item is already claimed for another found reserve, skip it.
        my $claimed_reserve_count = Koha::Holds->search(
            {
                'me.itemnumber' => $item->itemnumber,
                'me.found'      => { '!=' => undef }
            }
        )->count;
        next if $claimed_reserve_count;

        # If circulation rule holdallowed says not_allowed, item cannot fill this hold.
        my $issuing_rule = Koha::CirculationRules->get_effective_rule(
            {
                categorycode => $patron->categorycode,
                itemtype     => $item->itype,
                branchcode   => $hold->branchcode,
                rule_name    => 'holdallowed',
            }
        );

        if ( !$issuing_rule || ( $issuing_rule->rule_value && $issuing_rule->rule_value ne 'not_allowed' ) ) {
            $valid_items{ $item->itemnumber } = $item;
            push @valid_itypes, $item->itype;
            push @valid_holdingbranches, $item->holdingbranch;
        }
    }

    return ( \%valid_items, \@valid_itypes, \@valid_holdingbranches );
}

my $today = dt_from_string;
my $today_iso = output_pref({ dt => $today, dateformat => 'iso', dateonly => 1 });

# Find two days ago for the default shelf pull start date, unless HoldsToPullStartDate sys pref is set.
my $startdate = $today - DateTime::Duration->new(days => C4::Context->preference('HoldsToPullStartDate') || PULL_INTERVAL);
my $startdate_iso = output_pref({ dt => $startdate, dateformat => 'iso', dateonly => 1 });

# Similarly: calculate end date with ConfirmFutureHolds (days)
my $enddate = $today + DateTime::Duration->new( days => C4::Context->preference('ConfirmFutureHolds') || 0 );
my $enddate_iso = output_pref({ dt => $enddate, dateformat => 'iso', dateonly => 1 });

my $total_start = time();

# PHASE 1: Build basic where clause for holds
my %where = active_hold_where();

# Date range filtering
my $dtf = Koha::Database->new->schema->storage->datetime_parser;
if ( $startdate_iso && $enddate_iso ) {
    $where{'me.reservedate'} = [ -and => { '>=', $startdate_iso }, { '<=', $enddate_iso } ];
} elsif ($startdate_iso) {
    $where{'me.reservedate'} = { '>=', $startdate_iso };
} elsif ($enddate_iso) {
    $where{'me.reservedate'} = { '<=', $enddate_iso };
}

# PHASE 2: Get all biblionumbers with holds
my $holds = Koha::Holds->search(
    { %where },
    { distinct => 1, columns => qw[me.biblionumber] }
);

my @biblionumbers = $holds->get_column('biblionumber');
print STDERR "Phase 1: Found " . scalar(@biblionumbers) . " biblionumbers in " . sprintf("%.2f", time() - $total_start) . "s\n";

my $phase2_start = time();

# PHASE 3: Get items that can fill holds (pre-filtered, pre-loaded)
my %all_items;
if ( @biblionumbers ) {
    my $items = Koha::Holds->search(
        { %where },
        { join => 'itembib', distinct => 1 }
    )->get_items_that_can_fill;

    foreach my $item ( $items->as_list ) {
        push @{ $all_items{ $item->biblionumber } }, $item;
    }
}

print STDERR "Phase 2: Loaded items in " . sprintf("%.2f", time() - $phase2_start) . "s\n";

my $phase3_start = time();

# PHASE 4: Get count of total reserves per biblionumber
my $reserves_by_biblionumber = {
    map { $_->{biblionumber} => $_->{total_reserves} } @{ Koha::Holds->search(
            { active_hold_where() },
            {
                select   => [ 'me.biblionumber', { count => '*' } ],
                as       => [qw( biblionumber total_reserves )],
                group_by => [qw( me.biblionumber )]
            },
        )->unblessed
    }
};

# PHASE 5-6: Bulk fetch all active holds with details
my $all_holds_by_biblio = active_holds_by_biblio();

print STDERR "Phase 3-6: Data aggregation in " . sprintf("%.2f", time() - $phase3_start) . "s\n";

my $phase4_start = time();

# Precompute items with active transfers using SQL (replicates Item->get_transfer logic)
my %items_in_transfer;
if (@biblionumbers) {
    my @all_itemnumbers = map { $_->itemnumber } map { @{ $all_items{$_} || [] } } @biblionumbers;
    if (@all_itemnumbers) {
        my $dbh = C4::Context->dbh;
        my $itemnumbers_list = join(',', @all_itemnumbers);
        # Matches Item->get_transfer() which uses current_branchtransfers relationship
        # that filters: datearrived IS NULL AND datecancelled IS NULL
        my $sth = $dbh->prepare(
            'SELECT DISTINCT itemnumber FROM branchtransfers 
             WHERE datearrived IS NULL AND datecancelled IS NULL AND itemnumber IN (' . $itemnumbers_list . ')'
        );
        $sth->execute();
        while (my ($itemnumber) = $sth->fetchrow_array) {
            $items_in_transfer{$itemnumber} = 1;
        }
    }
}

# PHASE 7: Build output array
my @reservedata;
my %seen;

foreach my $bibnum (@biblionumbers) {
    next if $seen{$bibnum};
    $seen{$bibnum} = 1;

    my $items = $all_items{$bibnum} || [];
    my $items_count = scalar @$items;
    my $total_reserves = $reserves_by_biblionumber->{$bibnum} || 0;
    my $pull_count = $items_count <= $total_reserves ? $items_count : $total_reserves;

    next if $pull_count == 0;

    my $hold_candidates = $all_holds_by_biblio->{$bibnum} || [];
    my $hold;
    my $patron;
    my $valid_items;
    my $valid_itypes;
    my $valid_holdingbranches;

    # Walk queue-ordered holds and select the first one that can be filled now.
    HOLD_CANDIDATE:
    foreach my $candidate (@$hold_candidates) {
        # Ignore currently suspended holds and holds that only activate in the future. (KOHA-2259)
        if ( $candidate->suspend ) {
            next;
        }

        my $suspend_until = $candidate->suspend_until;
        if ($suspend_until) {
            my $suspend_until_iso = eval { $suspend_until->can('ymd') }
                ? $suspend_until->ymd
                : substr("$suspend_until", 0, 10);
            if ( $suspend_until_iso gt $today_iso ) {
                next;
            }
        }

        # If reservedate is in the future, this hold is not active yet for pulling.
        my $reserve_date = $candidate->reservedate;
        if ($reserve_date) {
            my $reserve_date_iso = eval { $reserve_date->can('ymd') }
                ? $reserve_date->ymd
                : substr("$reserve_date", 0, 10);
            if ( $reserve_date_iso gt $today_iso ) {
                next;
            }
        }

        # Skip candidates without a valid patron row.
        my $candidate_patron = Koha::Patrons->find( $candidate->borrowernumber );
        unless ($candidate_patron) {
            next;
        }

        # Check item-level targeting and eligibility (KOHA-2259)
        my ( $candidate_valid_items, $candidate_valid_itypes, $candidate_valid_holdingbranches ) =
            valid_items_for_hold( $candidate, $candidate_patron, $items, \%items_in_transfer );

        # Continue until at least one eligible item exists for this hold.
        my $candidate_valid_count = scalar(keys %$candidate_valid_items);
        unless ( $candidate_valid_count > 0 ) {
            next;
        }

        $hold = $candidate;
        $patron = $candidate_patron;
        $valid_items = $candidate_valid_items;
        $valid_itypes = $candidate_valid_itypes;
        $valid_holdingbranches = $candidate_valid_holdingbranches;

        # First valid candidate wins.
        last HOLD_CANDIDATE;
    }

    next unless $hold;

    my $biblio = $hold->biblio;
    my $biblioitem = $biblio->biblioitem;  # Get first biblioitem via biblio

    # Collect item metadata
    my @itemcallnumbers = sort { $a cmp $b } uniq map { $_->itemcallnumber // () } values %$valid_items;
    my @locations = sort { $a cmp $b } uniq map { $_->location // () } values %$valid_items;
    my @sublocations = sort { $a cmp $b } uniq map { $_->sub_location // () } values %$valid_items;
    my @ccodes = sort { $a cmp $b } uniq map { $_->ccode // () } values %$valid_items;
    my @enumchrons = sort { $a cmp $b } uniq map { $_->enumchron // () } values %$valid_items;
    my @copynumbers = sort { $a cmp $b } uniq map { $_->copynumber // () } values %$valid_items;
    my @itemnotes = sort { $a cmp $b } uniq map { $_->itemnotes // () } values %$valid_items;
    my @holdingbranches = sort { $a cmp $b } uniq @$valid_holdingbranches;
    my @itypes = sort { $a cmp $b } uniq @$valid_itypes;

    # Get item types from biblioitems if needed
    # Use Koha-Suomi logic
    my @mtypes;
    #if ( C4::Context->preference('item-level_itypes') ) {
    #    @mtypes = sort { $a cmp $b } uniq map { $_->itype // () } values %valid_items;
    #} else {
        @mtypes = $biblioitem && $biblioitem->itemtype ? ( $biblioitem->itemtype ) : ();
    #}

    push(
        @reservedata, {
            reservedate      => $hold->reservedate,
            borrowerinfo     => $patron->othernames,
            title            => $biblio->title,
            editionstatement => $biblioitem ? $biblioitem->editionstatement : '',
            number           => $biblioitem ? $biblioitem->number : '',
            subtitle         => [ $biblio->subtitle ] || [],
            author           => $biblio->author,
            collectiontitle  => $biblioitem ? $biblioitem->collectiontitle : '',
            collectionvolume => $biblioitem ? $biblioitem->collectionvolume : '',
            publicationyear  => $biblio->copyrightdate,
            part_name        => $biblio->part_name,
            part_number      => $biblio->part_number,
            borrowernumber   => $patron->borrowernumber,
            biblionumber     => $bibnum,
            holdingbranches  => \@holdingbranches,
            branch           => $hold->branchcode,
            itemcallnumber   => \@itemcallnumbers,
            enumchron        => join(', ', @enumchrons),
            copyno           => join('<br/>', @copynumbers),
            itemnotes        => \@itemnotes,
            count            => scalar(keys %$valid_items),
            rcount           => $total_reserves,
            itypes           => \@itypes,
            mtypes           => \@mtypes,
            pullcount        => $pull_count,
            locations        => \@locations,
            sublocations     => \@sublocations,
            ccodes           => \@ccodes,
        }
    );
}

store \@reservedata, "/tmp/kohasuomi-pendingreserves.tmp";

my $total_time = time() - $total_start;
print STDERR "\n=== Performance Timing ===\n";
print STDERR "Total processing time: " . sprintf("%.2f", $total_time) . " seconds\n";
print STDERR "Results processed: " . scalar(@reservedata) . "\n";
print STDERR "========================\n\n";

