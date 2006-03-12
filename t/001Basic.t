#####################################
# WWW::Mechanize::Plugin::phpBB Tests
#####################################

use Test::More tests => 1;

BEGIN { use_ok('WWW::Mechanize::Pluggable') };

my $mech = WWW::Mechanize::Pluggable->new();
