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
use C4::Biblio;
use Koha::Items;

my $input            = CGI->new;
my $op               = $input->param('op') // q|form|;
my $deleted_from = $input->param('deleted_from') // '';
my $deleted_to = $input->param('deleted_to') // '';

if ( $input->param('biblionumbers')) {
    $op = 'cud-restore-items-for-biblio';
}

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => 'tools/restore_items.tt',
        query         => $input,
        type          => "intranet",
        flagsrequired => { tools => 'edit_catalogue' },
    }
);

if ( $op eq 'form' ) {

    $template->param(
        op           => 'form',
        deleted_from => $deleted_from,
        deleted_to => $deleted_to,
    );
}

if ( $op eq 'cud-list' ) {

    $deleted_from = $input->param('deleted_from') // '';
    $deleted_to = $input->param('deleted_to') . " 23:59:59" // '';

    my $dbh = C4::Context->dbh;
    my $query = "SELECT b.biblionumber, di.itemnumber, b.title, b.subtitle, b.part_name, b.part_number, b.author, di.barcode, di.itemnotes, di.enumchron, di.copynumber, di.holdingbranch, di.homebranch, di.deleted_on FROM deleteditems di
inner join biblio b on di.biblionumber = b.biblionumber
inner join biblioitems bi on di.biblionumber = bi.biblionumber
where di.biblionumber in (select biblionumber from biblio)
and date(di.timestamp) between ? and ?
order by deleted_on desc";
    my $sth = $dbh->prepare($query);
    $sth->execute($deleted_from, $deleted_to);
    my $deleted_items = $sth->fetchall_arrayref({});
    my $deleted_item_count = scalar @$deleted_items;
    warn "deleted_item_count: $deleted_item_count";
    $template->param(
        deleted_item_count => $deleted_item_count,
    );

    my @records;
    foreach my $item ( @$deleted_items ) {
        push @records, {
            biblionumber => $item->{biblionumber},
            itemnumber   => $item->{itemnumber},
            deleted_on   => $item->{deleted_on},
            title        => $item->{title},
            subtitle        => $item->{subtitle},
            part_name    => $item->{part_name},
            part_number  => $item->{part_number},
            author       => $item->{author},
            barcode      => $item->{barcode},
            holdingbranch => $item->{holdingbranch},
            homebranch   => $item->{homebranch},
            enumchron    => $item->{enumchron},
            copynumber    => $item->{copynumber},
            itemnotes    => $item->{itemnotes},
        };
    }



    # Pass records to the template
    $template->param(
        records => \@records,
        op      => 'cud-list',
    );

}

if ( $op eq 'cud-restore-items-for-biblio' ) {

    my @biblionumbers = split ',', $input->param('biblionumbers');
    my $biblionumbers_str = join(',', @biblionumbers);

    my $dbh = C4::Context->dbh;
    my $query = "SELECT b.biblionumber, di.itemnumber, b.title, b.subtitle, b.part_name, b.part_number, b.author, di.barcode, di.itemnotes, di.itype, di.enumchron, di.copynumber, di.holdingbranch, di.homebranch, di.deleted_on FROM deleteditems di
inner join biblio b on di.biblionumber = b.biblionumber
inner join biblioitems bi on di.biblionumber = bi.biblionumber
where di.biblionumber in (select biblionumber from biblio)
and di.biblionumber in" . " ($biblionumbers_str) " . "
order by deleted_on desc";
    my $sth = $dbh->prepare($query);

    warn "Executing query: $query";
    $sth->execute();
    my $deleted_items = $sth->fetchall_arrayref({});
    my $deleted_item_count = scalar @$deleted_items;
    warn "deleted_item_count: $deleted_item_count";
    $template->param(
        deleted_item_count => $deleted_item_count,
    );

    my @records;
    foreach my $item ( @$deleted_items ) {
        push @records, {
            biblionumber => $item->{biblionumber},
            itemnumber   => $item->{itemnumber},
            deleted_on   => $item->{deleted_on},
            title        => $item->{title},
            subtitle        => $item->{subtitle},
            part_name    => $item->{part_name},
            part_number  => $item->{part_number},
            author       => $item->{author},
            barcode      => $item->{barcode},
            holdingbranch => $item->{holdingbranch},
            homebranch   => $item->{homebranch},
            enumchron    => $item->{enumchron},
            copynumber    => $item->{copynumber},
            itemnotes    => $item->{itemnotes},
            itemtype    => $item->{itype},
        };
    }

    # Pass records to the template
    $template->param(
        records => \@records,
        op      => 'cud-list',
    );

}

if ( $op eq 'cud-restore' ) {
    my @records = $input->multi_param('record_id');
    my @errors;
    my @restored_records;

    if (@records) {
        foreach my $record (@records) {
            my ($biblionumber, $itemnumber) = split(/\,/, $record);
            try {
                # Restore the record
                restore($biblionumber, $itemnumber);
                push @restored_records, { itemnumber => $itemnumber, biblionumber => $biblionumber };
            }
            catch {
                warn "Failed to restore item $itemnumber (biblionumber $biblionumber): $_";
                push @errors, { itemnumber => $itemnumber, biblionumber => $biblionumber };
            };
        }

        $template->param(
            restored_records => \@restored_records,
            errors => \@errors,
            view => 'report',
        );

    }
    else {
        $template->param(no_itemnumber => 1,);
    }
}

sub restore {

    my ($biblionumber, $itemnumber) = @_;
    my $dbh = C4::Context->dbh;

    my $query = "SELECT * FROM biblio WHERE biblionumber = ?";
    my $sth = $dbh->prepare($query);

    $sth->execute($biblionumber);

    my $record = $sth->fetchrow_hashref;

    die "Item's Biblio record not found\n" unless $record;

    _restore_item($itemnumber);

    #reindex item by calling ->store;
    my $item = Koha::Items->find($itemnumber);
    $item->store;

    _reindex_record($biblionumber);
    _delete_from_deleted($itemnumber);
}

sub _restore_item {
    my ($itemnumber) = @_;

    my $dbh = C4::Context->dbh;

    $dbh->do("INSERT INTO items SELECT * FROM deleteditems WHERE itemnumber = ?", undef, $itemnumber);
    $dbh->do("UPDATE items SET deleted_on = NULL WHERE itemnumber = ?", undef, $itemnumber);
}

sub _reindex_record {
    my ($biblionumber) = @_;

    my $indexer = Koha::SearchEngine::Indexer->new({ index => $Koha::SearchEngine::BIBLIOS_INDEX });
    $indexer->index_records( $biblionumber, "specialUpdate", "biblioserver" );
}

sub _delete_from_deleted {
    my ($itemnumber) = @_;

    my $dbh = C4::Context->dbh;
    $dbh->do("DELETE FROM deleteditems WHERE itemnumber = ?", undef, $itemnumber);
}


# Output the template
output_html_with_http_headers $input, $cookie, $template->output;