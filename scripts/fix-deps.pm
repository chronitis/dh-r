use feature say;
use strict;

use Dpkg::Control::Info;
use Dpkg::Deps;

my $ctrl = Dpkg::Control::Info->new();
my $src = $ctrl->get_source();
my $bin = $ctrl->get_pkg_by_idx(1);


$bin->{Depends} = Dpkg::Deps::deps_concat("\${R:Depends}", "\${misc:Depends}", "\${shlib:Depends}");
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


