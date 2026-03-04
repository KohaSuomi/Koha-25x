use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "HOLD_REMINDER_DAYS",
    description => "Enable days in advance selection for Hold Reminder notifications",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Update the Hold_Reminder message attribute to support takes_days
        $dbh->do(q{
            UPDATE message_attributes
            SET takes_days = 1
            WHERE message_name = 'Hold_Reminder'
        });

        say $out "Updated message attribute 'Hold_Reminder' to support days in advance selection";
        say_success( $out, "Hold reminder notifications can now be configured with days in advance preference" );
    },
};
