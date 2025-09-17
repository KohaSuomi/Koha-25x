#!/usr/bin/perl

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

use CGI;
use Try::Tiny;
use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use Koha::Biblios;
use Koha::Old::Biblioitems;
use Koha::Old::Biblios;
use Koha::Old::Items;
use MARC::Record;

my $input            = CGI->new;
my $op               = $input->param('op') // q|form|;
my $deleted_from = $input->param('deleted_from') // '';
my $deleted_to = $input->param('deleted_to') // '';

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => 'tools/restore_records.tt',
        query         => $input,
        type          => "intranet",
        flagsrequired => { tools => 'edit_catalogue' },
    }
);

if ( $op eq 'form' ) {
    $template->param(
        op           => 'form',
        deleted_from => $deleted_from,
        deleted_to   => $deleted_to,
    );
}


if ( $op eq 'cud-list' ) {
    my $biblio_rs = Koha::Old::Biblios->search(
        {
            timestamp => {
            -between => [$deleted_from, $deleted_to . " 23:59:59"]
            }
        },    # Filter biblios deleted between the specified dates
        {
            order_by => { '-desc' => 'timestamp' },
        }
    );

    my @records;

    while ( my $biblio = $biblio_rs->next ) {
        my $record = {
            biblionumber => $biblio->biblionumber,
            title        => $biblio->title,
            subtitle     => $biblio->subtitle,
            part_name    => $biblio->part_name,
            part_number  => $biblio->part_number,
            author       => $biblio->author,
            datecreated  => $biblio->datecreated,
            timestamp    => $biblio->timestamp,
        };

        # Try to extract 773$a and 773$t from the MARCXML metadata for component records
        my $subfield_a;
        my $subfield_t;

        my $metadata_obj = $biblio->metadata;
        # If metadata is not an object, assume it's a MARCXML string
        my $marcxml = ref($metadata_obj) ? $metadata_obj->metadata : $metadata_obj;

        if ($marcxml) {
            my $marc = MARC::Record->new_from_xml($marcxml, 'UTF-8');
            if ($marc) {
                my $field_773 = $marc->field('773');
                if ($field_773) {
                    $subfield_a = $field_773->subfield('a');
                    $subfield_t = $field_773->subfield('t');
                }
            }
        }

        $record->{main_biblio_heading} = $subfield_a if $subfield_a;
        $record->{main_biblio_title} = $subfield_t if $subfield_t;

        my $biblioitem = Koha::Old::Biblioitems->find( { biblionumber => $biblio->biblionumber } );

        #Not the community way
        if ( my $itemtype = $biblioitem->itemtype ) {
            my $authorised_value = Koha::AuthorisedValues->search(
            {
                category => 'MTYPE',
                authorised_value => $itemtype,
            }
            )->next;

            if ($authorised_value) {
            $record->{itemtype} = $authorised_value->opac_description;
            }
            else {
                $record->{itemtype} = $itemtype;
            }
        }

        my $item_rs = Koha::Old::Items->search(
            { biblionumber => $biblio->biblionumber },
            {
                order_by => { '-desc' => 'itemnumber' },
            }
        );

        my @items;

        while ( my $item = $item_rs->next ) {
            push @items, {
                itemnumber => $item->itemnumber,
                barcode    => $item->barcode,
                holdingbranch => $item->holdingbranch,
                homebranch => $item->homebranch,
                timestamp => $item->timestamp,
            };
        }

        $record->{items} = \@items;

        push @records, $record;
    }

    # Pass records to the template
    $template->param(
        records => \@records,
        op      => 'list',
    );
}

if ( $op eq 'cud-restore' ) {
    my @records = $input->multi_param('record_id');
    my @errors;
    my @restored_records;

    if (@records) {

        foreach my $record_id ( @records ) {
            try {
                # Restore the record
                restore($record_id);
                push @restored_records, $record_id;
            }
            catch {
                warn "Failed to restore biblio $record_id: $_";
                push @errors, $record_id;
            };

        }

        $template->param(
            restored_records => \@restored_records,
            errors => \@errors,
        );

    }
    else {
        $template->param(no_biblionumber => 1,);
    }
}

sub restore {
    my ($biblionumber, $itemnumber) = @_;
    my $dbh = C4::Context->dbh;

    my $query = "SELECT * FROM deletedbiblio_metadata WHERE biblionumber = ?";
    my $sth = $dbh->prepare($query);

    $sth->execute($biblionumber);

    my $deleted_record = $sth->fetchrow_hashref;

    die "Deleted record not found\n" unless $deleted_record;

    _restore_record($biblionumber);
    _reindex_record($biblionumber);
    _delete_from_deleted($biblionumber);
}

sub _restore_record {
    my ($biblionumber) = @_;

    my $dbh = C4::Context->dbh;

    $dbh->do("INSERT INTO biblio SELECT * FROM deletedbiblio WHERE biblionumber = ?", undef, $biblionumber);
    $dbh->do("INSERT INTO biblioitems SELECT * FROM deletedbiblioitems WHERE biblionumber = ?", undef, $biblionumber);
    $dbh->do("INSERT INTO biblio_metadata (biblionumber, format, `schema`, metadata, timestamp) SELECT biblionumber, format, `schema`, metadata, timestamp FROM deletedbiblio_metadata WHERE biblionumber = ?", undef, $biblionumber);

}

sub _reindex_record {
    my ($biblionumber) = @_;

    my $indexer = Koha::SearchEngine::Indexer->new({ index => $Koha::SearchEngine::BIBLIOS_INDEX });
    $indexer->index_records( $biblionumber, "specialUpdate", "biblioserver" );
}

sub _delete_from_deleted {
    my ($biblionumber) = @_;

    my $dbh = C4::Context->dbh;

    $dbh->do("DELETE FROM deletedbiblio WHERE biblionumber = ?", undef, $biblionumber);
    $dbh->do("DELETE FROM deletedbiblioitems WHERE biblionumber = ?", undef, $biblionumber);
    $dbh->do("DELETE FROM deletedbiblio_metadata WHERE biblionumber = ?", undef, $biblionumber);
}

# Output the template
output_html_with_http_headers $input, $cookie, $template->output;