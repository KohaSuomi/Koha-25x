package C4::KohaSuomi::SFTP;

# Copyright 2025 Koha-Suomi Oy
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Selects can be run on alt_host (database slave) if configured.

use strict;
use warnings;

use File::Copy;
use Net::SFTP::Foreign;

sub sftp_transfer {

    my ( $files, $config, $tmppath, $archivepath, $message_ids ) = @_;

    my @messages_array;
    my $success = 1;
    my $error = "";

    # Connect and send with SFTP
    my $sftp = Net::SFTP::Foreign->new('host' => $config->{host},
                                       'port' => $config->{port} || '22',
                                       'user' => $config->{user},
                                       'password' => $config->{password});

    if ( $sftp->error ) {
        die "Logging in to SFTP server failed with: ".$sftp->error."\n";
    }

    foreach my $file ( @$files ) {
        my $file_type = substr $file, -4;
        my ($library, $message_id) = split(/(\d+)/, $file) unless $file_type eq ".zip";

        unless ( $sftp->put($tmppath.$file, $config->{remotedir}.$file.'.part', copy_perms => 0, copy_time => 0)) {
            $success = 0;
            $error = $sftp->error;
            print "Transferring file to SFTP server failed with: ".$sftp->error."\n";
        }

        unless ( $sftp->rename($config->{remotedir}.$file.'.part', $config->{remotedir}.$file)) {
            $success = 0;
            $error = $sftp->error;
            print "Renaming a file on SFTP server failed with: ".$sftp->error."\n";
        }

        if ( $archivepath ){
            move ("$tmppath$file", "$archivepath") or die "The move operation failed: $!";
        }

        unless( $file_type eq ".zip" ){
            my $message_hash = {
                message_id => $message_id,
                success => $success,
                error => $error
            };
            push @messages_array, $message_hash;
        }
    }

    if ( $message_ids ){
        foreach my $message_id ( @$message_ids ){
            my $message_hash = {
                message_id => $message_id,
                success => $success,
                error => $error
            };
            push @messages_array, $message_hash;
        }
    }

    return $success, \@messages_array;
}

1;