#!/usr/bin/perl

# Copyright 2000-2002 Katipo Communications
# Copyright 2016-2022 Koha-Suomi Oy
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

use Modern::Perl;

use C4::Context;
use C4::Output qw( output_html_with_http_headers );
use CGI qw ( -utf8 );
use C4::Auth qw( get_template_and_user );
use File::stat;
use Time::localtime;
use Time::Piece;
use Storable;

use File::Basename;
use C4::Context;

my $title = 'VARAUSRYHMA';

my @reservegroup_ids;
my @reserve_groups = Koha::Library::Groups->search({title => {-like => "VARAUSRYHMA%"}})->as_list;

foreach my $reserve_group (@reserve_groups){
    my $id = $reserve_group->id;
    push( @reservegroup_ids, $id);
}

my $dbh = C4::Context->dbh();
my $sth;

my @branches;

foreach my $id (@reservegroup_ids){

    $sth = $dbh->prepare(
        q{
            select parent_id, branchcode from library_groups where parent_id = ?
        }
    );

    $sth->execute($id) or die $dbh->errstr;

    my @branchesref = @{$sth->fetchall_arrayref({})};
    #https://www.perlmonks.org/?node_id=334186
    push (@branches, \@branchesref);

    $sth->finish;
}

my $input = new CGI;

my $theme = $input->param('theme');    # only used if allowthemeoverride is set

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "circ/kohasuomi-pendingreserves.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => "circulate_remaining_permissions" },
        debug           => 1,
    }
);

my $reporteddate = localtime->datetime();
$reporteddate=~s/T/ /;
my @reservedata;

if ( -e '/tmp/kohasuomi-pendingreserves.tmp' ) {
    my $stored=retrieve('/tmp/kohasuomi-pendingreserves.tmp');
	$reporteddate = Time::Piece->strptime(ctime(stat('/tmp/kohasuomi-pendingreserves.tmp')->mtime), '%a %b %d %H:%M:%S %Y')->strftime('%Y-%m-%d %H:%M:%S');
    @reservedata=@{$stored};
}

# Apply highlighting to holding branches based on matching and reserve groups
apply_highlighting(\@reservedata, \@branches);

$template->param(
    reporteddate        => $reporteddate,
    reserveloop         => \@reservedata,
    has_reserve_groups  => scalar(@branches) > 0,
    "BiblioDefaultView".C4::Context->preference("BiblioDefaultView") => 1,
);

output_html_with_http_headers $input, $cookie, $template->output;

# Subroutine to apply highlighting to holding branches
sub apply_highlighting {
    my ($reservedata, $branches) = @_;
    
    return unless $reservedata && ref($reservedata) eq 'ARRAY';
    return unless $branches && ref($branches) eq 'ARRAY';
    
    # Build reserve groups lookup hash: branchcode => [list of all branches in its group]
    my %reserve_groups_lookup;
    foreach my $group (@$branches) {
        next unless ref($group) eq 'ARRAY' && scalar(@$group) > 0;
        
        # Extract all branch codes in this group
        my @group_branches = ();
        foreach my $member (@$group) {
            if (ref($member) eq 'HASH' && $member->{branchcode}) {
                push @group_branches, $member->{branchcode};
            }
        }
        
        # Map each branch in the group to the full group
        foreach my $branchcode (@group_branches) {
            $reserve_groups_lookup{$branchcode} = \@group_branches;
        }
    }
    
    foreach my $reserve (@$reservedata) {
        next unless $reserve->{holdingbranches} && ref($reserve->{holdingbranches}) eq 'ARRAY';
        
        my $to_branch = $reserve->{branch};
        
        # Process each holding branch
        foreach my $i (0..$#{$reserve->{holdingbranches}}) {
            my $holding_branch = $reserve->{holdingbranches}->[$i];
            
            # Skip if already a complex object
            next if ref($holding_branch) eq 'HASH';
            
            my %branch_data = (
                code => $holding_branch,
                highlight_orange => 0,
                highlight_bold => 0,
            );
            
            # Check if holding branch matches to branch (orange + bold)
            if (defined $to_branch && $holding_branch eq $to_branch) {
                $branch_data{highlight_orange} = 1;
                $branch_data{highlight_bold} = 1;
            }
            
            # Check if holding branch is in same reserve group as to branch (bold)
            if (defined $to_branch && exists $reserve_groups_lookup{$to_branch}) {
                my $group_branches = $reserve_groups_lookup{$to_branch};
                if (grep { $_ eq $holding_branch } @$group_branches) {
                    $branch_data{highlight_bold} = 1;
                }
            }
            
            $reserve->{holdingbranches}->[$i] = \%branch_data;
        }
    }
}
