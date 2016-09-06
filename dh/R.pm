# A debhelper build system for R

package Debian::Debhelper::Buildsystem::R;

use feature say;
use strict;
use Cwd;
use Dpkg::Control;
use Dpkg::Control::Info;
use Dpkg::Changelog::Parse;
use Debian::Debhelper::Dh_Lib;
use Dpkg::Deps qw(deps_concat);
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

sub parse_description {
    my $desc = Dpkg::Control->new(type => Dpkg::Control::CTRL_UNKNOWN);
    $desc->load("DESCRIPTION");
    return $desc;
}

sub parse_depends {
    # try and convert R package dependencies in DESCRIPTION into a
    # list of debian package dependencies

    my $field = shift;
    my $rawtext = shift;
    my %apthash = %{shift()};
    my @text = split(/,\s*/, $rawtext);
    my @deps;

    foreach my $dep (@text) {
        chomp $dep;

        # clean up possible newline or tabs in the middle of dependencies
        $dep =~ s/[\n\t]/ /g;
        # rely on the R version format being equivalent
        $dep =~ /^([\w.]+)\s*(\([^()]*\))?$/;
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

    my $desc = parse_description(); # key-value hash for the DESCRIPTION file
    my $srcctrl = Dpkg::Control::Info->new()->get_source();
    my $sourcepackage = $this->sourcepackage();


    say "I: R Package: $desc->{Package} Version: $desc->{Version}";

    # Priority: Recommended should go in /library instead of /site-library
    my $libdir = "usr/lib/R/site-library";
    if ($desc->{Priority} eq "Recommended") {
        $libdir = "usr/lib/R/library";
        say "I: R package with Priority: $desc->{Priority}, installing in $libdir";
    }

    my $repo = "CRAN";
    if (defined $ENV{RRepository}) {
        $repo = $ENV{RRepository};
        say "I: Using repo=$repo from env RRepository";
    } elsif (length $desc->{Repo}) {
        # this appears to be set ("CRAN") for packages originating from CRAN,
        # but is not set for bioconductor, nor for packages direct from upstream
        $repo = $desc->{Repo};
        say "I: Using repo=$repo from DESCRIPTION::Repository";
    } elsif (length $desc->{biocViews}) {
        # however, biocViews is (presumably) only going to be set for bioconductor
        # packages, so nonzero should identify
        $repo = "BIOC";
        say "I: Using repo=$repo due to existence of DESCRIPTION::biocViews";
    } elsif ($sourcepackage =~ /^r-cran/) {
        $repo = "CRAN";
        say "I: Using repo=$repo based on source package name";
    } elsif ($sourcepackage =~ /^r-bioc/) {
        $repo = "BIOC";
        say "I: Using repo=$repo based on source package name";
    } else {
        say "I: Using repo=$repo by default";
    }


    # this is used to determine the install directory during build
    # TODO: check this actually matches the binary name in d/control?
    my $debname = "r-" . lc($repo) . "-" . lc($desc->{Package});
    say "I: Using debian package name: $debname";

    chomp(my $rbase_version = qx/dpkg-query -W -f='\${Version}' r-base-dev/);
    say "I: Building using R version $rbase_version";

    chomp(my $rapi_version = qx/dpkg-query -W -f='\${Provides}' r-base-core | grep -o 'r-api[^, ]*'/);
    say "I: R API version: $rapi_version";

    my $changelog_time = Dpkg::Changelog::Parse::changelog_parse()->{Date};
    say "I: Using built-time from d/changelog: $changelog_time";


    $this->doit_in_sourcedir("mkdir", "-p", "$destdir/$libdir");

    my @instargs;
    if (defined $ENV{RMakeFlags}) {
        say "I: Using MAKEFLAGS=" . $ENV{RMakeFlags};
        push (@instargs, "MAKEFLAGS=" . $ENV{RMakeFlags});
    } else {
        chomp(my $ldflags = qx/dpkg-buildflags --get LDFLAGS/);
        $ldflags =~ s/ /\\ /g;
        $ENV{MAKEFLAGS} = "'LDFLAGS=$ldflags'";
        say "I: Using MAKEFLAGS=$ENV{MAKEFLAGS}";
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
        if (-e "$destdir/$libdir/$desc->{Package}/$rmf") {
            $this->doit_in_sourcedir("rm", "-f", "$destdir/$libdir/$desc->{Package}/$rmf");
        }
    }

    # get all available r-* packages from which we can guess dependencies
    my @aptavail = qx/grep-aptavail -P -s Package -n -e ^r-/;
    my %apthash;
    @apthash{@aptavail} = ();

    my $rdepends = deps_concat(parse_depends("Depends", $desc->{Depends}, \%apthash));
    my $rrecommends = deps_concat(parse_depends("Recommends", $desc->{Recommends}, \%apthash));
    my $rsuggests = deps_concat(parse_depends("Suggests", $desc->{Suggests}, \%apthash));
    my $rimports = deps_concat(parse_depends("Imports", $desc->{Imports}, \%apthash));

    open(my $svs, ">>", "debian/$sourcepackage.substvars");
    my $depends = deps_concat("r-base-core (>= $rbase_version)", $rapi_version, $rdepends, $rimports);
    say $svs "R:Depends=$depends";
    say $svs "R:Recommends=$rrecommends";
    say $svs "R:Suggests=$rsuggests";
    close $svs;

}

1
