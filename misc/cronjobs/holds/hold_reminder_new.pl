#!/usr/bin/perl

# Copyright 2025 Koha Community
#
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

=head1 NAME

hold_reminder_new.pl - prepare hold expiration reminder messages to be sent to patrons

=head1 SYNOPSIS

       hold_reminder_new.pl
         [ -n ][ -m <number of days> ][ -c ][ -v ]

=head1 DESCRIPTION

This script prepares hold expiration reminder messages to be sent to patrons
based on their messaging preferences. It queues them in the message queue,
which is processed by the process_message_queue.pl cronjob. The type and
timing of the messages can be configured by the patrons in their "My Alerts"
tab in the OPAC.

=cut

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );
use Koha::Script -cron;
use C4::Context;
use C4::Letters;
use C4::Members::Messaging;
use C4::Reserves;
use C4::Log qw( cronlogaction );
use Koha::Patrons;

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<-v>

Verbose. Without this flag set, only fatal errors are reported.

=item B<-n>

Do not send any email. Hold reminder notices that would have been sent to
the patrons are printed to standard out.

=item B<-m>

Defines the maximum number of days in advance to send hold reminder notices.

=item B<-c>

Confirm flag: Add this option. The script will only print a usage
statement otherwise.

=item B<--library>

select notices for one specific library. Use the value in the
branches.branchcode table. This option can be repeated in order
to select notices for a group of libraries.

=back

=head2 Configuration

This script pays attention to the hold reminder notice configuration
performed by borrowers in the OPAC, or by staff in the patron detail page of the intranet.
The content of the messages is configured in Tools -> Notices and slips, using the
HOLD_REMINDER letter template.

Hold reminders can be sent via email and/or SMS. Emails are sent only if the patron
has configured an email address and enabled email notifications. SMS messages are sent
only if the patron has configured a phone number and enabled SMS notifications. The patron
can set a "days in advance" preference for hold reminders via the "My Alerts" section in
the OPAC. More information about the use of this section of Koha is available in the
Koha manual.

=head2 Outgoing messages

Messages are staged in the outgoing message queue, as are messages produced by
other features of Koha. This message queue must be processed regularly by the
F<misc/cronjobs/process_message_queue.pl> program. This includes both email and
SMS messages.

In the event that the C<-n> flag is passed to this program, no messages are sent.
Instead, messages are sent on standard output from this program. They may be
redirected to a file if desired.

=head2 Templates

Templates can contain variables enclosed in double angle brackets like
<<this>>. Those variables will be replaced with values specific to the
patron and their expiring holds. Available variables are:

=over

=item E<lt>E<lt>borrowers.*E<gt>E<gt>

any field from the borrowers table

=item E<lt>E<lt>branches.*E<gt>E<gt>

any field from the branches table

=item E<lt>E<lt>reserves.*E<gt>E<gt>

any field from the reserves table

=back

=head1 SEE ALSO

The F<misc/cronjobs/advance_notices.pl> program allows you to send
messages to patrons with upcoming due items.

=cut

binmode( STDOUT, ':encoding(UTF-8)' );

# These are defaults for command line options.
my $confirm;                   # -c: Confirm that the user has read and configured this script.
my $nomail;                    # -n: No mail. Will not send any emails.
my $maxdays = 30;              # -m: Maximum number of days in advance to send notices
my $verbose = 0;               # -v: verbose
my @branchcodes;               # Branch(es) passed as parameter

my $help = 0;
my $man  = 0;

my $command_line_options = join( " ", @ARGV );
cronlogaction( { info => $command_line_options } );

GetOptions(
    'help|?'    => \$help,
    'man'       => \$man,
    'library=s' => \@branchcodes,
    'c'         => \$confirm,
    'n'         => \$nomail,
    'm:i'       => \$maxdays,
    'v'         => \$verbose,
) or pod2usage(2);
pod2usage(1)               if $help;
pod2usage( -verbose => 2 ) if $man;

# Since hold reminder options are not visible in the web-interface
# unless EnhancedMessagingPreferences is on, let the user know that
# this script probably isn't going to do much
if ( !C4::Context->preference('EnhancedMessagingPreferences') && $verbose ) {
    warn <<'END_WARN';

The "EnhancedMessagingPreferences" syspref is off.
Therefore, it is unlikely that this script will actually produce any messages to be sent.
To change this, edit the "EnhancedMessagingPreferences" syspref.

END_WARN
}
unless ($confirm) {
    pod2usage(1);
}

my %branches = ();
if (@branchcodes) {
    %branches = map { $_ => 1 } @branchcodes;
}

# Process hold expiration reminders
warn 'getting upcoming expiring holds' if $verbose;
my $upcoming_holds = C4::Reserves::GetUpcomingExpiringHolds(
    {
        days_in_advance => $maxdays,
    }
);
warn 'found ' . scalar(@$upcoming_holds) . ' upcoming expiring holds' if $verbose;

my $admin_adress = C4::Context->preference('KohaAdminEmailAddress');

# Group holds by borrowernumber and days_until_expiration for digest delivery
my %holds_by_patron_day = ();
foreach my $upcoming_hold (@$upcoming_holds) {
    my $key = $upcoming_hold->{'borrowernumber'} . '_' . $upcoming_hold->{'days_until_expiration'};
    push @{ $holds_by_patron_day{$key} }, $upcoming_hold;
}

my @letters;
HOLDGROUP: foreach my $key ( sort keys %holds_by_patron_day ) {
    my @group = @{ $holds_by_patron_day{$key} };
    @letters = ();

    my $first_hold      = $group[0];
    my $borrowernumber  = $first_hold->{'borrowernumber'};
    my $days_until      = $first_hold->{'days_until_expiration'};
    my $branchcode      = $first_hold->{'branchcode'};
    my $from_address    = $first_hold->{branchemail} || $admin_adress;

    warn 'examining digest for borrowernumber ' . $borrowernumber . ' with ' . scalar(@group) . ' holds expiring in ' . $days_until . ' days' if $verbose;

    my $borrower_preferences = C4::Members::Messaging::GetMessagingPreferences(
        {
            borrowernumber => $borrowernumber,
            message_name   => 'hold_reminder'
        }
    );

    # Check if patron has this notification enabled for the correct days
    my $patron_days = 0;
    if ( $borrower_preferences && exists $borrower_preferences->{days_in_advance} ) {
        $patron_days = $borrower_preferences->{days_in_advance};
    }

    # Only send if days match
    next HOLDGROUP if $patron_days != $days_until;

    # Skip this HOLD_REMINDER if we specify list of libraries and this one is not part of it
    next if ( @branchcodes && !$branches{$branchcode} );

    # Collect reserve IDs for the loop
    my @reserve_ids = map { $_->{'reserve_id'} } @group;

    # Send hold reminders via all configured transports
    foreach my $transport_type ( keys %{ $borrower_preferences->{'transports'} } ) {
        my $letter_type = 'HOLD_REMINDER';
        my $letter = parse_letter(
            {
                letter_code    => $letter_type,
                borrowernumber => $borrowernumber,
                branchcode     => $branchcode,
                loops          => {
                    reserves => \@reserve_ids,
                },
                message_transport_type => $transport_type,
            }
        )
        or warn "no letter of type '$letter_type' found for borrowernumber "
        . $borrowernumber
        . ". Please see sample_notices.sql";
        if ($letter) {
            push @letters, $letter;
            warn 'successfully created digest letter for borrowernumber ' . $borrowernumber . ' via ' . $transport_type . ' with ' . scalar(@group) . ' holds expiring in ' . $days_until . ' days' if $verbose;
        }
    }

    # If we have prepared a letter, send it.
    if (@letters) {
        if ($nomail) {
            for my $letter (@letters) {
                local $, = "\f";
                print $letter->{'content'} . "\n";
            }
        } else {
            for my $letter (@letters) {
                C4::Letters::EnqueueLetter(
                    {
                        letter                 => $letter,
                        borrowernumber         => $borrowernumber,
                        from_address           => $from_address,
                        message_transport_type => $letter->{message_transport_type}
                    }
                );
                warn 'enqueued hold reminder digest for borrowernumber ' . $borrowernumber . ' via ' . $letter->{message_transport_type} . ' for ' . scalar(@group) . ' holds (patron selected ' . $borrower_preferences->{'days_in_advance'} . ' days in advance)' if $verbose;
            }
        }
    }
}

cronlogaction( { action => 'End', info => "COMPLETED" } );

=head1 METHODS

=head2 parse_letter

=cut

sub parse_letter {
    my $params = shift;

    foreach my $required (qw( letter_code borrowernumber )) {
        return unless exists $params->{$required};
    }
    my $patron = Koha::Patrons->find( $params->{borrowernumber} );

    my %table_params = ( 'borrowers' => $params->{'borrowernumber'} );

    if ( my $p = $params->{'branchcode'} ) {
        $table_params{'branches'} = $p;
    }
    if ( my $p = $params->{'biblionumber'} ) {
        $table_params{'biblio'}      = $p;
        $table_params{'biblioitems'} = $p;
    }

    return C4::Letters::GetPreparedLetter(
        module      => 'reserves',
        letter_code => $params->{'letter_code'},
        branchcode  => $table_params{'branches'},
        lang        => $patron->lang,
        substitute  => $params->{'substitute'},
        tables      => \%table_params,
        loops       => $params->{'loops'},
        message_transport_type => $params->{message_transport_type},
    );
}

1;

__END__
