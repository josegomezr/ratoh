#!/usr/bin/perl -w

use Mojo::Base -strict;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::Log;
use Mojo::JSON;
use Mojo::Util;
use Net::AMQP::RabbitMQ;
use Data::Dumper;


require "./Config.pm"; ## no critic

my $log = Mojo::Log->new;
my $cfg = Ratoh::Config::rabbitmq_settings();
my $targets = Ratoh::Config::targets();

sub send_http_request {
	my ($target, $body) = @_;
	my $url = $target->{url};
	my $pointer = Mojo::JSON::Pointer->new($body);

	while ($url =~ s!%\{([^\}]+)\}%!($pointer->get($1)//"-broken:$1-")!ge) {}

	$url = Mojo::URL->new($url);
	my $method = $target->{method} // 'get';

	my $ua = Mojo::UserAgent->new();

	my $tx = $ua->build_tx($method => $url => {}, json => $body);

	if ($target->{pre_request}){
		$target->{pre_request}->($tx->req);
	}
	$tx = $ua->start($tx);

	return {
		remote_addr => $tx->remote_address,
		status_code => $tx->res->code,
		body => $tx->res->body,
		headers => $tx->res->headers->to_hash()
	}
}

sub is_subroutine {
  my $rt = shift;
  return defined $rt and reftype($rt) eq 'CODE'
}

sub notify_targets {
	my ($targets, $message) = @_;
	foreach	my $target_name (keys $targets->%*) {
		$log->info(sprintf("[%s] Notifying %s", $message->{consumer_tag}, $target_name));

		my $target = $targets->{$target_name};
		my $body = $message->{body};
		my $body_parser = $target->{body_parser} // 'PARSE_JSON';

		if($target->{body_parser} eq 'PARSE_JSON'){
			eval { $body = Mojo::JSON::decode_json($message->{body}) };
		}elsif (is_subroutine $target->{body_parser}){
			# or do something arbitrary...
			eval { $body = $target->{body_parser}->($body, $message) };
		}

		if($@) {
			$log->info(sprintf("[%s] Falling back to empty json body, JSON Parsing broke with: %s", $message->{consumer_tag}, $@));
			$body = {};
		}

		$message->{body} = $body;

		my $response = send_http_request($target, $message);
		if (($response->{status_code} < 200 || $response->{status_code} > 299) && is_subroutine($target->{on_error})) {
			$log->info(sprintf("[%s] Calling error handler on %s", $message->{consumer_tag}, $target_name));
			$target->{on_error}->($response, $message);
		}
		# print Dumper($response);
	}
}


my $mq = Net::AMQP::RabbitMQ->new();

$cfg->{conn_params}->{port} //= ($cfg->{conn_params}->{ssl} ? 5671 : 5672);
$cfg->{conn_params}->{queue} //= '';
$log->info('Connecting to RabbitMQ: ' . Mojo::Util::dumper({
		host => $cfg->{host},
		user => $cfg->{conn_params}->{user},
		queue => $cfg->{conn_params}->{queue},
		channel => $cfg->{conn_params}->{channel},
		exchange => $cfg->{conn_params}->{exchange},
		routing_key => $cfg->{conn_params}->{routing_key},
}) );

$mq->connect($cfg->{host}, $cfg->{conn_params});

$log->info('Opening channel');
$mq->channel_open($cfg->{conn_params}->{channel});

$log->info('Binding to queue');
my $queuename = $mq->queue_declare(1, $cfg->{conn_params}->{queue});
$mq->queue_bind($cfg->{conn_params}->{channel}, $queuename, $cfg->{conn_params}->{exchange}, $cfg->{conn_params}->{routing_key});
$mq->consume($cfg->{conn_params}->{channel}, $queuename);

$log->info('Start consuming');
while ( my $message = $mq->recv(0) )
{
	$log->debug('Incoming message: ' . Mojo::Util::dumper($message));
	notify_targets($targets, $message);
}

$log->info('Disconnecting');
$mq->disconnect();
