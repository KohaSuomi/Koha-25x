#!/usr/bin/perl

use Modern::Perl;

use t::lib::Mocks;
use C4::Context;

use Test::NoWarnings;
use Test::More tests => 8;
use MARC::Record;

use Koha::Patrons;
use Koha::Holds;
use C4::Biblio;
use C4::Items;
use Koha::Database;
use Koha::Library::Groups;

use t::lib::TestBuilder;

BEGIN {
    use FindBin;
    use lib $FindBin::Bin;
    use_ok( 'C4::Reserves', qw( AddReserve CheckReserves RecordFulfillmentSkips ModReserveAffect ) );
}

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;

my $library1 = $builder->build( { source => 'Branch', } );
my $library2 = $builder->build( { source => 'Branch', } );
my $library3 = $builder->build( { source => 'Branch', } );
my $library4 = $builder->build( { source => 'Branch', } );
my $library5 = $builder->build( { source => 'Branch', } );
my $itemtype = $builder->build(
    {
        source => 'Itemtype',
        value  => { notforloan => 0, rentalcharge => 0 }
    }
)->{itemtype};

my $borrowers_count = 5;

# Create some groups
my $group1 =
    Koha::Library::Group->new( { title => "Test hold group 1", ft_local_hold_group => '1' } )->store();
my $group2 =
    Koha::Library::Group->new( { title => "Test hold group 2", ft_local_hold_group => '1' } )->store();

#Add branches to the groups
my $group1_library1 =
    Koha::Library::Group->new( { parent_id => $group1->id, branchcode => $library1->{branchcode} } )->store();
my $group1_library2 =
    Koha::Library::Group->new( { parent_id => $group1->id, branchcode => $library2->{branchcode} } )->store();
my $group2_library1 =
    Koha::Library::Group->new( { parent_id => $group2->id, branchcode => $library3->{branchcode} } )->store();
my $group2_library2 =
    Koha::Library::Group->new( { parent_id => $group2->id, branchcode => $library4->{branchcode} } )->store();

# group1
#    group1_library1
#    group1_library2
# group2
#    group2_library1
#    group2_library2

my $biblio = $builder->build_sample_biblio();
my $item   = Koha::Item->new(
    {
        biblionumber                      => $biblio->biblionumber,
        homebranch                        => $library4->{branchcode},
        holdingbranch                     => $library3->{branchcode},
        itype                             => $itemtype,
        exclude_from_local_holds_priority => 0,
    },
)->store->get_from_storage;

my $item2 = Koha::Item->new(
    {
        biblionumber                      => $biblio->biblionumber,
        homebranch                        => $library1->{branchcode},
        holdingbranch                     => $library1->{branchcode},
        itype                             => $itemtype,
        exclude_from_local_holds_priority => 0,
    },
)->store->get_from_storage;

my @branchcodes = (
    $library1->{branchcode}, $library2->{branchcode}, $library3->{branchcode}, $library4->{branchcode},
    $library3->{branchcode}, $library4->{branchcode}
);
my $patron_category = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => 0 } } );

# Create some borrowers
my @borrowernumbers;
my $r = 0;
foreach ( 0 .. $borrowers_count - 1 ) {
    my $borrowernumber = Koha::Patron->new(
        {
            firstname    => 'my firstname',
            surname      => 'my surname ' . $_,
            categorycode => $patron_category->{categorycode},
            branchcode   => $branchcodes[$r],
        }
    )->store->borrowernumber;
    push @borrowernumbers, $borrowernumber;
    $r++;
}

# Create five record level holds
AddReserve(
    {
        branchcode     => $library1->{branchcode},
        borrowernumber => $borrowernumbers[0],
        biblionumber   => $item->biblionumber,
        priority       => 1,
    }
);
AddReserve(
    {
        branchcode     => $library2->{branchcode},
        borrowernumber => $borrowernumbers[1],
        biblionumber   => $item->biblionumber,
        priority       => 1,
    }
);
AddReserve(
    {
        branchcode     => $library3->{branchcode},
        borrowernumber => $borrowernumbers[2],
        biblionumber   => $item->biblionumber,
        priority       => 1,
    }
);
AddReserve(
    {
        branchcode     => $library4->{branchcode},
        borrowernumber => $borrowernumbers[3],
        biblionumber   => $item->biblionumber,
        priority       => 1,
    }
);
my ( $status, $reserve, $all_reserves );
t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'None' );
( $status, $reserve, $all_reserves ) = CheckReserves($item);
ok( $reserve->{borrowernumber} eq $borrowernumbers[0], "Received expected results with LocalHoldsPriority disabled" );

subtest 'LocalHoldsPriority, GiveLibrary' => sub {    #Test library only priority
    plan tests => 4;

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibrary' );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron is given priority when patron pickup and item home branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[2],
        "Local patron is given priority when patron pickup location and item home branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[2],
        "Local patron is given priority when patron home library and item holding branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron is given priority when patron home location and item home branch match"
    );

};

subtest 'LocalHoldsPriority, GiveLibraryAndGroup' => sub {    #Test library then hold group priority
    plan tests => 4;
    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibraryAndGroup' );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron is given priority when patron pickup and item home branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[2],
        "Local patron in group is given priority when patron pickup location and item home branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item2);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[0],
        "Local patron in group is given priority when patron home library and item holding branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron is given priority when patron home location and item home branch match"
    );

};

subtest 'LocalHoldsPriority, GiveLibraryGroup' => sub {    #Test hold group only priority
    plan tests => 4;
    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibraryGroup' );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron in group is given priority when patron pickup location and item home branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron in group is given priority when patron pickup location and item holding branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'holdingbranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron in group is given priority when patron home library and item holding branch match"
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item);
    ok(
        $reserve->{borrowernumber} eq $borrowernumbers[3],
        "Local patron in group is given priority when patron home library and item home branch match"
    );
};

$schema->storage->txn_rollback;

subtest "exclude from local holds" => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority',              'GiveLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );

    my $category_ex = $builder->build_object(
        { class => 'Koha::Patron::Categories', value => { exclude_from_local_holds_priority => 1 } } );
    my $category_nex = $builder->build_object(
        { class => 'Koha::Patron::Categories', value => { exclude_from_local_holds_priority => 0 } } );

    my $lib1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $lib2 = $builder->build_object( { class => 'Koha::Libraries' } );

    my $item1 =
        $builder->build_sample_item( { exclude_from_local_holds_priority => 0, homebranch => $lib1->branchcode } );
    my $item2 =
        $builder->build_sample_item( { exclude_from_local_holds_priority => 1, homebranch => $lib1->branchcode } );

    my $patron_ex_l2 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib2->branchcode, categorycode => $category_ex->categorycode }
        }
    );
    my $patron_ex_l1 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib1->branchcode, categorycode => $category_ex->categorycode }
        }
    );
    my $patron_nex_l2 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib2->branchcode, categorycode => $category_nex->categorycode }
        }
    );
    my $patron_nex_l1 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib1->branchcode, categorycode => $category_nex->categorycode }
        }
    );

    AddReserve(
        {
            branchcode     => $patron_nex_l2->branchcode,
            borrowernumber => $patron_nex_l2->borrowernumber,
            biblionumber   => $item1->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $patron_ex_l1->branchcode,
            borrowernumber => $patron_ex_l1->borrowernumber,
            biblionumber   => $item1->biblionumber,
            priority       => 2,
        }
    );
    AddReserve(
        {
            branchcode     => $patron_nex_l1->branchcode,
            borrowernumber => $patron_nex_l1->borrowernumber,
            biblionumber   => $item1->biblionumber,
            priority       => 3,
        }
    );

    my ( $status, $reserve, $all_reserves );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item1);
    is(
        $reserve->{borrowernumber}, $patron_nex_l1->borrowernumber,
        "Patron not excluded with local holds priorities is next checkout"
    );

    Koha::Holds->delete;

    AddReserve(
        {
            branchcode     => $patron_nex_l2->branchcode,
            borrowernumber => $patron_nex_l2->borrowernumber,
            biblionumber   => $item1->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $patron_ex_l1->branchcode,
            borrowernumber => $patron_ex_l1->borrowernumber,
            biblionumber   => $item1->biblionumber,
            priority       => 2,
        }
    );

    ( $status, $reserve, $all_reserves ) = CheckReserves($item1);
    is( $reserve->{borrowernumber}, $patron_nex_l2->borrowernumber, "Local patron is excluded from priority" );

    Koha::Holds->delete;

    AddReserve(
        {
            branchcode     => $patron_nex_l2->branchcode,
            borrowernumber => $patron_nex_l2->borrowernumber,
            biblionumber   => $item2->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $patron_nex_l1->branchcode,
            borrowernumber => $patron_nex_l1->borrowernumber,
            biblionumber   => $item2->biblionumber,
            priority       => 2,
        }
    );

    ( $status, $reserve, $all_reserves ) = CheckReserves($item2);
    is(
        $reserve->{borrowernumber}, $patron_nex_l2->borrowernumber,
        "Patron from other library is next checkout because item is excluded"
    );

    $schema->storage->txn_rollback;
};

subtest "fulfillment skips" => sub {
    plan tests => 7;

    $schema->storage->txn_begin;

    my $lib1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $lib2 = $builder->build_object( { class => 'Koha::Libraries' } );

    my $item3 = $builder->build_sample_item(
        {
            exclude_from_local_holds_priority => 0,
            homebranch                        => $lib2->branchcode,
            holdingbranch                     => $lib2->branchcode,
        }
    );
    my $category_nex = $builder->build_object(
        { class => 'Koha::Patron::Categories', value => { exclude_from_local_holds_priority => 0 } } );

    my $patron_nex_l1 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib1->branchcode, categorycode => $category_nex->categorycode }
        }
    );
    my $patron_nex_l2 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { branchcode => $lib2->branchcode, categorycode => $category_nex->categorycode }
        }
    );

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority',              'GiveLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'HomeLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityFulfillmentSkips', '2' );

    AddReserve(
        {
            branchcode     => $lib1->branchcode,
            borrowernumber => $patron_nex_l1->borrowernumber,
            biblionumber   => $item3->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $lib2->branchcode,
            borrowernumber => $patron_nex_l2->borrowernumber,
            biblionumber   => $item3->biblionumber,
            priority       => 2,
        }
    );

    my ( $status, $reserve, $all_reserves );
    ( $status, $reserve, $all_reserves ) = CheckReserves($item3);
    is( $reserve->{borrowernumber}, $patron_nex_l2->borrowernumber, "Local match wins" );

    my @reserves_in_order = sort { $a->{priority} <=> $b->{priority} } @$all_reserves;
    my $skipped_hold_id   = $reserves_in_order[0]->{reserve_id};
    my $winning_hold_id   = $reserves_in_order[1]->{reserve_id};

    is(
        Koha::Holds->find($skipped_hold_id)->fulfillment_skips, 0,
        "CheckReserves does not increment fulfillment_skips"
    );

    RecordFulfillmentSkips( $item3->itemnumber, $winning_hold_id );
    is(
        Koha::Holds->find($skipped_hold_id)->fulfillment_skips, 1,
        "RecordFulfillmentSkips counts the hold passed over when fulfilling"
    );
    is(
        Koha::Holds->find($winning_hold_id)->fulfillment_skips, 0,
        "The fulfilled hold itself is not counted"
    );

    RecordFulfillmentSkips( $item3->itemnumber, $winning_hold_id );
    RecordFulfillmentSkips( $item3->itemnumber, $winning_hold_id );
    RecordFulfillmentSkips( $item3->itemnumber, $winning_hold_id );
    is(
        Koha::Holds->find($skipped_hold_id)->fulfillment_skips, 2,
        "fulfillment_skips is capped at the LocalHoldsPriorityFulfillmentSkips threshold"
    );

    my $item4 = $builder->build_sample_item(
        {
            exclude_from_local_holds_priority => 0,
            homebranch                        => $lib2->branchcode,
            holdingbranch                     => $lib2->branchcode,
        }
    );
    AddReserve(
        {
            branchcode     => $lib1->branchcode,
            borrowernumber => $patron_nex_l1->borrowernumber,
            biblionumber   => $item4->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $lib2->branchcode,
            borrowernumber => $patron_nex_l2->borrowernumber,
            biblionumber   => $item4->biblionumber,
            priority       => 2,
        }
    );

    my ( $status2, $reserve2, $all_reserves2 ) = CheckReserves($item4);
    my @fullfills2   = sort { $a->{priority} <=> $b->{priority} } @$all_reserves2;
    my $skipped_id2  = $fullfills2[0]->{reserve_id};

    ModReserveAffect( $item4->itemnumber, $reserve2->{borrowernumber}, 0, $reserve2->{reserve_id} );
    is(
        Koha::Holds->find($skipped_id2)->fulfillment_skips, 1,
        "ModReserveAffect records the fulfillment skips"
    );

    ModReserveAffect( $item4->itemnumber, $reserve2->{borrowernumber}, 0, $reserve2->{reserve_id} );
    is(
        Koha::Holds->find($skipped_id2)->fulfillment_skips, 1,
        "Re-affecting an already waiting hold does not record further skips"
    );

    $schema->storage->txn_rollback;
};
