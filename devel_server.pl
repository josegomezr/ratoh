#!/usr/bin/env perl -w

use Mojolicious::Lite -signatures;
use Mojo::Util qw(dumper);

sub echo_req {
  my ($c) = @_;
  my $path = $c->req->url->path;
  my $headers = dumper($c->req->headers->to_hash);
  my $body = $c->req->body;

  my $resp = (<<~EOF);
  Path: $path
  Headers
  ----
  $headers

  Body:
  -----
  $body
  EOF
  $c->render(text => $resp);
}

# Route with placeholder
any '/*rpath' => \&echo_req;
any '/' => \&echo_req;

# Start the Mojolicious command system
app->start;
