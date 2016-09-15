#!/usr/bin/env perl

# This script attempts to convert the dependencies of an existing R package
# from using CDBS to use dh-r.
# It should be run from the root of an R package, and will write a new
# d/control file to stdout.
# Note that this completely replaces the existing binary Depends, Recommends,
# Suggests with substvar versions - if your package has dependencies which
# are not either shlibs or R then they will be lost!

use feature say;
use strict;

use Dpkg::Control::Info;
use Dpkg::Deps;

my $ctrl = Dpkg::Control::Info->new();
my $src = $ctrl->get_source();
my $bin = $ctrl->get_pkg_by_idx(1);


$bin->{Depends} = "\${R:Depends}, \${misc:Depends}, \${shlibs:Depends}";
if (defined $bin->{Recommends}) {
    $bin->{Recommends} = "\${R:Recommends}";
}
if (defined $bin->{Suggests}) {
    $bin->{Suggests} = "\${R:Suggests}";
}

my @bdeps = Dpkg::Deps::deps_parse($src->{"Build-Depends"})->get_deps();

if (grep(/^cdbs/, @bdeps)) {
    @bdeps = grep {!/^cdbs/} @bdeps;
}

if (! grep(/^dh-r/, @bdeps)) {
    push (@bdeps, "dh-r");
}

$src->{"Build-Depends"} = Dpkg::Deps::deps_concat(@bdeps);

say $ctrl->output();
