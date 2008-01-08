package POE::Component::SmokeBox::Recent;

use strict;
use Carp;
use POE qw(Component::Client::HTTP Component::Client::FTP);
use URI;
use HTTP::Request;
use File::Spec;
use vars qw($VERSION);

$VERSION = '0.03';

sub recent {
  my $package = shift;
  my %opts = @_;
  $opts{lc $_} = delete $opts{$_} for keys %opts;
  croak "$package requires a 'url' argument\n" unless $opts{url};
  croak "$package requires an 'event' argument\n" unless $opts{event};
  my $options = delete $opts{options};
  my $self = bless \%opts, $package;
  $self->{uri} = URI->new( $self->{url} );
  croak "url provided is of an unsupported scheme\n" 
	unless $self->{uri}->scheme and $self->{uri}->scheme =~ /^(ht|f)tp$/;
  $self->{session_id} = POE::Session->create(
	object_states => [
	   $self => [ qw(_start _process_http _process_ftp _recent _http_response) ],
	   $self => { connect_error => '_connect_error',
		      login_error   => '_login_error', 
		      get_error     => '_get_error',
		      authenticated => '_authenticated',
		      get_data      => '_get_data',
		      get_done      => '_get_done', },
	],
	heap => $self,
	( ref($options) eq 'HASH' ? ( options => $options ) : () ),
  )->ID();
  return $self;
}

sub _start {
  my ($kernel,$sender,$self) = @_[KERNEL,SENDER,OBJECT];
  $self->{session_id} = $_[SESSION]->ID();
  if ( $kernel == $sender and !$self->{session} ) {
	croak "Not called from another POE session and 'session' wasn't set\n";
  }
  my $sender_id;
  if ( $self->{session} ) {
    if ( my $ref = $kernel->alias_resolve( $self->{session} ) ) {
	$sender_id = $ref->ID();
    }
    else {
	croak "Could not resolve 'session' to a valid POE session\n";
    }
  }
  else {
    $sender_id = $sender->ID();
  }
  if ( $self->{http_alias} ) {
     my $http_ref = $kernel->alias_resolve( $self->{http_alias} );
     $self->{http_id} = $http_ref->ID() if $http_ref;
  }
  $kernel->refcount_increment( $sender_id, __PACKAGE__ );
  $self->{sender_id} = $sender_id;
  $kernel->yield( '_process_' . $self->{uri}->scheme );
  return;
}

sub _recent {
  my ($kernel,$self,$type) = @_[KERNEL,OBJECT,ARG0];
  my $target = delete $self->{sender_id};
  my %reply;
  $reply{recent} = delete $self->{recent} if $self->{recent};
  $reply{error} = delete $self->{error} if $self->{error};
  $reply{context} = delete $self->{context} if $self->{context};
  $reply{url} = delete $self->{url};
  my $event = delete $self->{event};
  $kernel->post( $target, $event, \%reply );
  $kernel->refcount_decrement( $target, __PACKAGE__ );
  $kernel->post( $self->{http_id}, 'shutdown' ) if $type eq 'http' and !$self->{http_alias}; 
  return;
}

sub _process_http {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  unless ( $self->{http_id} ) {
    $self->{http_id} = 'smokeboxhttp' . $$ . $self->{session_id};
    POE::Component::Client::HTTP->spawn(
	Alias     => $self->{http_id},
	FollowRedirects => 2,
    );
  }
  $self->{uri}->path( File::Spec::Unix->catfile( $self->{uri}->path(), 'RECENT' ) );
  $kernel->post( $self->{http_id}, 'request', '_http_response', 
	HTTP::Request->new(GET => $self->{uri}->as_string()),
	$self->{session_id} );
  return;
}

sub _http_response {
  my ($kernel,$self,$request_packet,$response_packet) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my $response = $response_packet->[0];
  if ( $response->code() == 200 ) {
    for ( split /\n/, $response->content() ) {
       next unless /^authors/;
       next unless /\.(tar\.gz|tgz|tar\.bz2|zip)$/;
       s!authors/id/!!;
       push @{ $self->{recent} }, $_;
    }
  }
  else {
    $self->{error} = $response->as_string();
  }
  $kernel->yield( '_recent', 'http' );
  return;
}

sub _process_ftp {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  POE::Component::Client::FTP->spawn(
        Alias => 'ftpclient' . $self->{session_id},
        Username => 'anonymous',
        Password => 'anon@anon.org',
        RemoteAddr => $self->{uri}->host,
        Events => [qw(connect_error login_error get_error authenticated get_data get_done)],
        Filters => { get => POE::Filter::Line->new(), },
  );
  return;
}

sub _connect_error {
  my ($kernel,$self,@args) = @_[KERNEL,OBJECT,ARG0..$#_];
  $self->{error} = join ' ', @args;
  $kernel->yield( '_recent', 'ftp' );
  return;
}

sub _login_error {
  my ($kernel,$self,$sender,@args) = @_[KERNEL,OBJECT,SENDER,ARG0..$#_];
  $self->{error} = join ' ', @args;
  $kernel->post( $sender, 'quit' );
  $kernel->yield( '_recent', 'ftp' );
  return;
}

sub _get_error {
  my ($kernel,$self,$sender,@args) = @_[KERNEL,OBJECT,SENDER,ARG0..$#_];
  $self->{error} = join ' ', @args;
  $kernel->post( $sender, 'quit' );
  $kernel->yield( '_recent', 'ftp' );
  return;
}

sub _authenticated {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  $kernel->post( $sender, 'get', File::Spec::Unix->catfile( $self->{uri}->path, 'RECENT' ) );
  return;
}

sub _get_data {
  my ($kernel,$self,$data) = @_[KERNEL,OBJECT,ARG0];
  return unless $data =~ /^authors/i;
  return unless $data =~ /\.(tar\.gz|tgz|tar\.bz2|zip)$/;
  $data =~ s!authors/id/!!;
  push @{ $self->{recent} }, $data;
  return;
}

sub _get_done {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  $kernel->post( $sender, 'quit' );
  $kernel->yield( '_recent', 'ftp' );
  return;
}

1;
__END__

=head1 NAME

POE::Component::SmokeBox::Recent - A POE component to retrieve recent CPAN uploads.

=head1 SYNOPSIS

  use strict;
  use POE qw(Component::SmokeBox::Recent);

  $|=1;

  POE::Session->create(
	package_states => [
	  'main' => [qw(_start recent)],
	],
  );

  $poe_kernel->run();
  exit 0;

  sub _start {
    POE::Component::SmokeBox::Recent->recent( 
	url => 'http://www.cpan.org/',
	event => 'recent',
    );
    return;
  }

  sub recent {
    my $hashref = $_[ARG0];
    if ( $hashref->{error} ) {
	print $hashref->{error}, "\n";
	return;
    }
    print $_, "\n" for @{ $hashref->{recent} };
    return;
  }

=head1 DESCRIPTION

POE::Component::SmokeBox::Recent is a L<POE> component for retrieving recently uploaded CPAN distributions 
from the CPAN mirror of your choice.

It accepts a url and an event name and attempts to download and parse the RECENT file from that given url.

It is part of the SmokeBox toolkit for building CPAN Smoke testing frameworks.

=head1 CONSTRUCTOR

=over

=item recent

Takes a number of parameters:

  'url', the full url of the CPAN mirror to retrieve the RECENT file from, only http and ftp are currently supported, mandatory;
  'event', the event handler in your session where the result should be sent, mandatory;
  'session', optional if the poco is spawned from within another session;
  'context', anything you like that'll fit in a scalar, a ref for instance;

The 'session' parameter is only required if you wish the output event to go to a different
session than the calling session, or if you have spawned the poco outside of a session.

The poco does it's work and will return the output event with the result.

=back

=head1 OUTPUT EVENT

This is generated by the poco. ARG0 will be a hash reference with the following keys:

  'recent', an arrayref containing recently uploaded distributions; 
  'error', if something went wrong this will contain some hopefully meaningful error messages;
  'context', if you supplied a context in the constructor it will be returned here;

=head1 AUTHOR

Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

=head1 KUDOS

Andy Armstrong for helping me to debug accessing his CPAN mirror. 

=head1 SEE ALSO

L<POE>

L<http://cpantest.grango.org/>

L<POE::Component::Client::HTTP>

L<POE::Component::Client::FTP>

=cut
