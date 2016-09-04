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
    my @text = split(/,\s*/, qx/grep-dctrl -s $field -n . DESCRIPTION/);
    my @deps;

    # get all available r-* packages from which we can guess dependencies
    my @aptavail = qx/grep-aptavail -P -s Package -n -e ^r-/;
    my %apthash;
    @apthash{@aptavail} = ();


    foreach my $dep (@text) {
        chomp $dep;
        # rely on the R version format being equivalent
        $dep =~ /^(\w+)\s*(\([^()]*\))?$/;
        my $pkg = lc $1;
        my $vers = $2;
        if ($pkg eq "r") {
            # TODO: check if the available version of R satisfies this
            # for now, discard it, since we generate R (>= curver)
            say "W: Ignoring specified R dependency: $dep";
            next;
        }

        # check if r-cran-pkg or r-bioc-pkg exists, and add it as a
        # dependency (or recommend/suggest)
        if (exists $apthash{"r-cran-$pkg\n"}) {
            say "I: Using r-cran-$pkg for $field:$dep";
            push (@deps, "r-cran-$pkg $vers");
        } elsif (exists $apthash{"r-bioc-$pkg\n"}) {
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
    chomp(my $desc_package = qx/grep-dctrl -s Package -n . DESCRIPTION/);
    chomp(my $desc_version = qx/grep-dctrl -s Version -n . DESCRIPTION/);

    say "I: R Package: $desc_package Version: $desc_version";

    # Priority: Recommended should go in /library instead of /site-library
    chomp(my $desc_priority = qx/grep-dctrl -s Priority -n . DESCRIPTION/);

    my $libdir = "usr/lib/R/site-library";
    if ($desc_priority eq "Recommended") {
        $libdir = "usr/lib/R/library";
        say "I: R package with Priority: $desc_priority, installing in $libdir";
    }

    # this appears to be set ("CRAN") for packages originating from CRAN,
    # but is not set for bioconductor, nor for packages direct from upstream
    chomp(my $desc_repo = qx/grep-dctrl -s Repository -n . DESCRIPTION/);

    # however, biocViews is (presumably) only going to be set for bioconductor
    # packages, so nonzero should identify
    chomp(my $desc_biocviews = qx/grep-dctrl -s biocViews -n . DESCRIPTION/);

    my $srcctrl = Dpkg::Control::Info->new()->get_source();

    my $repo = "CRAN";
    if (defined $ENV{RRepository}) {
        $repo = $ENV{RRepository};
        say "I: Using repo=$repo from env RRepository";
    } elsif (length $desc_repo) {
        $repo = $desc_repo;
        say "I: Using repo=$repo from DESCRIPTION::Repository";
    } elsif (length $desc_biocviews) {
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
    my $debname = "r-" . lc($repo) . "-" . lc($desc_package);
    say "I: Using debian package name: $debname";

    chomp(my $rbase_version = qx/dpkg-query -W -f='\${Version}' r-base-dev/);
    say "I: Building using R version $rbase_version";

    chomp(my $rapi_version = qx/dpkg-query -W -f='\${Provides}' r-base-core | grep -o 'r-api[^, ]*'/);
    say "I: R API version: $rapi_version";

    chomp(my $changelog_time = qx/dpkg-parsechangelog | grep-dctrl -s Date -n ./);
    say "I: Using built-time from d/changelog: $changelog_time";



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
    push (@instargs, "--built-timestamp='$changelog_time'");

    $this->doit_in_sourcedir(@instargs);

    my @toremove = ("R.css", "COPYING", "COPYING.txt", "LICENSE", "LICENSE.txt");
    foreach my $rmf (@toremove) {
        if (-e "$destdir/$libdir/$desc_package/$rmf") {
            $this->doit_in_sourcedir("rm", "-vf", "$destdir/$libdir/$desc_package/$rmf");
        }
    }

    my $sourcepackage = $this->sourcepackage();
    my $rdepends = join(",", parse_depends("Depends"));
    my $rrecommends = join(",", parse_depends("Recommends"));
    my $rsuggests = join(",", parse_depends("Suggests"));
    my $rimports = join(",", parse_depends("Imports"));

    open(my $svs, ">>", "debian/$sourcepackage.substvars");
    say $svs "R:Depends=r-base-core (>= $rbase_version), $rapi_version";
    say $svs "R:PkgDepends=$rdepends, $rimports";
    say $svs "R:Recommends=$rrecommends";
    say $svs "R:Suggests=$rsuggests";
    close $svs;

}

1
