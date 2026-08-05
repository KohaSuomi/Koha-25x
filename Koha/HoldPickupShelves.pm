package Koha::HoldPickupShelves;

# This file is part of Koha.
#
# Copyright 2025 Koha-Suomi Oy
#
# Koha is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General
# Public License along with Koha; if not, see
# <http://www.gnu.org/licenses>

use Modern::Perl;

use base qw(Koha::Objects);

use Koha::HoldPickupShelf;

=head1 NAME

Koha::HoldPickupShelves - Koha HoldPickupShelves Object class

=head1 API

=head2 Public methods

=head3 available_shelves
Returns the list of shelves for a given library.
=cut
sub available_shelves {
    my ($self, $library_id, $biblio_id, $patron_id) = @_;

    $self->lock_previously_used_shelves($library_id);
    $self->open_locked_shelves($library_id);

    my $patron = Koha::Patrons->find($patron_id);
    my $biblio = Koha::Biblios->find($biblio_id);

    my @methods = (
        sub { $self->shelves_by_itemtype_and_category($library_id, $biblio->itemtype, $patron->categorycode) },
        sub { $self->shelves_by_itemtype_or_category($library_id, $biblio->itemtype, $patron->categorycode) },
        sub { $self->shelves_all_primary($library_id) },
        sub { $self->overflow_shelves($library_id) },
    );

    foreach my $method (@methods) {
        my $shelves = $method->();
        if ($shelves && @$shelves) {
            # Optimize: Prefetch all hold counts and duplicate checks in one query
                my @shelf_ids = map { $_->hold_pickup_shelf_id } @$shelves;
            my %holds_count = $self->_get_holds_count_for_shelves(\@shelf_ids);
            my %duplicate_check = $self->_check_duplicates_for_shelves(\@shelf_ids, $biblio_id);
            
            my $response = [];
                for my $shelf (@$shelves) {
                my $shelf_id = $shelf->hold_pickup_shelf_id;
                my $holds_count = $holds_count{$shelf_id} || 0;
                
                # Early exit checks before calling available_shelf
                next if !$shelf->allow_multiple && $duplicate_check{$shelf_id};
                next if $holds_count >= $shelf->max_items;
                
                # Pass holds_count to avoid redundant query
                if ($shelf->available_shelf($biblio, $patron, $holds_count)) {
                    $shelf = $shelf->unblessed;
                    $shelf->{holds_count} = $holds_count;
                    push @{$response}, $shelf;
                }
            }
            
            return $response if @$response;
        }
    }
    return [];
}

# Add search helper subs for shelf selection logic
sub shelves_by_itemtype_and_category {
    my ($self, $library_id, $biblio_itemtype, $patron_categorycode) = @_;
    return $self->search({
        library_id         => $library_id,
        biblio_itemtype    => $biblio_itemtype,
        patron_category_id => $patron_categorycode,
        overflow_shelf     => 0,
        locked             => 0
    }, { order_by => { -asc => 'priority' } })->as_list;
}

sub shelves_by_itemtype_or_category {
    my ($self, $library_id, $biblio_itemtype, $patron_categorycode) = @_;
    return $self->search({
        library_id     => $library_id,
        overflow_shelf => 0,
        locked         => 0,
        -or => [
            { biblio_itemtype    => $biblio_itemtype },
            { patron_category_id => $patron_categorycode }
        ]
    }, { order_by => { -asc => 'priority' } })->as_list;
}

sub shelves_by_category {
    my ($self, $library_id, $patron_categorycode) = @_;
    return $self->search({
        library_id         => $library_id,
        patron_category_id => $patron_categorycode,
        overflow_shelf     => 0,
        locked             => 0
    }, { order_by => { -asc => 'priority' } })->as_list;
}

sub shelves_by_itemtype {
    my ($self, $library_id, $biblio_itemtype) = @_;
    return $self->search({
        library_id      => $library_id,
        biblio_itemtype => $biblio_itemtype,
        overflow_shelf  => 0,
        locked          => 0
    }, { order_by => { -asc => 'priority' } })->as_list;
}

sub shelves_all_primary {
    my ($self, $library_id) = @_;
    return $self->search(
        { library_id => $library_id, overflow_shelf => 0, locked => 0 },
        { order_by => { -asc => 'priority' } }
    )->as_list;
}

=head3 overflow_shelves
Returns the list of overflow shelves for a given library.
=cut
sub overflow_shelves {
    my ($self, $library_id) = @_;
    return $self->search(
        { library_id => $library_id, overflow_shelf => 1, locked => 0 },
        { order_by => { -asc => 'priority' } }
    )->as_list;
}

=head3 _get_holds_count_for_shelves
Returns a hash of shelf_id => holds_count for given shelf IDs using a single query.
Internal optimization method.
=cut
sub _get_holds_count_for_shelves {
    my ($self, $shelf_ids) = @_;
    return () unless $shelf_ids && @$shelf_ids;
    
    my $dbh = C4::Context->dbh;
    my $placeholders = join(',', ('?') x @$shelf_ids);
    my $query = qq{
        SELECT hold_pickup_shelf_id, COUNT(*) as count
        FROM reserves
        WHERE hold_pickup_shelf_id IN ($placeholders)
        GROUP BY hold_pickup_shelf_id
    };
    
    my $sth = $dbh->prepare($query);
    $sth->execute(@$shelf_ids);
    
    my %counts;
    while (my $row = $sth->fetchrow_hashref) {
        $counts{$row->{hold_pickup_shelf_id}} = $row->{count};
    }
    return %counts;
}

=head3 _check_duplicates_for_shelves
Returns a hash of shelf_id => 1 for shelves that already have the biblio.
Internal optimization method.
=cut
sub _check_duplicates_for_shelves {
    my ($self, $shelf_ids, $biblio_id) = @_;
    return () unless $shelf_ids && @$shelf_ids && $biblio_id;
    
    my $dbh = C4::Context->dbh;
    my $placeholders = join(',', ('?') x @$shelf_ids);
    my $query = qq{
        SELECT DISTINCT hold_pickup_shelf_id
        FROM reserves
        WHERE hold_pickup_shelf_id IN ($placeholders)
        AND biblionumber = ?
    };
    
    my $sth = $dbh->prepare($query);
    $sth->execute(@$shelf_ids, $biblio_id);
    
    my %duplicates;
    while (my $row = $sth->fetchrow_hashref) {
        $duplicates{$row->{hold_pickup_shelf_id}} = 1;
    }
    return %duplicates;
}

=head3 lock_previously_used_shelves
Locks all shelves that are in use for a given library.
This method is used to prevent shelves that have been used previously from being used again.
Optimized to use bulk operations.
=cut
sub lock_previously_used_shelves {
    my ($self, $library_id) = @_;
    my $today = DateTime->now->ymd;
    my $shelves = $self->search({
        library_id    => $library_id,
        locked        => 0,
        last_used_date => { '<' => $today }
    })->as_list;
    
    return unless @$shelves;
    
    # Bulk fetch hold counts
    my @shelf_ids = map { $_->hold_pickup_shelf_id } @$shelves;
    my %holds_count = $self->_get_holds_count_for_shelves(\@shelf_ids);
    
    # Collect shelf IDs that need locking
    my @shelves_to_lock;
    for my $shelf (@$shelves) {
        # Only lock if there are holds linked to this shelf
        my $holds_count = $holds_count{$shelf->hold_pickup_shelf_id} || 0;
        if ($holds_count > 0) {
            push @shelves_to_lock, $shelf->hold_pickup_shelf_id;
        }
    }
    
    # Bulk update all shelves that need locking
    if (@shelves_to_lock) {
        $self->search({
            hold_pickup_shelf_id => { -in => \@shelves_to_lock }
        })->update({
            locked => 1,
            locked_date => DateTime->now,
            last_used_date => undef
        });
    }
}

=head3 open_locked_shelves
Opens all locked shelves for a given library.
This method is used to unlock shelves that are not locked today.
Optimized to use bulk operations.
=cut
sub open_locked_shelves {
    my ($self, $library_id) = @_;
    my $shelves = $self->search({library_id => $library_id, locked => 1})->as_list;
    
    return unless @$shelves;
    
    # Bulk fetch hold counts
    my @shelf_ids = map { $_->hold_pickup_shelf_id } @$shelves;
    my %holds_count = $self->_get_holds_count_for_shelves(\@shelf_ids);
    
    # Collect shelf IDs that need unlocking
    my @shelves_to_unlock;
    for my $shelf (@$shelves) {
        # Only unlock if there are no holds linked to this shelf
        my $holds_count = $holds_count{$shelf->hold_pickup_shelf_id} || 0;
        if ($holds_count == 0) {
            push @shelves_to_unlock, $shelf->hold_pickup_shelf_id;
        }
    }
    
    # Bulk update all shelves that need unlocking
    if (@shelves_to_unlock) {
        $self->search({
            hold_pickup_shelf_id => { -in => \@shelves_to_unlock }
        })->update({
            locked => 0,
            locked_date => undef,
            patron_id => undef
        });
    }
}

=head3 biblio_level_itemtypes
Returns the list of item types or authorised values for the biblio level item type parameter
=cut

sub biblio_level_itemtypes {
    my ($self) = @_;
    my $config = C4::Context->preference('HoldPickupShelvesBiblioLevelItemTypeParameter');
    my $response = [];
    if ($config eq 'itemtypes') {
        my $item_types = Koha::ItemTypes->search->unblessed;
        foreach my $item_type (@$item_types) {
            $item_type->{name} = $item_type->{description};
            $item_type->{id} = $item_type->{itemtype};
            push @$response, $item_type;
        }
    } else {
        my $authorsed_values = Koha::AuthorisedValues->search({ category => $config })->unblessed;
        foreach my $authorised_value ( @$authorsed_values ) {
            $authorised_value->{name} = $authorised_value->{lib};
            $authorised_value->{id} = $authorised_value->{authorised_value};
            push @{$response}, $authorised_value;
        }
    }
    # _order_by from the REST client is not applied here as this isn't a DBIC resultset
    return [ sort { $a->{name} cmp $b->{name} } @$response ];
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'HoldPickupShelve';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::HoldPickupShelf';
}

1;
