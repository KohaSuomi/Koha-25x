#!/usr/bin/env perl

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

use Test::More tests => 7;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::HoldPickupShelves;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'list() tests' => sub {

    plan tests => 14;

    $schema->storage->txn_begin;

    my $hold_pickup_shelf = $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );

    for ( 1 .. 10 ) {
        $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    }

    my $nonprivilegedpatron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    my $password = 'thePassword123';

    $nonprivilegedpatron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $nonprivilegedpatron->userid;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves?_per_page=10")->status_is( 200, 'REST3.2.2' );

    my $response_count = scalar @{ $t->tx->res->json };

    is( $response_count, 10, 'The API returns 10 shelves' );

    my $id = $hold_pickup_shelf->hold_pickup_shelf_id;
    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves?q={\"hold_pickup_shelf_id\": $id}")->status_is(200)
        ->json_is( '' => [ $hold_pickup_shelf->to_api ], 'REST3.3.2' );

    $hold_pickup_shelf->delete;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves?q={\"hold_pickup_shelf_id\": $id}")->status_is(200)
        ->json_is( '' => [] );

    # Test x-koha-embed header

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves?_per_page=10", { 'x-koha-embed' => 'library' } )
        ->status_is( 200, 'REST3.2.2' );

    $schema->storage->txn_rollback;
};

subtest 'get() tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    my $hold_pickup_shelf = $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );

    my $nonprivilegedpatron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    my $password = 'thePassword123';

    $nonprivilegedpatron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $nonprivilegedpatron->userid;

    my $id = $hold_pickup_shelf->hold_pickup_shelf_id;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is( 200, 'REST3.2.2' )
        ->json_is( '' => $hold_pickup_shelf->to_api, 'REST3.3.2' );

    $hold_pickup_shelf->delete;

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is(404)
        ->json_is( '/error' => 'Hold pickup shelf not found' );

    $schema->storage->txn_rollback;
};

subtest 'delete() tests' => sub {

    plan tests => 10;

    $schema->storage->txn_begin;

    my $hold_pickup_shelf = $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );

    my $nonprivilegedpatron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    my $password = 'thePassword123';

    $nonprivilegedpatron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $nonprivilegedpatron->userid;

    my $id = $hold_pickup_shelf->hold_pickup_shelf_id;

    $t->delete_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $hold_pickup_shelf->delete();
    $t->delete_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is( 404, 'REST4.3' )
        ->json_is( { error => q{Hold pickup shelf not found}, error_code => q{not_found} } );

    $hold_pickup_shelf = $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    $id     = $hold_pickup_shelf->id;

    $t->delete_ok("//$userid:$password@/api/v1/holds/pickup_shelves/$id")->status_is( 204, 'REST3.2.4' )
        ->content_is( q{}, 'REST3.3.4' );

    my $deleted_source = Koha::HoldPickupShelves->search( { hold_pickup_shelf_id => $id } );

    is( $deleted_source->count, 0, 'No hold pickup shelf' );

    $schema->storage->txn_rollback;
};

subtest 'add() tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );

    my $nonprivilegedpatron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    my $password = 'thePassword123';

    my $library = $builder->build_object(
        {
            class => 'Koha::Libraries',
            value => { branchcode => 'LIB' }
        }
    );

    my $params = {
        library_id => $library->id,
        shelf_name => 'test1',
        max_items => 10,
    };

    $nonprivilegedpatron->set_password( { password => $password, skip_validation => 1 } );
    my $userid    = $nonprivilegedpatron->userid;
    my $patron_id = $nonprivilegedpatron->borrowernumber;

    $t->post_ok( "//$userid:$password@/api/v1/holds/pickup_shelves" => json => $params )->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    my $hold_pickup_shelf_id =
        $t->post_ok( "//$userid:$password@/api/v1/holds/pickup_shelves" => json => $params )
        ->status_is( 201, 'REST3.2.2' )
        ->tx->res->json->{hold_pickup_shelf_id};

    my $created_source = Koha::HoldPickupShelves->find($hold_pickup_shelf_id);

    is( $created_source->shelf_name, 'test1', 'Shelf name is correct' );

    $schema->storage->txn_rollback;
};

subtest 'update() tests' => sub {

    plan tests => 14;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $unauth_userid = $patron->userid;

    my $library = $builder->build_object(
        {
            class => 'Koha::Libraries',
            value => { branchcode => 'LIB' }
        }
    );

    my $params = {
        library_id => $library->id,
        shelf_name => 'test1',
        max_items => 10,
    };

    my $hold_pickup_shelf    = Koha::HoldPickupShelf->new( $params )->store;
    my $hold_pickup_shelf_id = $hold_pickup_shelf->id;

    $params->{shelf_name} = 'test2';

    # Unauthorized attempt to update
    $t->put_ok( "//$unauth_userid:$password@/api/v1/holds/pickup_shelves/$hold_pickup_shelf_id" => json => $params )->status_is(403);

    # Attempt partial update on a PUT
    $params = {
        library_id => $library->id,
        shelf_name => 'test3',
    };

    $t->put_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$hold_pickup_shelf_id" => json => $params )
        ->status_is(400)->json_is( "/errors" => [ { message => "Missing property.", path => "/body/max_items" } ] );

    # Full object update on PUT
    
    $params = {
        library_id => $library->id,
        shelf_name => 'test3',
        max_items => 15,
    };

    $t->put_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$hold_pickup_shelf_id" => json => $params )
        ->status_is(200);

    # Authorized attempt to write invalid data
    $params = {
        library_id => $library->id,
        shelf_name => 'test3',
        max_items => 15,
        potato => 'potato',
    };

    $t->put_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$hold_pickup_shelf_id" => json => $params )
        ->status_is(400)->json_is(
        "/errors" => [
            {
                message => "Properties not allowed: potato.",
                path    => "/body"
            }
        ]
        );

    my $hold_pickup_shelf_to_delete = $builder->build_object( { class => 'Koha::HoldPickupShelves' } );
    my $non_existent_id  = $hold_pickup_shelf_to_delete->id;
    $hold_pickup_shelf_to_delete->delete;

    $params = {
        library_id => $library->id,
        shelf_name => 'test3',
        max_items => 15,
    };

    $t->put_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$non_existent_id" => json => $params )
        ->status_is(404);

    # Wrong method (POST)
    $params->{hold_pickup_shelf_id} = 2;

    $t->post_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$hold_pickup_shelf_id" => json => $params )
        ->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'available_shelves() tests' => sub {

    plan tests => 16;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $unauth_userid = $patron->userid;

    # Create test library
    my $library = $builder->build_object({ class => 'Koha::Libraries' });
    my $library_id = $library->branchcode;

    # Create test patron for shelves
    my $test_patron = $builder->build_object({ class => 'Koha::Patrons' });
    my $patron_id = $test_patron->borrowernumber;

    # Create test biblio
    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->biblionumber;

    # Create test shelves with different configurations
    # Set weekday, biblio_itemtype, and patron_category_id to undef so they match any day/itemtype/category
    my $shelf1 = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id => $library_id,
            shelf_name => 'A10',
            max_items => 5,
            overflow_shelf => 0,
            locked => 0,
            priority => 1,
            weekday => undef,
            biblio_itemtype => undef,
            patron_category_id => undef,
        }
    });

    my $shelf2 = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id => $library_id,
            shelf_name => 'A2',
            max_items => 5,
            overflow_shelf => 0,
            locked => 0,
            priority => 2,
            weekday => undef,
            biblio_itemtype => undef,
            patron_category_id => undef,
        }
    });

    my $locked_shelf = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id => $library_id,
            shelf_name => 'A1',
            max_items => 5,
            overflow_shelf => 0,
            locked => 1,
            locked_date => DateTime->now->subtract(days => 1)->ymd,
            priority => 3,
            weekday => undef,
            biblio_itemtype => undef,
            patron_category_id => undef,
        }
    });

    # Add holds to locked shelf so it won't be auto-unlocked
    my $dbh = $schema->storage->dbh;
    $dbh->do(q{
        INSERT INTO reserves (biblionumber, borrowernumber, branchcode, hold_pickup_shelf_id)
        VALUES (?, ?, ?, ?)
    }, undef, $biblio_id, $test_patron->borrowernumber, $library_id, $locked_shelf->hold_pickup_shelf_id);

    my $shelf4 = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id => $library_id,
            shelf_name => 'A3',
            max_items => 10,
            overflow_shelf => 0,
            locked => 0,
            priority => 2,
            weekday => undef,
            biblio_itemtype => undef,
            patron_category_id => undef,
        }
    });

    my $overflow_shelf = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id => $library_id,
            shelf_name => 'Overflow',
            max_items => 10,
            overflow_shelf => 1,
            locked => 0,
            priority => 99,
            weekday => undef,
            biblio_itemtype => undef,
            patron_category_id => undef,
        }
    });

    # Test unauthorized access
    $t->get_ok("//$unauth_userid:$password@/api/v1/holds/pickup_shelves/available?library_id=$library_id&biblio_id=$biblio_id&patron_id=$patron_id")
        ->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    # Test with authorized user
    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/available?library_id=$library_id&biblio_id=$biblio_id&patron_id=$patron_id")
        ->status_is(200);

    my $response = $t->tx->res->json;
    ok( ref($response) eq 'ARRAY', 'Response is an array' );
    ok( scalar(@$response) > 0, 'At least one shelf is available' );

    # Verify the response structure
    if (@$response) {
        my $first_shelf = $response->[0];
        ok( exists $first_shelf->{hold_pickup_shelf_id}, 'Shelf has hold_pickup_shelf_id' );
        ok( exists $first_shelf->{shelf_name}, 'Shelf has shelf_name' );
        ok( exists $first_shelf->{holds_count}, 'Shelf has holds_count' );
    }

    # Test priority sorting
    if (@$response >= 2) {
        is( $response->[0]->{shelf_name}, 'A10', 'First shelf is priority 1' );
        is( $response->[1]->{shelf_name}, 'A2', 'Second shelf is the first priority 2 shelf' );
        is( $response->[2]->{shelf_name}, 'A3', 'Third shelf is the next priority 2 shelf' ) if @$response >= 3;
    }

    # Test with non-existent library
    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/available?library_id=NONEXISTENT&biblio_id=$biblio_id&patron_id=$patron_id")
        ->status_is(200)
        ->json_is( '' => [], 'No shelves available for non-existent library' );

    $schema->storage->txn_rollback;
};

subtest 'allow_multiple tests' => sub {

    plan tests => 15;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $library = $builder->build_object({ class => 'Koha::Libraries' });
    my $library_id = $library->branchcode;

    my $patron = $builder->build_object({ class => 'Koha::Patrons' });
    my $patron_id = $patron->borrowernumber;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->biblionumber;

    # Create a shelf with allow_multiple = true via API
    my $params = {
        library_id     => $library_id,
        shelf_name     => 'AllowMultiple',
        max_items      => 5,
        allow_multiple => Mojo::JSON->true,
    };

    my $shelf_id =
        $t->post_ok( "//$userid:$password@/api/v1/holds/pickup_shelves" => json => $params )
        ->status_is( 201, 'Created shelf with allow_multiple' )
        ->tx->res->json->{hold_pickup_shelf_id};

    my $shelf = Koha::HoldPickupShelves->find($shelf_id);
    is( $shelf->allow_multiple, 1, 'allow_multiple is set to 1 in DB' );

    # duplicate_record should return 0 when allow_multiple is true
    my $dbh = $schema->storage->dbh;
    $dbh->do(q{
        INSERT INTO reserves (biblionumber, borrowernumber, branchcode, hold_pickup_shelf_id)
        VALUES (?, ?, ?, ?)
    }, undef, $biblio_id, $patron_id, $library_id, $shelf_id);

    is( $shelf->duplicate_record($biblio_id), 0,
        'duplicate_record returns 0 when allow_multiple is true' );

    # Shelf with allow_multiple should appear in available_shelves
    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/available?library_id=$library_id&biblio_id=$biblio_id&patron_id=$patron_id")
        ->status_is(200);

    my $response = $t->tx->res->json;
    my @matching = grep { $_->{hold_pickup_shelf_id} == $shelf_id } @$response;
    ok( scalar(@matching) > 0, 'Shelf appears in available shelves despite duplicate biblio' );

    # Test shelf WITHOUT allow_multiple is excluded when duplicate exists
    my $shelf2 = $builder->build_object({
        class => 'Koha::HoldPickupShelves',
        value => {
            library_id         => $library_id,
            shelf_name         => 'NoMultiple',
            max_items          => 5,
            overflow_shelf     => 0,
            locked             => 0,
            priority           => 5,
            weekday            => undef,
            biblio_itemtype    => undef,
            patron_category_id => undef,
            allow_multiple     => 0,
        }
    });
    my $shelf2_id = $shelf2->hold_pickup_shelf_id;

    $dbh->do(q{
        INSERT INTO reserves (biblionumber, borrowernumber, branchcode, hold_pickup_shelf_id)
        VALUES (?, ?, ?, ?)
    }, undef, $biblio_id, $patron_id, $library_id, $shelf2_id);

    is( $shelf2->duplicate_record($biblio_id), 1,
        'duplicate_record returns 1 when allow_multiple is false' );

    $t->get_ok("//$userid:$password@/api/v1/holds/pickup_shelves/available?library_id=$library_id&biblio_id=$biblio_id&patron_id=$patron_id")
        ->status_is(200);

    $response = $t->tx->res->json;
    @matching = grep { $_->{hold_pickup_shelf_id} == $shelf2_id } @$response;
    is( scalar(@matching), 0, 'Shelf without allow_multiple is excluded from available shelves' );

    # Update allow_multiple to false via API
    $params = {
        library_id     => $library_id,
        shelf_name     => 'AllowMultiple',
        max_items      => 5,
        allow_multiple => Mojo::JSON->false,
    };

    $t->put_ok( "//$userid:$password@/api/v1/holds/pickup_shelves/$shelf_id" => json => $params )
        ->status_is(200);

    $shelf = Koha::HoldPickupShelves->find($shelf_id);
    ok( !$shelf->allow_multiple, 'allow_multiple updated to 0 via API' );
    is( $shelf->duplicate_record($biblio_id), 1,
        'duplicate_record returns 1 after allow_multiple disabled' );

    $schema->storage->txn_rollback;
};
