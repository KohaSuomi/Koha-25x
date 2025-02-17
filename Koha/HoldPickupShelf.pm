package Koha::HoldPickupShelf;

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

use base qw(Koha::Object);
use Koha::Library;
use Koha::Holds;
use Koha::Exceptions::Object;

=head1 NAME

Koha::HoldPickupShelf - Koha HoldPickupShelf Object class

=head1 API

=head3 library

Returns the related library object.

=cut

sub library {
    my ($self) = @_;
    my $rs = $self->_result->library;
    return Koha::Library->_new_from_dbic($rs);
}

=head3 patron_category
Returns the related category object.
=cut

sub patron_category {
    my ($self) = @_;
    my $rs = $self->_result->patron_category;
    return unless $rs;
    return Koha::Patron::Category->_new_from_dbic($rs);
}

=head3 biblio_level_itemtype
Returns the related item type object.
=cut
sub biblio_level_itemtype {
    my ($self) = @_;
    my $config = C4::Context->preference('HoldPickupShelvesBiblioLevelItemTypeParameter');
    my $biblio_itemtype = $self->_result->biblio_itemtype;
    return '' unless $biblio_itemtype;
    if ($config eq 'itemtypes') {
        my $itemtype = Koha::ItemTypes->search({ itemtype => $biblio_itemtype })->next;
        return '' unless $itemtype;
        return $itemtype->description;
    } else {
        my $authorised_value = Koha::AuthorisedValues->search({ category => $config, authorised_value => $biblio_itemtype})->next;
        return '' unless $authorised_value;
        return $authorised_value->lib;
    }
}

=head3 available_shelf
Return if the shelf is available for holds
=cut

sub available_shelf {
    my ($self, $biblio_id, $patron_id) = @_;
    my $patron = Koha::Patrons->find($patron_id);
    my $patron_category_id = $self->_result->patron_category_id;
    my $biblio_itemtype = $self->_result->biblio_itemtype;
    my $biblio = Koha::Biblios->find($biblio_id);

    if ($biblio_id && $self->duplicate_record($biblio_id)) {
        return 0;
    }
    if ($patron && $patron_category_id && $patron->categorycode ne $patron_category_id) {
        return 0;
    }

    if ($biblio_itemtype && $biblio && defined $biblio->itemtype && $biblio->itemtype ne $biblio_itemtype) {
        return 0;
    }

    if ($self->holds_count >= $self->max_items) {
        return 0;
    }

    return $self->weekday_match;
}

=head3 duplicate_shelf
Checks if shelf already has a record in the database.
=cut
sub duplicate_shelf {
    my ($self) = @_;

    my $rs = Koha::HoldPickupShelves->search({ 
        library_id => $self->_result->library_id,
        shelf_name => $self->_result->shelf_name,
        weekday => $self->_result->weekday,
        biblio_itemtype => $self->_result->biblio_itemtype,
        patron_category_id => $self->_result->patron_category_id,
    })->next;
    return $rs->hold_pickup_shelf_id if $rs;
    return 0;
}

=head3 calculate_priority
Returns the priority of the shelf.
=cut

sub calculate_priority {
    my ($self, $priority) = @_;
    if (!defined $priority) {
        # If no priority is given, we calculate the next available priority
        # by checking the existing shelves and finding the next available priority
        $priority = $self->next_priority;
    } else {
        my $current_priority = $self->_result->priority;
        my $shelf_with_current_priority = Koha::HoldPickupShelves->search({
            priority => $priority,
            hold_pickup_shelf_id => { '!=' => $self->_result->hold_pickup_shelf_id }
        })->next;
        
        if ($shelf_with_current_priority) {
            $shelf_with_current_priority->update({
                priority => $current_priority,
            });
            
        }
    }
    $self->_result->priority($priority);
    return $self->_result->priority;     
}

sub next_priority {
    my ($self) = @_;
    my $shelves_sorted = Koha::HoldPickupShelves->search(
        {},
        { order_by => { -asc => 'priority' } }
    )->last;

    return $shelves_sorted ? $shelves_sorted->priority + 1 : 1;
}

=head3 holds_count

Returns the number of holds on this hold pickup shelf.

=cut

sub holds_count {
    my ($self) = @_;
    return Koha::Holds->search({ hold_pickup_shelf_id => $self->_result->hold_pickup_shelf_id })->count;
}

=head3 duplicate_record

Checks if shelf already has a record in the database.

=cut

sub duplicate_record {
    my ($self, $biblio_id) = @_;
    my $rs = Koha::Holds->search({ hold_pickup_shelf_id => $self->_result->hold_pickup_shelf_id, biblionumber => $biblio_id });
    return $rs->count();
}

=head3 weekday_match
Checks if the shelf is open on the given weekday.
=cut
sub weekday_match {
    my ($self) = @_;
    my $weekday = $self->_result->weekday;
    my @days = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
    my $today = $days[(localtime)[6]];
    my $open = 1;
    if ($weekday) {
        if ($weekday ne $today) {
            $open = 0;
        }
    } 
    return $open;
}

=head3 lock_full_shelf
Locks the shelf if it is full.
=cut
sub lock_full_shelf {
    my ($self) = @_;
    my $shelf = Koha::HoldPickupShelves->find($self->_result->hold_pickup_shelf_id);
    if ($shelf->holds_count >= $shelf->max_items) {
        my $today = DateTime->today->ymd;
        $shelf->update({ locked => 1, locked_date => $today });
    }
}

=head3 delete

Overridden delete method to prevent system default deletions

=cut

sub delete {
    my ($self) = @_;
    
    if ($self->holds_count) {
        # If there are holds on this pickup shelf, we cannot delete it
        Koha::Exceptions::Object::FKConstraint->throw(
            "Cannot delete a pickup shelf that has holds"
        );
    }

    return $self->SUPER::delete;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'HoldPickupShelve';
}

1;
