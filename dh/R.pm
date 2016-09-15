# A debhelper build system for R

package Debian::Debhelper::Buildsystem::R;

use feature say;
use strict;
use Cwd;
use Dpkg::Control;
use Dpkg::Control::Info;
use Dpkg::Changelog::Parse;
use Debian::Debhelper::Dh_Lib;
use Dpkg::Deps qw(deps_concat deps_parse);
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
    my @rdeps = deps_parse($rawtext)->get_deps();
    my @deps;

    # r namespaces included in r-base-core which we shouldn't try and
    # generate dependencies for
    my %builtins;
    @builtins{qw/base compiler datasets grDevices graphics grid methods
                 parallel splines stats tcltk tools translations utils/} = ();

    foreach my $d (@rdeps) {
        if (exists $builtins{$d->{package}}) {
            # ignore dependencies on built-in namespaces
            next;
        }

        my $pkg = lc $d->{package};
        my $vers = "";
        if (length $d->{version}) {
            $vers = " ($d->{relation} $d->{version})";
        }
        if ($pkg eq "r") {
            # TODO: check if the available version of R satisfies this
            # for now, discard it, since we generate R (>= curver)
            say "W: Ignoring specified R dependency: $d";
            next;
        }

        # check if r-cran-pkg or r-bioc-pkg exists, and add it as a
        # dependency (or recommend/suggest)
        if (exists $apthash{"r-cran-$pkg\n"}) {
            say "I: Using r-cran-$pkg for $field:$d";
            push (@deps, "r-cran-$pkg$vers");
        } elsif (exists $apthash{"r-bioc-$pkg\n"}) {
            say "I: Using r-bioc-$pkg for $field:$d";
            push (@deps, "r-bioc-$pkg$vers");
        } else {
            say "W: Cannot find a debian package for $field:$d";
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
