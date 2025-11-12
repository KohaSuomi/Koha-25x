use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "41240",
    description => "Add LocalHoldsPriorityFulfillmentSkips syspref and reserves.fulfillment_skips column",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Do you stuffs here
        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable,value,explanation,options,type) VALUES ('LocalHoldsPriorityFulfillmentSkips', '0', 'Maximum number of times LocalHoldsPriority can skip a hold for fulfillment. Set to 0 for no limit.', '', 'integer');
        });

        # sysprefs
        say $out "Added new system preference 'LocalHoldsPriorityFulfillmentSkips'";
        if ( !column_exists( 'reserves', 'fulfillment_skips' ) ) {
            $dbh->do(q{
                ALTER TABLE reserves ADD COLUMN fulfillment_skips INT(11) DEFAULT 0 COMMENT 'Number of times this hold has been skipped for fulfillment by LocalHoldsPriority';
            });

            say $out "Added column 'reserves.fulfillment_skips'";
        }

        if ( !column_exists( 'old_reserves', 'fulfillment_skips' ) ) {
            $dbh->do(q{
                ALTER TABLE old_reserves ADD COLUMN fulfillment_skips INT(11) DEFAULT 0 COMMENT 'Number of times this hold has been skipped for fulfillment by LocalHoldsPriority';
            });

            say $out "Added column 'old_reserves.fulfillment_skips'";
        }
    },
};
