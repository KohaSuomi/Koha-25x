package Koha::BiblioFramework;

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

use Koha::Database;
use C4::Biblio qw( GetMarcFromKohaField GetMarcStructure IsMarcStructureInternal );

use base qw(Koha::Object);

=head1 NAME

Koha::BiblioFramework - Koha BiblioFramework Object class

=head1 API

=head2 Class Methods

=cut

=head2 fill_with_default_values

Fill the given MARC record with default values from the framework. If the
optional parameter C<only_mandatory> is set to a true value, only the mandatory
fields/subfields will be filled.

    $framework->fill_with_default_values( $record, { only_mandatory => 1 } );

Where C<$framework> is a L<Koha::BiblioFramework> object and C<$record> is a
L<MARC::Record> object.

=cut

sub fill_with_default_values {
    my ( $self, $record, $params ) = @_;
    return unless $record;
    my $tagslib   = C4::Biblio::GetMarcStructure( 1, $self->frameworkcode, { unsafe => 1 } );
    my $mandatory = $params->{only_mandatory};
    if ($tagslib) {
        my ($itemfield) = C4::Biblio::GetMarcFromKohaField('items.itemnumber');
        for my $tag ( sort keys %$tagslib ) {
            next unless $tag;
            next if $tag == $itemfield;
            for my $subfield ( sort keys %{ $tagslib->{$tag} } ) {
                next if C4::Biblio::IsMarcStructureInternal( $tagslib->{$tag}{$subfield} );
                next if $mandatory && !$tagslib->{$tag}{$subfield}{mandatory};
                my $defaultvalue = $tagslib->{$tag}{$subfield}{defaultvalue};
                if ( defined $defaultvalue and $defaultvalue ne '' ) {
                    my @fields = $record->field($tag);
                    if (@fields) {
                        for my $field (@fields) {
                            if ( $field->is_control_field ) {
                                $field->update($defaultvalue) if not defined $field->data;
                            } elsif ( not defined $field->subfield($subfield) ) {
                                $field->add_subfields( $subfield => $defaultvalue );
                            }
                        }
                    } else {
                        if ( $tag < 10 ) {    # is_control_field
                            $record->insert_fields_ordered( MARC::Field->new( $tag, $defaultvalue ) );
                        } else {
                            $record->insert_fields_ordered(
                                MARC::Field->new( $tag, '', '', $subfield => $defaultvalue ) );
                        }
                    }
                }
            }
        }
    }
}

=head3 type

=cut

sub _type {
    return 'BiblioFramework';
}

1;
