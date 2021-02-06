#!/usr/bin/perl
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
# A copy of the GNU General Public License is available as
# `/usr/share/common-licenses/GPL' in the Debian GNU/Linux distribution
# or on the World Wide Web at `http://www.gnu.org/copyleft/gpl.html'.
# You can also obtain it by writing to the Free Software Foundation,
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stig Thormodsrud
# Date: October 2010
# Description: Script for config management features.
#
# **** End License ****
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5/';

use Vyatta::Config;
use Vyatta::ConfigMgmt;
use Getopt::Long;
use File::Basename;
use File::Copy;
use URI;
use IO::Prompt;
use Sys::Syslog qw(:standard :macros);

my $commit_uri_script  = '/opt/vyatta/sbin/vyatta-commit-push.pl';
my $commit_revs_script = '/opt/vyatta/sbin/vyatta-commit-revs.pl';

my $commit_hook_dir  = cm_get_commit_hook_dir();
my $archive_dir      = cm_get_archive_dir();
my $config_file      = "$archive_dir/config.boot";
my $lr_conf_file     = cm_get_lr_conf_file();

my $job_name = "commit-confirm";

my $debug = 0;

sub get_link {
    my ($path) = @_;

    my $script = basename($path);
    if ($script =~ /revs/) {
        $script = "01" . $script;
    } elsif ($script =~ /push/) {
        $script = "02" . $script;
    }
    my $link = $commit_hook_dir . $script; 
    return $link;
}

sub check_integer {
    my ($num) = @_;

    if ($num !~ /^\d+$/) {
        print "Invalid number [$num]\n";
        exit 1;
    }
    return 1;
}

sub check_valid_rev {
    my ($rev) = @_;

    check_integer($rev);
    my $num_revs = cm_get_num_revs();
    return 1 if $rev <= $num_revs;
    print "Invalid revision [$rev]\n";
    exit 1;
}

sub filter_file_lines {
    my ($diff) = @_;

    my @lines = split("\n", $diff);
    my $line1 = shift @lines;
    my $line2 = shift @lines;
    unshift(@lines, $line2) if $line2 !~ /^\+\+\+ /;
    unshift(@lines, $line1) if $line1 !~ /^\-\-\- /;
    return join("\n", @lines);
}

sub filter_version_string {
    my ($diff) = @_;

    # find last diff hunk, skip it if it's the version string
    my @lines = split("\n", $diff);
    my @last_hunk = ();
    my $found = 0;
    while (my $line = pop(@lines)) {
        unshift(@last_hunk, $line);
        $found = 1 if $line =~ /vyatta-config-version/;
        last if $line =~ /^@@/;
    }
    return join("\n", @lines) if $found;
    push(@lines, @last_hunk);
    return join("\n", @lines);
}


#
# main
#
my ($action, $uri, $revs, $revnum, $minutes, $filename);

Getopt::Long::Configure('pass_through');
GetOptions("action=s"      => \$action,
           "uri=s"         => \$uri,
           "revs=s"        => \$revs,
           "revnum=s"      => \$revnum,
           "minutes=s"     => \$minutes,
           "file=s"        => \$filename,
);

die "Error: no action"      if ! defined $action;

my ($cmd, $rc) = ('', 1);

if ($action eq 'update-uri') {
    print "update-uri\n" if $debug;
    my $config = new Vyatta::Config;
    $config->setLevel('system config-management commit-archive');
    my @uris = $config->returnValues('location');
    my $link = get_link($commit_uri_script);
    if (scalar(@uris) > 0 and ! -e $link) {
        print "add link [$link]\n" if $debug;
        $rc = system("ln -s $commit_uri_script $link");
        exit $rc;
    } elsif (scalar(@uris) < 1 and -e $link) {
        print "remove link [$link]\n" if $debug;
        $rc = system("rm -f $link");
        exit $rc;
    }
    exit 0;
}

if ($action eq 'valid-uri') {
    die "Error: no uri" if ! defined $uri;
    print "valid-uri [$uri]\n" if $debug;
    my $u = URI->new($uri);
    exit 1 if ! defined $u;
    my $scheme = $u->scheme();
    my $auth   = $u->authority();
    my $path   = $u->path();
    
    exit 1 if ! defined $scheme or ! defined $path;
    if ($scheme eq 'tftp') {
    } elsif ($scheme eq 'ftp') {
    } elsif ($scheme eq 'scp') {
    } elsif ($scheme eq 'sftp') {
    } else {
        print "Unsupported URI scheme.\n";
        exit 1;
    }
    exit 0;
}

if ($action eq 'update-revs') {
    die "Error: no revs" if ! defined $revs;
    print "update-revs [$revs]\n" if $debug;
    check_integer($revs);
    my $link = get_link($commit_revs_script);
    if ($revs == 0) {
        print "remove link [$link]\n" if $debug;
        $rc = system("rm -f $link");
    } else {
        if (! -e $link) {
            print "add link [$link]\n" if $debug;
            $rc = system("ln -s $commit_revs_script $link");
        }
        if (! -e $archive_dir) {
            system("sudo mkdir $archive_dir");
            system("sudo chgrp vyattacfg $archive_dir");
            system("sudo chmod 775 $archive_dir");
        }
        my $lr_conf = "$config_file {\n";
        $lr_conf   .= "\t su root vyattacfg\n";
        $lr_conf   .= "\t rotate $revs\n";
        $lr_conf   .= "\t start 0\n";
        $lr_conf   .= "\t compress \n";
        $lr_conf   .= "\t copy \n";
        $lr_conf   .= "}\n";
        cm_write_file($lr_conf_file, $lr_conf);

        # logrotate doesn't like when its config is writeable
        # for anyone but root
        system("sudo chmod 644 $lr_conf_file");

        my $num_revs = cm_get_num_revs();
        if (! -e "$archive_dir/commits" or $num_revs == 0) {
            # store a baseline config
            system("sudo touch $archive_dir/commits");
            system("sudo chgrp vyattacfg $archive_dir/commits");
            system("sudo chmod 664 $archive_dir/commits");
            my $cmd = "$commit_revs_script baseline config.boot";
            system("sudo sg vyattacfg \"export COMMIT_VIA=init; $cmd\"");
        }
        exit 0;
    }
    exit 0;
}

if ($action eq 'show-commit-log') {
    print "show-commit-log\n" if $debug;
    my $max_revs = cm_get_max_revs();
    if (!defined $max_revs or $max_revs <= 0) {
        print "commit-revisions is not configured.\n\n";
    }
    my @log = cm_commit_get_log();
    foreach my $line (@log) {
        print $line;
    }
    exit 0;
}

if ($action eq 'show-commit-log-brief') {
    print "show-commit-log-brief\n" if $debug;
    my $max_revs = cm_get_max_revs();
    my @log = cm_commit_get_log(1);
    foreach my $line (@log) {
        $line =~ s/\s/_/g;
        print $line, ' ';
    }
    exit 0;
}

if ($action eq 'show-commit-file') {
    die "Error: no revnum" if ! defined $revnum;
    print "show-commit-file [$revnum]\n" if $debug;
    check_valid_rev($revnum);
    my $file = cm_commit_get_file($revnum);
    print $file;
    exit 0;
}

if ($action eq 'diff') {
    print "diff\n" if $debug;    
    my $args = $#ARGV;
    if ($args < 0) {
        my $rc = system("cli-shell-api sessionChanged");
        if (defined $rc and $rc > 0) {
            print "No changes between working and active configurations.\n";
            exit 0;
        }
        my $show_args = '--show-show-defaults --show-context-diff';
        # default behavior for showConfig is @ACTIVE vs. @WORKING, so no
        # need to write to a file first
        my $diff = `cli-shell-api showConfig $show_args`;
        if (defined $diff and length($diff) > 0) {
            print "$diff";
        } else {
            print "No changes between working and active configurations.\n";
            exit 0;
        }
    } elsif ($args eq 0) {
        my $rev1 = $ARGV[0];
        check_valid_rev($rev1);
        my $filename1 = cm_commit_get_file_name($rev1);
        my $outfile = $filename1;
        $outfile =~ s/(.*)\.gz/$1/g;
        system("zcat $filename1 > $outfile");
        my $diff = `cli-shell-api showConfig --show-cfg1 $outfile --show-cfg2 \@WORKING --show-show-defaults --show-context-diff`;
        if (defined $diff and length($diff) > 0) {
            print "$diff";
        } else {
            print "No changes between working and "
                . "revision $rev1 configurations.\n";
        }
        system("rm $outfile");
    } elsif ($args eq 1) {
        my $rev1 = $ARGV[0];
        my $rev2 = $ARGV[1];
        check_valid_rev($rev1);
        check_valid_rev($rev2);
        my $filename  = cm_commit_get_file_name($rev1);
        my $filename2 = cm_commit_get_file_name($rev2);
        my $outfile = $filename;
        $outfile =~ s/(.*)\.gz/$1/g;
        system("zcat $filename > $outfile");
        my $outfile2 = $filename2;
        $outfile2 =~ s/(.*)\.gz/$1/g;
        system("zcat $filename2 > $outfile2");
        my $diff = `cli-shell-api showConfig --show-cfg1 $outfile2 --show-cfg2 $outfile --show-show-defaults --show-context-diff`;
        if (defined $diff and length($diff) > 0) {
            print "$diff";
        } else {
            print "No changes between revision $rev1 and "
                . "revision $rev2 configurations.\n";
        }
        system("rm $outfile2");
        system("rm $outfile");
    } elsif ($args eq 2) {
        my $rev1 = $ARGV[0];
        my $rev2 = $ARGV[1];
        check_valid_rev($rev1);
        check_valid_rev($rev2);
        my $filename  = cm_commit_get_file_name($rev1);
        my $filename2 = cm_commit_get_file_name($rev2);
        my $outfile = $filename;
        $outfile =~ s/(.*)\.gz/$1/g;
        system("zcat $filename > $outfile");
        my $outfile2 = $filename2;
        $outfile2 =~ s/(.*)\.gz/$1/g;
        system("zcat $filename2 > $outfile2");
        my $diff = `cli-shell-api showConfig --show-cfg1 $outfile2 --show-cfg2 $outfile --show-commands --show-show-defaults --show-context-diff`;
        if (defined $diff and length($diff) > 0) {
            my @difflines = split('\n', $diff);
            foreach my $line (@difflines) {
                my @words = split(' ', $line);
                my $elements = scalar(@words);
                my @non_leaf = @words[0 .. ($elements - 2)] ;
                my $path = join(' ', @non_leaf);
                $path =~ s/'//g;
                my $cmd = "$path " . @words[($elements - 1)];
                print "$cmd\n";
            }
        } else {
            print "No changes between revision $rev1 and "
                . "revision $rev2 configurations.\n";
        }
        system("rm $outfile2");
        system("rm $outfile");
    }
    exit 0;
}

if ($action eq 'commit-confirm') {
    die "Error: no minutes defined." if ! defined $minutes;
    print "commit-confirm [$minutes]\n" if $debug;

    # Check if there's already a timer.
    system("systemctl is-active --quiet ${job_name}.timer");
    if ($? == 0) {
        print "Another confirm is pending.\n";
        exit 0;
    }

    my $max_revs = cm_get_max_revs();
    if (!defined $max_revs or $max_revs <= 0) {
        print "commit-revisions is not configured.\n\n";
        exit 1;
    }
    check_integer($minutes);
    print "commit-confirm will automatically reboot in $minutes"
        . " minutes unless changes are confirmed.\n";
    if (prompt("Proceed?", -y1d=>"y")) {
    } else {
        print "commit-confirm canceled.\n";
        exit 1;
    }

    my @lines= cm_read_file(cm_get_boot_config_file());
    my $rollback_config  = join("\n", @lines);
    $rollback_config .= "\n";
    my $config_rb = cm_get_config_rb();
    cm_write_file($config_rb, $rollback_config);

    my $command = "/opt/vyatta/sbin/vyatta-config-mgmt.pl --action rollback "
        . "--file $config_rb";
    # Schedule a systemd timer to run rollback $minutes later.
    system("sudo systemd-run --quiet --on-active=${minutes}m --unit=${job_name} "
           . "sg vyattacfg \"${command}\"");
    # Check if the timer was created.
    system("systemctl is-active --quiet ${job_name}.timer");
    if ($? != 0) {
        print "Error: unable to schedule reboot.\n";
        exit 1;
    }
    print "Reboot scheduled for commit-confirm. "
        . "Confirm your changes to cancel the reboot.\n";
    # Call the script to notify the users of the impending reboot.
    system("sudo -b /opt/vyatta/sbin/commit-confirm-notify.py ${minutes}");
    exit 0;
}

if ($action eq 'confirm') {
    # Check if timer exists.
    system("systemctl is-active --quiet ${job_name}.timer");
    if ($? != 0) {
        print "No confirm pending.\n";
    } else {
        # If so, stop it.
        system("sudo systemctl stop --quiet ${job_name}.timer");
        # Kill the notification daemon if it's still running.
        system("sudo pkill -f commit-confirm-notify.py");
        print "Reboot timer stopped.\n";
    }
    exit 0;
}

if ($action eq 'rollback') {
    my ($method, $rollback_config) = (undef, undef);

    if (defined $revnum) {
        print "rollback [$revnum]\n" if $debug;
        check_valid_rev($revnum);        
        $method = 'revnum';
        if (prompt("Proceed with reboot? [confirm]", -y1d=>"y")) {
        } else {
            print "Cancelling rollback\n";
            exit 0;
        }
        $rollback_config = cm_commit_get_file($revnum);
    }

    if (defined $filename) {
        print "rollback [$filename]\n" if $debug;
        if (! -e $filename) {
            die "Error: file [$filename] doesn't exist";
        }
        if (defined $method) {
            die "Error: can only define revnum or file";
        }
        $method = 'file';
        # Should have code to validate config, but for now only
        # called internally.  If we later expose this to cli
        # we'll need to prompt for confirmation.
        my @lines = cm_read_file($filename);
        $rollback_config  = join("\n", @lines);
        $rollback_config .= "\n";
    }
    if (!defined $method) {
        die "Error: must define either revnum or file";
    }

    my ($user) = getpwuid($<);
    my $boot_config_file = cm_get_boot_config_file();
    my $archive_dir      = cm_get_archive_dir();
    my $last_commit_file = cm_get_last_commit_file();
    system("sudo cp $boot_config_file $archive_dir/config.boot-prerollback");
    cm_write_file($boot_config_file, $rollback_config);
    cm_write_file($last_commit_file, $rollback_config); # white lie
    my $cmd = "$commit_revs_script --rollback=1 rollback/reboot";
    system("sudo sg vyattacfg \"$cmd\"");
    openlog($0, "", LOG_USER);
    my $login = getpwuid($<) || "unknown";
    syslog("warning", "Rollback reboot requested by $login");
    closelog();
    exec("sudo /sbin/reboot");
}

exit $rc;

# end of file
