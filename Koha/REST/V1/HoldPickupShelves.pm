package Koha::REST::V1::HoldPickupShelves;

# Copyright 2023 Theke Solutions
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

use Mojo::Base 'Mojolicious::Controller';

use Koha::HoldPickupShelves;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

=head1 API

=head2 Methods

=head3 list

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $library_id = $c->param('library_id');
        my $results = $library_id
            ? Koha::HoldPickupShelves->search( { library_id => $library_id } )
            : Koha::HoldPickupShelves->new;
        return $c->render(
            status  => 200,
            openapi => $c->objects->search($results)
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $hold_pickup_shelf = $c->objects->find( Koha::HoldPickupShelves->new, $c->param('hold_pickup_shelf_id') );
        return $c->render_resource_not_found("Hold pickup shelf")
            unless $hold_pickup_shelf;

        return $c->render( status => 200, openapi => $hold_pickup_shelf );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 available_shelves 

=cut

sub available_shelves {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $library_id = $c->param('library_id');
        my $biblio_id = $c->param('biblio_id');
        my $patron_id = $c->param('patron_id');
        my $response = Koha::HoldPickupShelves->available_shelves( $library_id, $biblio_id, $patron_id );
        return $c->render(
            status  => 200,
            openapi => $response
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 biblio_level_itemtypes
=cut

sub biblio_level_itemtypes {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $response = Koha::HoldPickupShelves->biblio_level_itemtypes;
        return $c->render(
            status  => 200,
            openapi => $response
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $hold_pickup_shelf = Koha::HoldPickupShelf->new_from_api( $c->req->json );
        if ( $hold_pickup_shelf->duplicate_shelf ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'The shelf already exists',
                    error_code => 'duplicate_shelf',
                }
            );
        }
        $hold_pickup_shelf->calculate_priority();
        $hold_pickup_shelf->store;
        $c->res->headers->location( $c->req->url->to_string . '/' . $hold_pickup_shelf->hold_pickup_shelf_id );
        return $c->render(
            status  => 201,
            openapi => $c->objects->to_api($hold_pickup_shelf)
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 update

=cut

sub update {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $hold_pickup_shelf_id = $c->param('hold_pickup_shelf_id');
        my $hold_pickup_shelf = $c->objects->find_rs( Koha::HoldPickupShelves->new, $hold_pickup_shelf_id );

        return $c->render_resource_not_found("Hold pickup shelf")
            unless $hold_pickup_shelf;

        my $body = $c->req->json;
        my $check_hold_pickup_shelf = Koha::HoldPickupShelf->new_from_api($body);

        if ( $check_hold_pickup_shelf->duplicate_shelf && $check_hold_pickup_shelf->duplicate_shelf != $hold_pickup_shelf_id ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'The shelf already exists',
                    error_code => 'duplicate_shelf',
                }
            );
        }
        
        # Optionally recalculate priority if needed
        $hold_pickup_shelf->calculate_priority($body->{priority}) if exists $body->{priority};

        # Update from API data
        $hold_pickup_shelf->set_from_api($body);

        $hold_pickup_shelf->store;

        return $c->render( status => 200, openapi => $c->objects->to_api($hold_pickup_shelf) );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 update_order

Update the order of the shelves.

=cut

sub batch_update_priority {
    my $c = shift->openapi->valid_input or return;

    try {
    
        my $body = $c->req->json;
        my $first_priority = $body->{first_priority};
        my $last_priority  = $body->{last_priority};
        my $new_priority  = $body->{new_priority};
        my $shelf_id = $body->{hold_pickup_shelf_id};
        my $shelf = Koha::HoldPickupShelves->find($shelf_id);

        return $c->render_resource_not_found("Hold pickup shelf")
            unless $shelf;

        my @shelves = Koha::HoldPickupShelves->search({}, { order_by => ['priority'] })->as_list;

        # Remove the selected shelf from the list
        @shelves = grep { $_->hold_pickup_shelf_id != $shelf_id } @shelves;

        if ($first_priority) {
            # Set the selected shelf's priority to 1
            $shelf->priority(1);
            $shelf->store;

            # Reassign priorities to the rest, starting from 2
            my $priority = 2;
            for my $other_shelf (@shelves) {
                $other_shelf->priority($priority++);
                $other_shelf->store;
            }
        }
        elsif ($last_priority) {
            # Set the selected shelf's priority to the last position
            my $last_priority_value = scalar(@shelves) + 1;
            $shelf->priority($last_priority_value);
            $shelf->store;
            # Reassign priorities to the rest, starting from 1
            my $priority = 1;
            for my $other_shelf (@shelves) {
                $other_shelf->priority($priority++);
                $other_shelf->store;
            }
        }
        elsif (defined $new_priority) {
            # Ensure new_priority is within valid range
            my $total_shelves = scalar(@shelves) + 1; # +1 for the moved shelf
            if ($new_priority < 1 || $new_priority > $total_shelves) {
                return $c->render(
                    status  => 400,
                    openapi => {
                        error      => 'Invalid new_priority value',
                        error_code => 'invalid_priority',
                    }
                );
            }
            # Insert the selected shelf at the new priority position
            splice(@shelves, $new_priority - 1, 0, $shelf);
            # Reassign priorities to all shelves
            my $priority = 1;
            for my $shelf_item (@shelves) {
                $shelf_item->priority($priority++);
                $shelf_item->store;
            }
        }
        return $c->render( status => 200, openapi => { message => 'Priorities updated successfully' } );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 delete

=cut

sub delete {
    my $c = shift->openapi->valid_input or return;

    my $hold_pickup_shelf = $c->objects->find_rs( Koha::HoldPickupShelves->new, $c->param('hold_pickup_shelf_id') );

    return $c->render_resource_not_found("Hold pickup shelf")
        unless $hold_pickup_shelf;

    return try {
        $hold_pickup_shelf->delete;
        return $c->render_resource_deleted;
    } catch {
        if ( blessed($_) && ref($_) eq 'Koha::Exceptions::Object::FKConstraint' ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'The shelf has items assigned to it',
                    error_code => 'cannot_delete_used',
                }
            );
        }
        $c->unhandled_exception($_);
    };
}

1;
