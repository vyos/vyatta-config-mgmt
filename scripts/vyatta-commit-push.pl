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
# Description: Script to push cofig.boot to one or more URIs
#
# **** End License ****
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5/';

use Vyatta::Config;
use Vyatta::ConfigMgmt;
use POSIX;
use File::Compare;
use File::Copy;
use URI;
use WWW::Curl::Easy;
use Sys::Hostname;


my $debug = 0;

my $config = new Vyatta::Config;
$config->setLevel('system config-mgmt remote-archive');
my @uris = $config->returnOrigValues('commit-uri');

if (scalar(@uris) < 1) {
    print "No URI's configured\n";
    exit 0;
}

my $last_push_file = cm_get_last_push_file();
my $tmp_push_file  = "/tmp/config.boot.$$";

my $cmd = 'cli-shell-api showCfg --show-active-only';
system("$cmd > $tmp_push_file");

if (-e $last_push_file and compare($last_push_file, $tmp_push_file) == 0) {
    exit 0;
}

my $timestamp = strftime(".%Y%m%d_%H%M%S", localtime);
my $hostname = hostname();
$hostname = 'vyatta' if ! defined $hostname;
my $save_file = "config.boot-$hostname" . $timestamp;

print "Archiving config...\n";
foreach my $uri (@uris) {
    my $u      = URI->new($uri);
    my $scheme = $u->scheme();
    my $auth   = $u->authority();
    my $path   = $u->path();
    my ($host, $remote) = ('', '');
    if (defined $auth and $auth =~ /.*\@(.*)/) {
        $host = $1;
    } else {
        $host = $auth if defined $auth;
    }
    $remote .= "$scheme://$host";
    $remote .= "$path" if defined $path;
    print "  $remote ";
    open(my $FILE, '<', $tmp_push_file) or die "Error: read $!";
    my $curl = new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_NOPROGRESS, 1);
    $curl->setopt(CURLOPT_URL, "$uri/$save_file");
    $curl->setopt(CURLOPT_UPLOAD, 1);
    $curl->setopt(CURLOPT_INFILE, $FILE);
    $curl->setopt(CURLOPT_VERBOSE, $debug);
    my $retcode = $curl->perform;
    if ($retcode == 0) {
        print "Ok\n";
    } else {
        print "Failed: " . $curl->strerror($retcode) . "\n";
    }
}
move($tmp_push_file, $last_push_file);

exit 0;
