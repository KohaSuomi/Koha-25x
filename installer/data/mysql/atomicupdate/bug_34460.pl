use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "34460",
    description => "Add 'can_have_permissions' column to 'categories' table",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( column_exists( 'categories', 'can_have_permissions' ) ) {
            $dbh->do(
                q{
                ALTER TABLE categories
                ADD COLUMN can_have_permissions tinyint(1) NOT NULL DEFAULT 0
            }
            );

            say_success( $out, "Added 'can_have_permissions' column to 'categories' table" );
        }

        $dbh->do(
            q{
            UPDATE categories
            SET can_have_permissions = 1
            WHERE category_type = 'S'
        }
        );

        say_info( $out, "Set 'can_have_permissions' to 1 for categories with category_type 'S'" );

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value) VALUES ('ClearPermissionsAutomatically', '0')
        }
        );

        say_success( $out, "Added 'ClearPermissionsAutomatically' system preference" );
    },
};
