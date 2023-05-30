#!/usr/bin/perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use Module::Packaged::Report;
use Module::Packaged::Collect;

my %opts;
GetOptions(\%opts,
    'fetch',
    'build',
    'report=s',
    'dir=s',
    'help',
) or usage();

usage() if $opts{help};
usage('Need either --fetch, --build or --report') if not ($opts{fetch} or $opts{build} or $opts{report});
usage("Incorrect value for --report") if $opts{report} and $opts{report} !~ /^(test|all)$/;


my $mirror_dir = 'mirror';
my $collect = Module::Packaged::Collect->new($mirror_dir);
if ($opts{fetch}) {
    $collect->fetch_all;
}


if ($opts{build}) {
    $collect->load_all;
    $collect->save;
    #$collect->create_database;
    #$collect->fill_db;
}

if ($opts{report}) {
    if (not $opts{build}) {
        $collect->load;
        #$collect->load_db;
    }
    my $mpr = Module::Packaged::Report->new($collect, %opts);
    $mpr->generate_html_report;
}


# fetch
#   all
#   new  (only those that are supposed to change at all)
# build  from the 
# update update database from the newly mirrored files
# report 
#   all
#   test  (create report using a few selected modules)
sub usage {
    my $msg = shift || '';

    print <<"USAGE";
$msg
Usage: $0
            --fetch                  fetch from remote sites
            --build                  build database from the already mirrored files
            --report [test|all]      report using small number of modules or all modules
            

            --dir DIR         name of the directory where the reports are generated (defaults to ./report)

            --help            this help
USAGE

    exit;
}



