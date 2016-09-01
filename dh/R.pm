# A debhelper build system for R

package Debian::Debhelper::Buildsystem::R;

use feature say;
use strict;
use Cwd;
use Dpkg::Control::Info;
use Dpkg::Changelog::Debian;
use Debian::Debhelper::Dh_Lib;
use base 'Debian::Debhelper::Buildsystem';

sub DESCRIPTION {
    "R buildsystem"
}

sub new {
    my $class=shift;
    my $this=$class->SUPER::new(@_);
    $this->enforce_in_source_building();
    return $this;
}

sub check_auto_buildable {
    # R packages are auto-buildable if they contain ./DESCRIPTION in the
    # source package

    my $this=shift;
    return -e $this->get_sourcepath("DESCRIPTION") ? 1 : 0;
}

sub parse_depends {
    # try and convert R package dependencies in DESCRIPTION into a
    # list of debian package dependencies

    my $field = shift;
    my @text = split(/,/, qx/grep-dctrl -s $field -n . DESCRIPTION/);
    my @deps;
    foreach my $dep (@text) {
        chomp $dep;
        # rely on the R version format being equivalent
        $dep =~ /^(\w+)\s*(\(.*\))?$/;
        my $pkg = lc $1;
        my $vers = $2;
        if ($pkg eq "r") {
            # TODO: check if the available version of R satisfies this
            # for now, discard it, since we generate R (>= curver)
            say "W: Ignoring specified R dependency: $dep";
            next;
        }

        if (system("dpkg-query", "-W", "r-cran-$pkg") == 0) {
            say "I: Using r-cran-$pkg for $field:$dep";
            push (@deps, "r-cran-$pkg $vers");
        } elsif (system("dpkg-query", "-W", "r-bioc-$pkg") == 0) {
            say "I: Using r-bioc-$pkg for $field:$dep";
            push (@deps, "r-bioc-$pkg $vers");
        } else {
            say "W: Cannot find a debian package for $field:$dep";
        }
    }
    return @deps;
}

sub install {
    my $this = shift;
    my $destdir = shift;

    # it would be nice to use Dpkg::Control::Info here since the
    # format is the same, but we can't because it checks the first
    # block contains Source: and errors when it doesn't
    chomp(my $rpackage = qx/grep-dctrl -s Package -n . DESCRIPTION/);
    chomp(my $rversion = qx/grep-dctrl -s Version -n . DESCRIPTION/);

    say "I: R Package: $rpackage Version: $rversion";

    # Priority: Recommended should go in /library instead of /site-library
    chomp(my $rpriority = qx/grep-dctrl -s Priority -n . DESCRIPTION/);

    my $libdir = "usr/lib/R/site-library";
    if ($rpriority eq "Recommended") {
        $libdir = "usr/lib/R/library";
        say "I: R package with Priority: $rpriority, installing in $libdir";
    }

    # this appears to be set ("CRAN") for packages originating from CRAN,
    # but is not set for bioconductor, nor for packages direct from upstream
    chomp(my $rrepo = qx/grep-dctrl -s Repository -n . DESCRIPTION/);

    # however, biocViews is (presumably) only going to be set for bioconductor
    # packages, so nonzero should identify
    chomp(my $rbiocviews = qx/grep-dctrl -s biocViews -n . DESCRIPTION/);

    my $srcctrl = Dpkg::Control::Info->new()->get_source();

    my $repo = "CRAN";
    if (defined $ENV{RRepository}) {
        $repo = $ENV{RRepository};
        say "I: Using repo=$repo from env RRepository";
    } elsif (length $rrepo) {
        $repo = $rrepo;
        say "I: Using repo=$repo from DESCRIPTION::Repository";
    } elsif (length $rbiocviews) {
        $repo = "BIOC";
        say "I: Using repo=$repo due to existence of DESCRIPTION::biocViews";
    } elsif ($this->sourcepackage() =~ /^r-cran/) {
        $repo = "CRAN";
        say "I: Using repo=$repo based on source package name";
    } elsif ($this->sourcepackage() =~ /^r-bioc/) {
        $repo = "BIOC";
        say "I: Using repo=$repo based on source package name";
    } else {
        say "I: Using repo=$repo by default";
    }


    # this is used to determine the install directory during build
    # TODO: check this actually matches the binary name in d/control?
    my $debname = "r-" . lc($repo) . "-" . lc($rpackage);
    say "I: Using debian package name: $debname";

    chomp(my $rpkgversion = qx/dpkg-query -W -f='\${Version}' r-base-dev/);
    say "I: Building using R version $rpkgversion";

    chomp(my $rapiversion = qx/dpkg-query -W -f='\${Provides}' r-base-core | grep -o 'r-api[^, ]*'/);
    say "I: R API version: $rapiversion";

    chomp(my $builttime = qx/dpkg-parsechangelog | grep-dctrl -s Date -n ./);
    say "I: Using built-time from d/changelog: $builttime";



    $this->doit_in_sourcedir("mkdir", "-p", "$destdir/$libdir");

    my @instargs;
    if (defined $ENV{RMakeFlags}) {
        say "I: Using MAKEFLAGS=" . $ENV{RMakeFlags};
        push (@instargs, "MAKEFLAGS=" . $ENV{RMakeFlags});
    }

    push (@instargs, "R", "CMD", "INSTALL", "-l", "$destdir/$libdir", "--clean");
    if (defined $ENV{RExtraInstallFlags}) {
        say "I: Using extra install flags: $ENV{RExtraInstallFlags}";
        push (@instargs, $ENV{RExtraInstallFlags});
    }
    push (@instargs, ".");
    push (@instargs, "--built-timestamp='$builttime'");

    $this->doit_in_sourcedir(@instargs);

    my @toremove = ("R.css", "COPYING*", "LICENSE*");
    foreach my $rmf (@toremove) {
        $this->doit_in_sourcedir("rm", "-vf", "$destdir/$libdir/$rpackage/$rmf");
    }

    my $sourcepackage = $this->sourcepackage();
    my $rdepends = join(",", parse_depends("Depends"));
    my $rrecommends = join(",", parse_depends("Recommends"));
    my $rsuggests = join(",", parse_depends("Suggests"));
    my $rimports = join(",", parse_depends("Imports"));

    open(my $svs, ">>", "debian/$sourcepackage.substvars");
    say $svs "R:Depends=r-base-core (>= $rversion), $rapiversion";
    say $svs "R:PkgDepends=$rdepends, $rimports";
    say $svs "R:Recommends=$rrecommends";
    say $svs "R:Suggests=$rsuggests";
    close $svs;

}

1
