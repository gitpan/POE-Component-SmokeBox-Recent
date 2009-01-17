use strict;
use warnings;
use Test::More tests => 2;
BEGIN { use_ok( 'POE::Component::SmokeBox::Recent' ); };
BEGIN { use_ok( 'POE::Component::SmokeBox::Recent::FTP' ); };
diag( "Testing POE::Component::SmokeBox::Recent-$POE::Component::SmokeBox::Recent::VERSION, POE-$POE::VERSION, Perl $], $^X" );
