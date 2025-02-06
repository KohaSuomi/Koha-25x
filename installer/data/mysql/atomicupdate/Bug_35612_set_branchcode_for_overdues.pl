use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_failure say_success say_info);

return {
    bug_number  => "35612",
    description => "Add syspref OverdueFineBranch",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(q{INSERT IGNORE INTO systempreferences (variable,value,options,explanation,type) VALUES ('OverdueFineBranch', 'NoLibrary','NoLibrary|PatronLibrary|ItemHomeLibrary|IssuingLibrary', "Configure OVERDUE fine's recorded branchcode", 'choice');});

        say $out "Added new system preference 'OverdueFineBranch'";
    },
};
