package Koha::REST::V1::Items::Transfers;

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
use Koha::Item::Transfers;
use Koha::Libraries;
use Koha::Items;
use Koha::Patrons;
use Koha::Recalls;
use C4::Context;

use Koha::Exceptions::Item::Transfer;

use Scalar::Util qw( blessed );

use Try::Tiny qw( catch try );

=head1 NAME

Koha::REST::V1::Items::Transfers - Koha REST API for handling item transfers (V1)

=head1 API

=head2 Methods

=cut

=head3 list

Controller function that handles listing Koha::Item::Transfers objects

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $transfers = $c->objects->search( Koha::Item::Transfers->new );
        return $c->render( status => 200, openapi => $transfers );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

Controller function that handles retrieving a single Koha::Item::Transfer

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $item_id = $c->param('item_id');
    my $item    = Koha::Items->find($item_id);

    return $c->render_resource_not_found("Item")
        unless $item;
    try {
        my $transfer = $item->transfer;

        return $c->render(
            status  => 404,
            openapi => { error => "Item is not in transfer" },
        ) unless $transfer;

        return $c->render(
            status  => 200,
            openapi => $c->objects->to_api($transfer),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

Controller function that handles adding a new transfer

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    my $item_id       = $c->param('item_id');
    my $item          = Koha::Items->find($item_id);
    my $ignore_limits = $c->param('ignore_limits');
    my $enqueue       = $c->param('enqueue');
    my $replace       = $c->param('replace');

    return $c->render_resource_not_found("Item")
        unless $item;

    my $body = $c->req->json;

    my $to_library = Koha::Libraries->find( $body->{to_library_id} );

    return $c->render_resource_not_found("Library")
        unless $to_library;
    return try {
        my $params = {
            to      => $to_library,
            reason  => $body->{reason},
            comment => $body->{comments},
        };
        $params->{ignore_limits} = $ignore_limits if defined $ignore_limits;
        $params->{enqueue}       = $enqueue       if defined $enqueue;
        $params->{replace}       = $replace       if defined $replace;

        my $transfer = $item->request_transfer($params);
        $transfer->transit;
        return $c->render(
            status  => 201,
            openapi => $c->objects->to_api($transfer),
        );
    } catch {
        if ( blessed $_ && $_->isa('Koha::Exceptions::Item::Transfer::InQueue') ) {
            return $c->render(
                status  => 409,
                openapi => { error => "Item is already in transfer queue" },
            );
        }
        $c->unhandled_exception($_);
    };
}

=head3 cancel

Controller function that handles deleting a transfer

=cut

sub cancel {
    my $c = shift->openapi->valid_input or return;

    my $item_id = $c->param('item_id');
    my $item    = Koha::Items->find($item_id);

    return $c->render_resource_not_found("Item")
        unless $item;

    my $reason = $c->param('reason') || "Manual";

    return try {
        my $transfer = $item->transfer;
        return $c->render(
            status  => 404,
            openapi => { error => "Item is not in transfer" },
        ) unless $transfer;

        $transfer->cancel(
            {
                reason => $reason,
                force  => 1,
            }
        );
        if ( C4::Context->preference('UseRecalls') ) {
            my $recall_transfer_deleted = Koha::Recalls->find( { item_id => $item_id, status => 'in_transit' } );
            if ( defined $recall_transfer_deleted ) {
                $recall_transfer_deleted->revert_transfer;
            }
        }
        return $c->render_resource_deleted;
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
