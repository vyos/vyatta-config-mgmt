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
use URI;

my $commit_uri_script  = '/opt/vyatta/sbin/vyatta-commit-push.pl';
my $commit_revs_script = '/opt/vyatta/sbin/vyatta-commit-revs.pl';

my $commit_hook_dir = cm_get_commit_hook_dir();
my $archive_dir     = cm_get_archive_dir();
my $config_file     = "$archive_dir/config.boot";
my $lr_conf_file    = cm_get_lr_conf_file();

my $debug = 0;

sub get_link {
    my ($path) = @_;

    my $link = $commit_hook_dir . basename($path);
    return $link;
}


#
# main
#
my ($action, $uri, $revs, $revnum);

GetOptions("action=s"      => \$action,
           "uri=s"         => \$uri,
           "revs=i"        => \$revs,
           "revnum=i"      => \$revnum,
);

die "Error: no action"      if ! defined $action;

my ($cmd, $rc) = ('', 1);

if ($action eq 'add-uri') {
    print "add-uri\n" if $debug;
    my $config = new Vyatta::Config;
    $config->setLevel('system config-mgmt remote-archive');
    my @uris = $config->returnValues('commit-uri');
    my $link = get_link($commit_uri_script);
    if (scalar(@uris) >= 1 and ! -e $link) {
        print "add link [$link]\n" if $debug;
        $rc = system("ln -s $commit_uri_script $link");
        exit $rc;
    }
    exit 0;
}

if ($action eq 'del-uri') {
    print "del-uri\n" if $debug;
    my $config = new Vyatta::Config;
    $config->setLevel('system config-mgmt remote-archive');
    my @uris = $config->returnValues('commit-uri');
    if (scalar(@uris) <= 0) {
        my $link = get_link($commit_uri_script);
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
    } else {
        print "Unsupported URI scheme\n";
        exit 1;
    }
    exit 0;
}

if ($action eq 'update-revs') {
    die "Error: no revs" if ! defined $revs;
    print "update-revs [$revs]\n" if $debug;
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
        }
        my $lr_conf = "$config_file {\n";
        $lr_conf   .= "\t rotate $revs\n";
        $lr_conf   .= "\t compress \n";
        $lr_conf   .= "}\n";
        cm_write_file($lr_conf_file, $lr_conf);
        exit 0;
    }
    exit 0;
}

if ($action eq 'show-commit-log') {
    print "show-commit-log\n" if $debug;
    my @log = cm_commit_get_log();
    foreach my $line (@log) {
        print $line;
    }
    exit 0;
}

if ($action eq 'show-commit-file') {
    die "Error: no revnum" if ! defined $revnum;
    print "show-commit-file [$revnum]\n" if $debug;
    my $file = cm_commit_get_file($revnum);
    print $file;
}

exit $rc;

# end of file
