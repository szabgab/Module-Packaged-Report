use strict;
use warnings;

use File::Path    qw(rmtree mkpath);
use File::Copy    qw(copy);
use Data::Dumper  qw(Dumper);

use Test::More;
use Test::Deep;
my $tests;

plan tests => $tests;

use Module::Packaged::Collect;

rmtree 'test/';
my $mirror_dir = 'test/mirror';
my $collect = Module::Packaged::Collect->new($mirror_dir);

{
    isa_ok($collect, 'Module::Packaged::Collect');
    cmp_deeply $collect, noclass({
        'mirror_dir'   => 'test/mirror',
        'dbfile'       => 'data.db',
        'distributors' => {},
    }), 'Collect fileds';
    BEGIN { $tests += 2; }
}

my @mirrors;
{
    no warnings 'redefine';
    sub Module::Packaged::Collect::mirror($$) {
        push @mirrors, \@_;
    }
}

{
    @mirrors = ();
    $collect->fetch_cpan;
    $collect->fetch_debian( qw( stable ) );
    #diag Dumper \@mirrors;
    cmp_deeply \@mirrors, 
        [
           [
             'http://www.cpan.org/modules/02packages.details.txt.gz',
             'test/mirror/cpan/02packages.details.txt.gz'
           ],
           [
             'http://ftp.debian.org/dists/stable/main/binary-i386/Packages.gz',
             'test/mirror/Debian/stable/Packages.gz'
           ]
         ],
         'fetch_cpan and fetch_debian';
    cmp_deeply $collect, noclass({
                    'mirror_dir' => 'test/mirror',
                    'dbfile' => 'data.db',
                    'distributors' => {
                                      'debian_stable' => 1,
                                    }
                }), 'fields';

    BEGIN { $tests += 2; }
}

{
    @mirrors = ();
    $collect->fetch_all;
    my $url_re = re('^http://');
    my $path_re = re('^test/mirror');

    cmp_deeply \@mirrors, array_each([$url_re, $path_re]), 'fetch_all mirrors';
    cmp_deeply $collect, noclass({
                    'mirror_dir' => 'test/mirror',
                    'dbfile' => 'data.db',
                    'distributors' => {
                                        'debian_stable' => 1,
                                        'debian_testing' => 1,
                                        'debian_unstable' => 1,
                                    }
                }), 'fields';
    BEGIN { $tests += 2; }
}

{
    @mirrors = ();
    mkpath 'test/mirror/cpan/';
    copy 't/files/02packages.details.txt.gz', 'test/mirror/cpan';
    
    $collect->load_cpan();
#    diag Dumper $collect;
    cmp_deeply $collect, noclass({
                    'mirror_dir' => 'test/mirror',
                    'dbfile' => 'data.db',
                    'distributors' => {
                                        'debian_stable' => 1,
                                        'debian_testing' => 1,
                                        'debian_unstable' => 1,
                                    },
                    'data' => ignore(),
                }), 'fields after load_cpan';
    my $key_re = re('^[\w-]+$');
    cmp_deeply $collect->{data}, { $key_re => ignore() };
    #$collect->load_all();
    #$collect->save;
#'Acme-Bleach-Numerically' => {
#                                                             'cpan' => {
#                                                                         'version' => '0.04',
#                                                                         'cpanid' => 'DANKOGAI'
#                                                                       }
#                                                           },


    cmp_deeply \@mirrors, [], 'mirror was not called';
    BEGIN { $tests += 2; }
}


