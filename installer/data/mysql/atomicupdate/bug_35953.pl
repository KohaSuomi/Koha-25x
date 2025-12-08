use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "35953",
    description => "Add new permission delete_bibliographic_records",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{INSERT IGNORE INTO permissions (module_bit, code, description) VALUES (9, 'delete_bibliographic_records', 'Delete bibliographic records from catalogue')}
        );

        say $out "Added new permission delete_bibliographic_records";

        $dbh->do(
            q{INSERT IGNORE INTO user_permissions (borrowernumber, module_bit, code) SELECT  borrowernumber, module_bit, 'delete_bibliographic_records' FROM user_permissions where module_bit = 9 and code = 'edit_catalogue';}
        );
        say $out "Add new permission delete_bibliographic_records for patrons with edit_catalogue permission";
    },
};
