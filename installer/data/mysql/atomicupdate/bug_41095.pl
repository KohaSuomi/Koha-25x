use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "41095",
    description => "Allow to limit LocalHoldsPriority filling to a maximum number of holds in the queue",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Do you stuffs here
        $dbh->do(q{
        INSERT IGNORE INTO systempreferences (variable,value,explanation,options,type) VALUES ('LocalHoldsPriorityMaxHolds', '0', 'Maximum number of holds to consider when calculating LocalHoldsPriority. Set to 0 for no limit.', '', 'integer');
        });

        # sysprefs
        say $out "Added new system preference 'LocalHoldsPriorityMaxHolds'";

    },
};
