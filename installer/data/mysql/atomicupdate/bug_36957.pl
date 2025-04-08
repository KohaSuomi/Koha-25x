use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "36957",
    description =>
        "Add CancelTransitWhenItemFloats system preference and 'ItemArrivedToFloatBranch' to branchtransfers.cancellation_reason enum",
    up => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{INSERT IGNORE INTO systempreferences (variable,value,options,explanation,type) VALUES ('CancelTransitWhenItemFloats','0',NULL,'Cancels items transit automatically if it arrives to a branch where it can float','YesNo')}
        );

        say_success( $out, "Added system preference 'CancelTransitWhenItemFloats'" );

        $dbh->do(
            q{
                alter table
                    `branchtransfers`
                modify column
                    `cancellation_reason` enum(
                        'Manual',
                        'StockrotationAdvance',
                        'StockrotationRepatriation',
                        'ReturnToHome',
                        'ReturnToHolding',
                        'RotatingCollection',
                        'Reserve',
                        'LostReserve',
                        'CancelReserve',
                        'ItemLost',
                        'WrongTransfer',
                        'ItemArrivedToFloatBranch'
                    ) DEFAULT NULL
                after `reason`
              }
        );

        say_success( $out, "Added 'ItemArrivedToFloatBranch' to branchtransfers.cancellation_reason enum" );
    },
};
