package Module::Packaged::Collect;
use strict;
use warnings;

use IO::File;
use File::Path                 qw(mkpath);
use File::Slurp                qw(slurp);
use Compress::Zlib;
use IO::String;
use IO::Zlib;
use File::Spec::Functions qw(catdir catfile tmpdir);
use LWP::Simple qw(mirror);
use Parse::CPAN::Packages;
use Parse::Debian::Packages;
use Parse::Fedora::Packages;
use Sort::Versions;
use Storable qw(store retrieve);
use base 'Class::Accessor::Chained::Fast';
__PACKAGE__->mk_accessors(qw(data));

=head1 NAME

Module::Packaged - Report upon packages of CPAN distributions

=head1 SYNOPSIS

  use Module::Packaged::Collect;

  my $p = Module::Packaged->new();
  my $dists = $p->check('Archive-Tar');
  # $dists is now:
  # {
  # cpan    => '1.08',
  # debian  => '1.03',
  # fedora  => '0.22',
  # freebsd => '1.07',
  # gentoo  => '1.05',
  # openbsd => '0.22',
  # suse    => '0.23',
  # }

  # meaning that Archive-Tar is at version 1.08 on CPAN but only at
  # version 1.07 on FreeBSD, version 1.05 on Gentoo, version 1.03 on
  # Debian, version 0.23 on SUSE and version 0.22 on OpenBSD

=head1 DESCRIPTION

CPAN consists of distributions. However, CPAN is not an isolated
system - distributions are also packaged in other places, such as for
operating systems. This module reports whether CPAN distributions are
packaged for various operating systems, and which version they have.

Note: only CPAN, Debian, Fedora (Core 2), FreeBSD, Gentoo, Mandriva
(10.1), OpenBSD (3.6) and SUSE (9.2) are currently supported. I want to
support everything else. Patches are welcome.

=head1 METHODS

=cut


=head2 new()

The new() method is a constructor:

    my $p = Module::Packaged::Collect->new();

=cut
sub new {
    my ($class, $mirror_dir) = @_;
    my $self  = {};
    bless $self, $class;
    $self->{mirror_dir} = $mirror_dir;
    $self->{dbfile}     = 'data.db';
    $self->{distributors} = {};
    mkpath $self->{mirror_dir};
    return $self;
}

sub set_dbh {
    my ($self, $dbh) = @_;
    $self->{dbh} = $dbh;
}

sub fill_db {
    my ($self) = @_;

    $self->{dbh}->begin_work;

    my @distributor = keys %{ $self->{distributors} };
    my %id_of_distributor;
    foreach my $id (0..@distributor-1) {
        $self->{dbh}->do("INSERT INTO distributor (id, name) VALUES(?, ?)", undef, $id, $distributor[$id]);
        $id_of_distributor{ $distributor[$id] } = $id;
    }

    my $sth_dist = $self->{dbh}->prepare("INSERT INTO cpan_dist (id, name) VALUES(?, ?)");
    my $sth = $self->{dbh}->prepare("INSERT INTO version (distributor, cpan_dist, no) VALUES(?, ?, ?)");

    my $dist_id = 0;
    foreach my $dist_name (keys %{ $self->{data} }) {
        #print "$dist_name\n";
        $dist_id++;
        $sth_dist->execute($dist_id, $dist_name);
        foreach my $name (keys %{ $self->{data}{$dist_name} }) {
            $sth->execute($id_of_distributor{$name}, $dist_id, $self->{data}{$dist_name}{$name});
        }
    }
    $self->{dbh}->commit;

}

sub save {
    my ($self) = @_;
    store $self->{data}, 'data.store';
}
sub load {
    my ($self) = @_;
    $self->{data} = retrieve 'data.store';
}


=head2 fetch_all()

Fetch all the files from the distributions.

    $p->fetch_all

=cut
sub fetch_all {
    my ($self) = @_;

    $self->fetch_cpan;
    $self->fetch_debian( qw( stable testing unstable ) );
    #$self->_fetch_ubuntu;
    #$self->_fetch_fedora;
    #$self->_fetch_freebsd;
    #$self->_fetch_gentoo;
    #$self->_fetch_mandriva;
    #$self->_fetch_openbsd;
    #$self->_fetch_suse;
    #$self->_fetch_activeperl;
    return;
}

sub load_all {
    my ($self) = @_;

    $self->load_cpan;
    return;
}



=head2 fetch_cpan()

Fetching http://www.cpan.org/modules/02packages.details.txt.gz

=cut
sub fetch_cpan {
    my ($self) = @_;

    my $local = $self->get_local_cpan();
    $self->_mirror("http://www.cpan.org/modules/02packages.details.txt.gz", $local);
    return;
}

sub get_local_cpan {
    my ($self) = @_;
    my $mirror_dir = catfile($self->{mirror_dir}, 'cpan');
    mkpath $mirror_dir;
    return catfile($mirror_dir, '02packages.details.txt.gz');
}
sub load_cpan {
    my ($self) = @_;
    my $local = $self->get_local_cpan;

    my $details = slurp $local;
    $details = Compress::Zlib::memGunzip($details);

    my $pcp = Parse::CPAN::Packages->new($details);

    #$self->{distributors}{cpan} = 1;
    foreach my $dist ($pcp->latest_distributions) {
        $self->{data}->{ $dist->dist }->{cpan} = {
                version => $dist->version,
                cpanid  => $dist->cpanid,
            };
    }
    return;
}


=head2 fetch_debian

   fetch_debian(@distributions);

The base URL of all the files listing the packages is L<http://ftp.debian.org/dists/>
within that there are distributions. There are 3 pseudo names: stable, testing and unstable
and there are specific versions of Debian such as etch.

Within each distribution there are several groups of packages. We are currently only interested
in the C<main> group. Within that we'll only care about C<binary-i386> for now.

So in DIST/main/binary-i386/   there is a file called Packages.gz that's what we are going to fetch.

=cut
# http://ftp.debian.org/dists/Debian4.0r0/main/binary-i386/Packages.bz2
# http://packages.debian.org/
sub fetch_debian {
    my ($self, @dists) = @_;
    my @locals;
    foreach my $dist (@dists) {
        my $name = "debian_$dist";
        $self->{distributors}{$name} = 1;

        my $url  = "http://ftp.debian.org/dists/$dist/main/binary-i386/Packages.gz";
        my $file = "Packages.gz";
        
        my $mirror_dir = catfile($self->{mirror_dir}, "Debian", $dist);
        mkpath $mirror_dir;
        my $local = catfile($mirror_dir, $file);

        $self->__fetch_debian_like($url, $local);
        push @locals, [$name, $local];

        #my $ae = Archive::Extract->new( archive => $local );
        #$ae->extract( to => $unzip_dir ); 
    }
    return @locals;
}

sub load_debian {
    my ($self, @dists) = @_;
    my @locals = $self->fetch_debian(@dists);
    foreach my $name_local (@locals) {
        $self->__load_debian_like(@$name_local);
    }
    return;
}


sub __fetch_debian_like {
    my ($self, $url, $file, $name) = @_;

    $self->_mirror($url, $file);
    return
}

sub __load_debian_like {
    my ($self, $name, $file) = @_;

    my %cpan_dists = map { lc $_ => $_ } keys %{ $self->{data} };

    my $data = slurp($file);
    $data = Compress::Zlib::memGunzip($data);

    my $fh       = IO::String->new($data);
    my $debthing = Parse::Debian::Packages->new($fh);
    while (my %package = $debthing->next) {
        next
            unless $package{Package} =~ /^lib(.*?)-perl$/
            || $package{Package}     =~ /^perl-(tk)$/;
        my $cpan_dist = $cpan_dists{$1} or next;

        # don't care about the debian version
        my ($version) = $package{Version} =~ /^(.*?)-/;
        $self->{data}{$cpan_dist}{$name} = $version
            if $self->{data}{$cpan_dist};
    }
    return;
}



sub _fetch_gentoo {
  my $self = shift;

  # http://packages.gentoo.org/
  my $file =
    $self->cache->get_url("http://www.gentoo.org/dyn/gentoo_pkglist_x86.txt",
    "gentoo.html");
  $file =~ s{</a></td>\n}{</a></td>}g;

  my @dists = keys %{ $self->{data} };

  foreach my $line (split "\n", $file) {
    next unless ($line =~ m/dev-perl/);
    my $dist;
    $line =~ s/\.ebuild//g;
    my ($package, $version, $trash) = split(' ', $line);
    next unless $package;

    # Let's try to find a cpan dist that matches the package name
    if (exists $self->{data}->{$package}) {
      $dist = $package;
    } else {
      foreach my $d (@dists) {
        if (lc $d eq lc $package) {
          $dist = $d;
          last;
        }
      }
    }

    if ($dist) {
      $self->{data}->{$dist}->{gentoo} = $version;
    } else {

      # I should probably care about these and fix them
      # warn "Could not find $package: $version\n";
    }
  }
}

sub _fetch_fedora {
  my $self = shift;
  # http://download.fedora.redhat.com/pub/fedora/linux/core/6/i386/os/repodata/
  foreach my $v (qw(6 development)) {
    foreach my $file (qw(comps.xml filelists.xml.gz other.xml.gz primary.xml.gz)) {
      my $url = "http://download.fedora.redhat.com/pub/fedora/linux/core/$v/i386/os/repodata/$file";
      eval {my $local_file =
        $self->cache->get_url($url, "fedora_${v}_${file}.html");
        # perl -MStorable -e 'use Data::Dumper; $d =
        # retrieve("~/.module_packaged_generate/cache/http_download_fedora_redhat_com_pub_fedora_linux_core_6_i386_os_repodata_primary_xml_gz");
        # print $d->{value}' > priary.xml.gz
        my $p = Parse::Fedora::Packages->new();
        print length($local_file), "\n";
        #$f->parse_primary($local_file);
      };
      #lftp -c get "https://admin.fedoraproject.org/pkgdb/acls/bugzilla?tg_format=plain" -o $owners/owners.list.raw
      # cat $owners/owners.list.raw | grep '^Fedora|' > $owners/owners.fedora.list
        # grep perl- owners.fedora.list

    }
  }
  #
  my $file =
    $self->cache->get_url("http://fedora.redhat.com/docs/package-list/fc2/",
    "fedora.html");
  foreach my $line (split "\n", $file) {
    next unless $line =~ /^perl-/;
    my ($dist, $version) =
      $line =~ m{perl-(.*?)</td><td class="column-2">(.*?)</td>};

    # only populate if CPAN already has
    $self->{data}{$dist}{fedora} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_suse {
  my $self = shift;
  my $file = $self->cache->get_url(
    "http://www.novell.com/products/linuxpackages/suselinux/index_all.html",
    "suse.html"
  );

  foreach my $line (split "\n", $file) {

   #    <a href="perl-dbi.html">perl-DBI 1.43 </a> (The Perl Database Interface)
    my ($dist, $version) = $line =~ m{">perl-(.*?) (.*?) </a>};
    next unless $dist;

    # only populate if CPAN already has
    $self->{data}{$dist}{suse} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_mandriva {
  my $self  = shift;

  # from http://www.mandriva.com/en/download one can reach the various mirrors
  # e.g. http://ftp.ale.org/pub/mirrors/mandrake/official/iso/2007.1/
  # and then find the *.idx files
  # http://ftp.ale.org/pub/mirrors/mandrake/official/iso/2007.1/mandriva-linux-2007-spring-free-dvd-i586.idx
  #
  # also suggested:
  # ftp://ftp.nluug.nl/pub/os/Linux/distr/Mandriva/official/2007.1/i586/media/main/release/

  my $file = $self->cache->get_url(
    "http://ftp.ale.org/pub/mirrors/mandrake/official/iso/2007.1/mandriva-linux-2007-spring-free-dvd-i586.idx",
    "mandriva1.idx");

  #my $file1 = $self->cache->get_url(
  #"http://distro.ibiblio.org/pub/linux/distributions/mandriva/MandrivaLinux/official/10.2/i586/media/media_info/synthesis.hdlist_main.cz",
  #  "mandrake1.html"
  #);
  #my $file2 = $self->cache->get_url(
  #"http://distro.ibiblio.org/pub/linux/distributions/mandriva/MandrivaLinux/official/10.2/i586/media/media_info/synthesis.hdlist_contrib.cz",
  # "mandrake2.html"
  #);

  #foreach my $file ($file1, $file2) {
  #  $file = Compress::Zlib::memGunzip($file);
  #  foreach my $line (split / /, $file) {

      # @info@perl-DBI-1.43-2mdk.i586@0@1371700@Development/Perl
 #     next
 #       unless my ($dist, $version) =
 #       $line =~ m{\@info\@perl-(.*)-(.*?)-\d+mdk};

      # only populate if CPAN already has
 #     $self->{data}{$dist}{mandrake} = $version
 #       if $self->{data}{$dist};
 #   }
 # }
}

sub _fetch_freebsd {
  my $self = shift;
  my $file = $self->cache->get_url("http://www.freebsd.org/ports/perl5.html",
    "freebsd.html");
   # http://www.freebsd.org/cgi/ports.cgi?query=perl&stype=all
   #ftp://ftp.freebsd.org/pub/FreeBSD/ports/ports/ports.tar.gz
   #ls ftp://ftp.freebsd.org/pub/FreeBSD/ports/i386/packages-6-stable/perl5
   # or
   #ls ftp://ftp.freebsd.org/pub/FreeBSD/ports/i386/packages-6-stable/ALL
   #/pub/FreeBSD/releases/i386/6.2-RELEASE/ports/ports.tgz

#<DT><B><A NAME="p5-DBI-1.37"></A><A HREF="http://www.FreeBSD.org/cgi/cvsweb.cgi/ports/databases/p5-DBI-137">p5-DBI-1.37</A></B> </DT>
  for my $package ($file =~ m/A NAME="p5-(.*?)"/g) {
    my ($dist, $version) = $package =~ /^(.*?)-(\d.*)$/ or next;

    # tidy up the oddness FreeBSD versions
    $version =~ s/_\d$//;

    # only populate if CPAN already has
    $self->{data}{$dist}{freebsd} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_activeperl {
  my $self = shift;
  # http://ppm.activestate.com/PPMPackages/zips/
  # http://ppm.activestate.com/PPMPackages/zips/8xx-builds-only/
  foreach my $platform (qw( Windows Solaris Linux HP-UX Darwin )) {
    my $name = lc "activeperl_8xx_$platform";
    my $file = $self->cache->get_url("http://ppm.activestate.com/PPMPackages/zips/8xx-builds-only/$platform/",
      "$name.html");
    # <tr><td valign="top"><img src="/icons/compressed.gif" alt="[   ]"></td><td><a href="ABI-0.01.zip">ABI-0.01.zip</a></td><td align="right">17-Mar-2006 12:58  </td><td align="right">5.0K</td></tr>
    for my $package ($file =~ m/href="([^"]+)"/g) {
      my ($dist, $version) = $package =~ /^(\D+)-(\d.*)\.zip$/ or next;
      # only populate if CPAN already has
      $self->{data}{$dist}{$name} = $version
        if $self->{data}{$dist};
    }
  }
}

sub _fetch_ubuntu {
  my $self = shift;
  # http://archive.ubuntu.com/ubuntu/dists/feisty/main/binary-i386/Packages.gz

  for my $dist (qw( feisty gutsy warty hoary edgy dapper breezy)) {
    for my $repo (qw(main restricted universe)) {
      my $url  = "http://archive.ubuntu.com/ubuntu/dists/$dist/$repo/binary-i386/Packages.gz";
      my $file = "ubuntu-$dist-$repo-Packages.gz";
      my $name = "ubuntu_${dist}_${repo}";
      $self->__fetch_debian_like($url, $file, $name);
    }
  }
}

sub _mirror {
    my ($self, $url, $local) = @_;
    #return if not $self->{fetch};
    mirror($url, $local);
    return;
}

sub _fetch_netbsd {
  my $self = shift;
  # http://pkgsrc.se/search.php?so=p5
}

sub _fetch_openbsd {
  my $self = shift;
  # http://ports.openbsd.nu/search.php?stype=folder&so=p5
  my $file =
    $self->cache->get_url("http://www.openbsd.org/3.6_packages/i386.html",
    "openbsd.html");

  for my $package ($file =~ m/href=i386\/p5-(.*?)\.tgz-long/g) {
    my ($dist, $version) = $package =~ /^(.*?)-(\d.*)$/ or next;

    # only populate if CPAN already has
    $self->{data}{$dist}{openbsd} = $version
      if $self->{data}{$dist};
  }
}

=head2 check()

The check() method returns a hash reference. The keys are various
distributions, the values the version number included:

  my $dists = $p->check('Archive-Tar');

=cut

sub check {
  my ($self, $dist) = @_;

  return $self->{data}->{$dist};
}

=head2 create_database

Creates a clean SQLite database for the data to be collected.

=cut
sub create_database {
    my ($self) = @_;
    unlink $self->{dbfile};
    $self->connect_db;
    foreach my $sql (split /;/, slurp ('schema.sql')) {
        next if $sql !~ /\S/;
        $self->{dbh}->do($sql);
    }
    return;
}

sub load_db {
    my ($self) = @_;

    $self->connect_db;
    $self->{p}->set_dbh($self->{dbh});
    $self->{p}->load;
}


=head2 connect_db

connct to the database.

=cut
sub connect_db {
    my ($self) = @_;
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{dbfile}", "", "", {AutoCommit => 1});
}


1;

=head1 TODO

 - mapping of names to URLs
 - fetch files based for a selected set of names from the mapping
 - parse the downloaded files and fill an SQLite database
 - create static reports from the SQL database

=head1 COPYRIGHT

Copyright (c) 2007-8 Gabor Szabo. All rights reserver.

Copyright (c) 2003-7 Leon Brocard. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it 
under the same terms as Perl itself.

=head1 AUTHOR

Gabor Szabo 

Based on the code of Module::Packeged::Generate of 
Leon Brocard, leon@astray.com

