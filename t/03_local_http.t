use strict;
use warnings;
use Test::More tests => 5;
use POE qw(Component::SmokeBox::Recent Filter::Stream);
use Test::POE::Server::TCP;

my $recent = <<RECENTFILE;
200 OK HTTP/1.1
Connection: close
Content-Length: 969
Content-Type: text/plain

MIRRORING.FROM
RECENT
RECENT.html
authors/00whois.html
authors/00whois.xml
authors/01mailrc.txt.gz
authors/02STAMP
authors/RECENT-1M.yaml
authors/RECENT-1Q.yaml
authors/RECENT-1W.yaml
authors/RECENT-1d.yaml
authors/RECENT-1h.yaml
authors/RECENT-6h.yaml
authors/id/A/AA/AAU/MRIM/CHECKSUMS
authors/id/A/AA/AAU/MRIM/Net-MRIM-1.10.meta
authors/id/A/AA/AAU/MRIM/Net-MRIM-1.10.tar.gz
authors/id/A/AD/ADAMK/CHECKSUMS
authors/id/A/AD/ADAMK/ORLite-1.17.meta
authors/id/A/AD/ADAMK/ORLite-1.17.readme
authors/id/A/AD/ADAMK/ORLite-1.17.tar.gz
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.06.meta
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.06.readme
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.06.tar.gz
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.07.meta
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.07.readme
authors/id/A/AD/ADAMK/Test-NeedsDisplay-1.07.tar.gz
authors/id/A/AD/ADAMK/YAML-Tiny-1.36.meta
authors/id/A/AD/ADAMK/YAML-Tiny-1.36.readme
authors/id/A/AD/ADAMK/YAML-Tiny-1.36.tar.gz
RECENTFILE

my @tests = qw(
A/AA/AAU/MRIM/Net-MRIM-1.10.tar.gz
A/AD/ADAMK/ORLite-1.17.tar.gz
A/AD/ADAMK/Test-NeedsDisplay-1.06.tar.gz
A/AD/ADAMK/Test-NeedsDisplay-1.07.tar.gz
A/AD/ADAMK/YAML-Tiny-1.36.tar.gz
);

POE::Session->create(
   package_states => [
        main => [qw(_start _stop testd_registered testd_client_input _recent)],
   ],
);

$poe_kernel->run();
exit 0;

sub _start {
  my $heap = $_[HEAP];
  $heap->{testd} = Test::POE::Server::TCP->spawn(
    filter => POE::Filter::Stream->new,
    address => '127.0.0.1',
  );
  my $port = $heap->{testd}->port;
  $heap->{url} = "http://127.0.0.1:$port/";
  return;
}

sub _stop {
  pass('Everything has stopped');
  return;
}

sub testd_registered {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  POE::Component::SmokeBox::Recent->recent(
      url => $heap->{url},
      event => '_recent',
      context => 'Blah Blah Blah',
  );
  return;
}

sub testd_client_input {
  my ($kernel, $heap, $id, $input) = @_[KERNEL, HEAP, ARG0, ARG1];
  diag($input);
  pass('Got a recent file request');
  $heap->{testd}->send_to_client($id, $recent);
  return;
}

sub _recent {
  my ($heap,$hashref) = @_[HEAP,ARG0];
  ok( $hashref->{recent}, 'We got a RECENT listing' );
  is_deeply( $hashref->{recent}, \@tests, 'What we got matched' );
  ok( $hashref->{context} eq 'Blah Blah Blah', 'Context was okay' );
  $heap->{testd}->shutdown();
  delete $heap->{testd};
  return;
}
