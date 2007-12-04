use inc::Module::Install;
name 'POE-Component-SmokeBox-Recent';
author 'Chris Williams <chris@bingosnet.co.uk>';
license 'perl';
version_from 'lib/POE/Component/SmokeBox/Recent.pm';
abstract_from 'lib/POE/Component/SmokeBox/Recent.pm';
build_requires 'Test::More' => 0.47;
requires 'Carp' => 0;
requires 'URI' => 0;
requires 'HTTP::Request' => 0;
requires 'POE' => 0.38;
requires 'POE::Component::Client::HTTP' => 0.82;
requires 'POE::Component::Client::FTP' => 0.10;
clean_files 'network.tests';
my $value = prompt( 'Do you want live network tests [N/y]?', 'N' );
if ( $value =~ /^y$/i ) {
  open FH, "> network.tests" or die "$!\n";
  print FH "Bleh\n";
  close FH;
}
WriteAll();
