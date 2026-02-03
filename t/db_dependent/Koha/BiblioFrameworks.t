#!/usr/bin/perl

# Copyright 2015 Koha Development team
#
# This file is part of Koha
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
use Test::NoWarnings;
use Test::More tests => 5;
use Test::MockModule;
use MARC::Record;
use MARC::Field;

use Koha::BiblioFramework;
use Koha::BiblioFrameworks;
use Koha::Database;
use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

my $nb_of_frameworks = Koha::BiblioFrameworks->search->count;
my $new_framework_1  = Koha::BiblioFramework->new(
    {
        frameworkcode => 'mfw1',
        frameworktext => 'my_frameworktext_for_fw_1',
    }
)->store;
my $new_framework_2 = Koha::BiblioFramework->new(
    {
        frameworkcode => 'mfw2',
        frameworktext => 'my_frameworktext_for_fw_2',
    }
)->store;

is( Koha::BiblioFrameworks->search->count, $nb_of_frameworks + 2, 'The 2 biblio frameworks should have been added' );

my $retrieved_framework_1 = Koha::BiblioFrameworks->find( $new_framework_1->frameworkcode );
is(
    $retrieved_framework_1->frameworktext, $new_framework_1->frameworktext,
    'Find a biblio framework by frameworkcode should return the correct framework'
);

$retrieved_framework_1->delete;
is( Koha::BiblioFrameworks->search->count, $nb_of_frameworks + 1, 'Delete should have deleted the biblio framework' );

subtest 'fill_with_default_values' => sub {
    plan tests => 14;

    # Create a test framework
    my $framework     = $builder->build_object( { class => 'Koha::BiblioFrameworks' } );
    my $frameworkcode = $framework->frameworkcode;

    my $default_008    = '######s################';
    my $default_author = 'Default Author';

    my $biblio_module = Test::MockModule->new('C4::Biblio');
    $biblio_module->mock(
        'GetMarcStructure',
        sub {
            return {
                # default for a control field
                '008' => {
                    x => { defaultvalue => $default_008 },
                },

                # default value for an existing field
                '245' => {
                    c          => { defaultvalue => $default_author, mandatory => 1 },
                    mandatory  => 0,
                    repeatable => 0,
                    tab        => 0,
                    lib        => 'a lib',
                },

                # default for a nonexisting field
                '099' => {
                    x => { defaultvalue => 'default_099' },
                },
                '942' => {
                    c => { defaultvalue => 'BK', mandatory => 1 },
                    d => { defaultvalue => '942d_val' },
                    f => { defaultvalue => '942f_val' },
                },
            };
        }
    );

    # Mock GetMarcFromKohaField to return item field
    $biblio_module->mock( 'GetMarcFromKohaField', sub { return ( '952', 'i' ); } );

    # Mock IsMarcStructureInternal - return true for non-hashref (tag properties), false for subfields
    $biblio_module->mock(
        'IsMarcStructureInternal',
        sub {
            my ($subfieldstruct) = @_;
            return 1 unless ref($subfieldstruct) eq 'HASH';
            return 0;
        }
    );

    # Test 1: Fill defaults for existing record
    my $record = MARC::Record->new();
    $record->leader('03174nam a2200445 a 4500');
    my @fields = (
        MARC::Field->new(
            '008', '120829t20132012nyu bk 001 0ceng',
        ),
        MARC::Field->new(
            100, '1', ' ',
            a => 'Knuth, Donald Ervin',
            d => '1938',
        ),
        MARC::Field->new(
            245, '1', '4',
            a => 'The art of computer programming',
            c => 'Donald E. Knuth.',
        ),
        MARC::Field->new(
            245, '1', '4', a => 'my second title',
        ),
    );

    $record->append_fields(@fields);
    $framework->fill_with_default_values($record);

    my @fields_245 = $record->field(245);
    is( scalar(@fields_245), 2, 'No new 245 field has been created' );
    my @subfields_245_0 = $fields_245[0]->subfields;
    my @subfields_245_1 = $fields_245[1]->subfields;
    is_deeply(
        \@subfields_245_0,
        [ [ 'a', 'The art of computer programming' ], [ 'c', 'Donald E. Knuth.' ] ],
        'first 245 field has not been updated'
    );
    is_deeply(
        \@subfields_245_1,
        [ [ 'a', 'my second title' ], [ 'c', $default_author ] ],
        'second 245 field has a new subfield c with a default value'
    );

    # Test 2: New field with default is created
    my @fields_099 = $record->field('099');
    is( scalar(@fields_099), 1, '1 new 099 field has been created' );
    my @subfields_099 = $fields_099[0]->subfields;
    is_deeply(
        \@subfields_099,
        [ [ 'x', 'default_099' ] ],
        '099$x contains the default value'
    );

    # Test 3: Control field default is applied when undefined
    $record->field('008')->update(undef);
    $framework->fill_with_default_values($record);
    is( $record->field('008')->data, $default_008, 'Controlfield got default' );

    # Test 4: Check 942 fields
    is( $record->subfield( '942', 'd' ), '942d_val', 'Check 942d' );

    # Test 5: Only mandatory parameter
    $record->delete_fields( $record->field('245') );
    $record->delete_fields( $record->field('942') );
    $record->append_fields( MARC::Field->new( '942', '', '', 'f' => 'f val' ) );

    # We deleted 245 and replaced 942. If we only apply mandatories, we should get
    # back 245c again and 942c but not 942d. 942f should be left alone.
    $framework->fill_with_default_values( $record, { only_mandatory => 1 } );
    @fields_245 = $record->field(245);
    is( scalar @fields_245, 1, 'Only one 245 expected' );
    is( $record->subfield( '245', 'c' ), $default_author, '245c restored' );
    is( $record->subfield( '942', 'c' ), 'BK',            '942c also restored' );
    is( $record->subfield( '942', 'd' ), undef,           '942d should not be there' );
    is( $record->subfield( '942', 'f' ), 'f val',         '942f untouched' );

    # Test 6: Handle undefined record gracefully
    my $record_undef;
    $framework->fill_with_default_values($record_undef);
    ok( !defined $record_undef, 'Undefined record handled without error' );

    # Test 7: Empty record should get defaults
    my $empty_record = MARC::Record->new();
    $framework->fill_with_default_values($empty_record);
    is( $empty_record->subfield( '942', 'c' ), 'BK', 'Empty record gets default 942c' );
};

$schema->storage->txn_rollback;
