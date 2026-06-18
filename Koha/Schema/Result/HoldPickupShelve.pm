use utf8;
package Koha::Schema::Result::HoldPickupShelve;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::HoldPickupShelve

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<hold_pickup_shelves>

=cut

__PACKAGE__->table("hold_pickup_shelves");

=head1 ACCESSORS

=head2 hold_pickup_shelf_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 library_id

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 10

=head2 patron_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 shelf_name

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 max_items

  data_type: 'integer'
  is_nullable: 0

=head2 overflow_shelf

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 1

=head2 locked

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 1

=head2 locked_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 biblio_itemtype

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=head2 patron_category_id

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 1
  size: 10

=head2 weekday

  data_type: 'enum'
  extra: {list => ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]}
  is_nullable: 1

=head2 priority

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 last_used_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 allow_multiple

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "hold_pickup_shelf_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "library_id",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 10 },
  "patron_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "shelf_name",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "max_items",
  { data_type => "integer", is_nullable => 0 },
  "overflow_shelf",
  { data_type => "tinyint", default_value => 0, is_nullable => 1 },
  "locked",
  { data_type => "tinyint", default_value => 0, is_nullable => 1 },
  "locked_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "biblio_itemtype",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "patron_category_id",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 1, size => 10 },
  "weekday",
  {
    data_type => "enum",
    extra => {
      list => [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ],
    },
    is_nullable => 1,
  },
  "priority",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "last_used_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "allow_multiple",
  { data_type => "tinyint", default_value => 0, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</hold_pickup_shelf_id>

=back

=cut

__PACKAGE__->set_primary_key("hold_pickup_shelf_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<hold_pickup_shelves_uniq_idx>

=over 4

=item * L</library_id>

=item * L</shelf_name>

=item * L</biblio_itemtype>

=item * L</patron_category_id>

=item * L</weekday>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "hold_pickup_shelves_uniq_idx",
  [
    "library_id",
    "shelf_name",
    "biblio_itemtype",
    "patron_category_id",
    "weekday",
  ],
);

=head1 RELATIONS

=head2 library

Type: belongs_to

Related object: L<Koha::Schema::Result::Branch>

=cut

__PACKAGE__->belongs_to(
  "library",
  "Koha::Schema::Result::Branch",
  { branchcode => "library_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "RESTRICT" },
);

=head2 old_reserves

Type: has_many

Related object: L<Koha::Schema::Result::OldReserve>

=cut

__PACKAGE__->has_many(
  "old_reserves",
  "Koha::Schema::Result::OldReserve",
  { "foreign.hold_pickup_shelf_id" => "self.hold_pickup_shelf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 patron

Type: belongs_to

Related object: L<Koha::Schema::Result::Borrower>

=cut

__PACKAGE__->belongs_to(
  "patron",
  "Koha::Schema::Result::Borrower",
  { borrowernumber => "patron_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "RESTRICT",
  },
);

=head2 patron_category

Type: belongs_to

Related object: L<Koha::Schema::Result::Category>

=cut

__PACKAGE__->belongs_to(
  "patron_category",
  "Koha::Schema::Result::Category",
  { categorycode => "patron_category_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "RESTRICT",
  },
);

=head2 reserves

Type: has_many

Related object: L<Koha::Schema::Result::Reserve>

=cut

__PACKAGE__->has_many(
  "reserves",
  "Koha::Schema::Result::Reserve",
  { "foreign.hold_pickup_shelf_id" => "self.hold_pickup_shelf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2026-06-18 09:30:33
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:477oszdWI0HqRXxkhtpAcA

sub koha_object_class {
    'Koha::HoldPickupShelf';
}
sub koha_objects_class {
    'Koha::HoldPickupShelves';
}

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
