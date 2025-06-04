#!/usr/bin/env perl

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 5;
use Test::MockModule;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'list()' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item     = $builder->build_sample_item(
        {
            homebranch    => $library1->branchcode,
            holdingbranch => $library1->branchcode,
        }
    );

    my $transfer = $item->request_transfer( { to => $library2, reason => 'Manual' } );

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
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

    $t->get_ok("//$userid:$password@/api/v1/items/transfers")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $t->get_ok("//$userid:$password@/api/v1/items/transfers")->status_is( 200, 'Transfer list retrieved successfully' );

    my $res  = $t->tx->res->json;
    my $json = pop @$res;
    is( $json->{item_id},         $item->itemnumber,     'Item number matches' );
    is( $json->{from_library_id}, $library1->branchcode, 'From library matches' );
    is( $json->{to_library_id},   $library2->branchcode, 'To library matches' );
    is( $json->{reason},          'Manual',              'Reason matches' );

    $schema->storage->txn_rollback;
};

subtest 'get()' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item     = $builder->build_sample_item(
        {
            homebranch    => $library1->branchcode,
            holdingbranch => $library1->branchcode,
        }
    );

    my $transfer = $item->request_transfer( { to => $library2, reason => 'Manual' } );

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
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

    $t->get_ok("//$userid:$password@/api/v1/items/transfers")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;
    my $itemnumber = $item->itemnumber;
    $t->get_ok("//$userid:$password@/api/v1/items/$itemnumber/transfers")
        ->status_is( 200, 'Transfer retrieved successfully' );

    my $res = $t->tx->res->json;
    is( $res->{item_id},         $item->itemnumber,     'Item number matches' );
    is( $res->{from_library_id}, $library1->branchcode, 'From library matches' );
    is( $res->{to_library_id},   $library2->branchcode, 'To library matches' );
    is( $res->{reason},          'Manual',              'Reason matches' );

    $schema->storage->txn_rollback;
};

subtest 'add()' => sub {
    plan tests => 33;

    $schema->storage->txn_begin;

    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library3 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item     = $builder->build_sample_item(
        {
            homebranch    => $library1->branchcode,
            holdingbranch => $library1->branchcode,
        }
    );

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
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
    my $userid     = $nonprivilegedpatron->userid;
    my $itemnumber = $item->itemnumber;

    my $params = {
        to_library_id => $library2->branchcode,
        reason        => 'Manual',
    };

    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )
        ->status_is( 201, 'Transfer is created successfully' );

    my $res = $t->tx->res->json;
    is( $res->{item_id},         $item->itemnumber,     'Item number matches' );
    is( $res->{from_library_id}, $library1->branchcode, 'From library matches' );
    is( $res->{to_library_id},   $library2->branchcode, 'To library matches' );
    is( $res->{reason},          'Manual',              'Reason matches' );

    # Check transfer with limits
    my $limit = $builder->build_object( { class => 'Koha::Item::Transfer::Limits' } );
    $limit->set( { toBranch => $library3->branchcode, fromBranch => $library1->branchcode } )->store;

    $params->{to_library_id} = $library3->branchcode;
    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )
        ->status_is( 409, 'Transfer is not created due to transfer limit' );

    $t->post_ok(
        "//$userid:$password@/api/v1/items/$itemnumber/transfers?ignore_limits=1&enqueue=1" => json => $params )
        ->status_is( 201, 'Transfer is created successfully ignoring transfer limit' );

    # Duplicate transfer
    $params->{to_library_id} = $library1->branchcode;
    $params->{comments}      = 'Test comment';

    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )->status_is(409)
        ->json_is( '/error' => 'Item is already in transfer queue' );

    # Add to enqueue even if already in transfer queue
    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers?enqueue=1" => json => $params )
        ->status_is( 201, 'Transfer is created successfully to enqueue up transfer' );
    $res = $t->tx->res->json;

    is( $res->{to_library_id}, $library1->branchcode, 'To library matches' );
    is( $res->{reason},        'Manual',              'Reason matches' );
    is( $res->{comments},      'Test comment',        'Comments matches' );

    my $library_transfer_id = $res->{library_transfer_id};

    # Add to enqueue with replace
    $params->{to_library_id} = $library2->branchcode;
    $params->{reason}        = 'Reserve';
    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers?replace=WrongTransfer" => json => $params )
        ->status_is( 201, 'Transfer is created successfully to replace existing transfer' );
    $res = $t->tx->res->json;
    is( $res->{to_library_id}, $library2->branchcode, 'To library matches after replace' );
    is( $res->{reason},        'Reserve',             'Reason matches after replace' );

    # Invalid item number
    my $invalid_itemnumber = $itemnumber + 1;
    $t->post_ok( "//$userid:$password@/api/v1/items/$invalid_itemnumber/transfers" => json => $params )->status_is(404)
        ->json_is( '/error' => 'Item not found' );

    # Invalid library
    $params->{to_library_id} = 'InvalidLibrary';
    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )->status_is(404)
        ->json_is( '/error' => 'Library not found' );

    # Invalid reason
    $params->{reason} = 'InvalidReason';
    $t->post_ok( "//$userid:$password@/api/v1/items/$itemnumber/transfers" => json => $params )->status_is(400);

    $schema->storage->txn_rollback;
};

subtest 'delete()' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;

    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item     = $builder->build_sample_item(
        {
            homebranch    => $library1->branchcode,
            holdingbranch => $library1->branchcode,
        }
    );

    my $transfer = $item->request_transfer( { to => $library2, reason => 'Manual' } );

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
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
    my $userid     = $nonprivilegedpatron->userid;
    my $itemnumber = $item->itemnumber;
    $t->delete_ok("//$userid:$password@/api/v1/items/$itemnumber/transfers")->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    is( $item->transfer->branchtransfer_id, $transfer->branchtransfer_id, 'Item transfer exists' );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    $userid = $patron->userid;

    $t->delete_ok("//$userid:$password@/api/v1/items/$itemnumber/transfers")
        ->status_is( 204, 'Transfer deleted successfully' );

    is( $item->transfer, undef, 'Item transfer is removed' );

    $schema->storage->txn_rollback;
};
