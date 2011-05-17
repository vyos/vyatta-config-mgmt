#
# Module: ConfigMgmt.pm
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2009 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2010
# Description: Common config-mgmt functions
# 
# **** End License ****
#
package Vyatta::ConfigMgmt;

use strict;
use warnings;

our @EXPORT = qw(cm_commit_add_log cm_commit_get_log cm_get_archive_dir 
                 cm_get_lr_conf_file cm_get_lr_state_file 
                 cm_get_commit_hook_dir cm_write_file cm_read_file
                 cm_commit_get_file cm_commit_get_file_name
                 cm_get_max_revs cm_get_num_revs cm_get_last_commit_file 
                 cm_get_last_push_file cm_get_boot_config_file
                 cm_get_config_rb cm_get_config_dir
                );
use base qw(Exporter);

use Vyatta::Config;
use Vyatta::Interface;
use Vyatta::Misc;
use POSIX;
use IO::Zlib;


my $commit_hook_dir  = `cli-shell-api getPostCommitHookDir`;
my $config_dir       = '/opt/vyatta/etc/config';
my $archive_dir      = "$config_dir/archive";
my $config_file      = "$config_dir/config.boot";
my $lr_conf_file     = "$archive_dir/lr.conf";
my $lr_state_file    = "$archive_dir/lr.state";
my $commit_log_file  = "$archive_dir/commits";
my $last_commit_file = "$archive_dir/config.boot";
my $last_push_file   = "$archive_dir/config.boot-push";
my $config_file_rb   = "$archive_dir/config.boot-rollback";

sub cm_get_boot_config_file {
    return $config_file;
}

sub cm_get_config_rb {
    return $config_file_rb;
}

sub cm_get_commit_hook_dir {
    return "$commit_hook_dir/";
}

sub cm_get_archive_dir {
    return $archive_dir;
}

sub cm_get_config_dir {
    return $config_dir;
}

sub cm_get_lr_conf_file {
    return $lr_conf_file;
}

sub cm_get_lr_state_file {
    return $lr_state_file;
}

sub cm_get_last_commit_file {
    return $last_commit_file;
}

sub cm_get_last_push_file {
    return $last_push_file;
}

sub cm_read_file {
    my ($file) = @_;
    my @lines;
    if ( -e $file) {
	open(my $FILE, '<', $file) or die "Error: read $!";
	@lines = <$FILE>;
	close($FILE);
	chomp @lines;
    }
    return @lines;
}

sub cm_write_file {
    my ($file, $data) = @_;

    open(my $fh, '>', $file) || die "Couldn't open $file - $!";
    print $fh $data;
    close $fh;
    return 1;
}

sub cm_get_max_revs {
    my $config = new Vyatta::Config;
    $config->setLevel('system config-management');
    my $revs = $config->returnOrigValue('commit-revisions');
    return $revs;
}

sub cm_get_num_revs {
    return -1 if ! -e $commit_log_file;
    my @lines = cm_read_file($commit_log_file);
    my $num_revs = scalar(@lines);
    $num_revs-- if $num_revs > 0;  # rev files start at 0
    return $num_revs;
}

sub cm_commit_add_log {
    my ($user, $via, $comment) = @_;

    my $time = time();
    if ($comment =~ /\|/) {
        $comment =~ s/\|/\%\%/g;
    }
    my $new_line = "|$time|$user|$via|$comment|";
    my @lines = cm_read_file($commit_log_file);

    my $revs = cm_get_max_revs();
    unshift(@lines, $new_line);   # head push()
    if (defined $revs and scalar(@lines) > $revs) {
        $#lines = $revs-1;
    }
    my $log = join("\n", @lines);
    cm_write_file($commit_log_file, $log);
}

sub cm_commit_get_log {
    my ($brief) = @_;
    
    my @lines = cm_read_file($commit_log_file);
    
    my @commit_log = ();
    my $count = 0;
    foreach my $line (@lines) {
        if ($line !~ /^\|(.*)\|$/) {
            print "Invalid log format [$line]\n";
            next;
        }
        $line = $1;
        my ($time, $user, $via, $comment) = split(/\|/, $line);
        $comment =~ s/\%\%/\|/g;
        if (defined $brief) {
            my $time_str = strftime("%Y-%m-%d_%H:%M:%S", localtime($time));
            $comment = '' if ! defined $comment;
            my $new_line = sprintf("%s %s by %s", $time_str, $user, $via);
            push @commit_log, $new_line;
        } else {
            my $time_str = strftime("%Y-%m-%d %H:%M:%S", localtime($time));
            my $new_line = sprintf("%-2s  %s by %s via %s\n", 
                                   $count, $time_str, $user, $via);
            push @commit_log, $new_line;
            if (defined $comment and $comment ne '' and $comment ne 'commit') {
                push @commit_log, "    $comment\n" 
            }
        }
        $count++;
    }
    return @commit_log;
}

sub cm_commit_get_file_name {
    my ($revnum) = @_;

    my $filename = $archive_dir . "/config.boot." . $revnum . ".gz";
    return $filename;
}

sub cm_commit_get_file {
    my ($revnum) = @_;

    my $max_revs = cm_get_max_revs();
    if (defined $max_revs and $revnum > $max_revs) {
        print "Error: Invalid config revision number\n";
        exit 1;
    }

    my $filename = cm_commit_get_file_name($revnum);
    die "File [$filename] not found." if ! -e $filename;

    my $fh = new IO::Zlib;
    $fh->open($filename, "rb") or die "Error: read $!";
    my @lines = <$fh>;
    $fh->close;
    return join('', @lines);
}

1;
