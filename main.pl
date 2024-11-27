#!/usr/bin/perl -w

use Mojo::Base -strict;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::File;
use Mojo::Log;
use Mojo::JSON;
use Mojo::Util;
use Net::AMQP::RabbitMQ;
use Data::Dumper;

my $log = Mojo::Log->new(level => $ENV{RATOH_LOG} // 'debug');

# TODO: properly do argparse here.
sub arg_parse {
    return {
        config_file => shift(@ARGV) // './Config.pm'
    };
}

sub send_http_request {
    my ($endpoint, $body) = @_;
    my $url = $endpoint->{url};
    my $pointer = Mojo::JSON::Pointer->new($body);

    do { } while ($url =~ s!%\{([^\}]+)\}%!($pointer->get($1)//"-broken:$1-broken-")!ge);

    $url = Mojo::URL->new($url);
    my $method = $endpoint->{method} // 'get';
    my $ua = Mojo::UserAgent->new();
    my $tx = $ua->build_tx($method => $url => {}, json => $body);
    $tx->req->headers->user_agent('RaToH/1.0.0');
    # Apply pre-request changes
    $endpoint->{pre_request}->($tx->req) if is_subroutine($endpoint->{pre_request});

    $tx = $ua->start($tx);

    return {
        remote_addr => $tx->remote_address,
        status_code => $tx->res->code,
        body => $tx->res->body,
        headers => $tx->res->headers->to_hash()
    };
}

sub is_subroutine {
    my ($rt) = @_;
    return (defined $rt) && (ref($rt) eq 'CODE');
}

sub is_http_status_error {
    my ($status) = @_;
    return $status && ($status < 200 || $status > 299);
}

sub notify_endpoint {
    my ($endpoint, $message) = @_;
    $log->info("START - Notifying endpoint");

    my $body = $message->{body};
    my $body_parser = $endpoint->{body_parser} // 'PARSE_JSON';

    if ($body_parser eq 'PARSE_JSON') {
        eval { $body = Mojo::JSON::decode_json($message->{body}) };
    } elsif (is_subroutine $endpoint->{body_parser}) {
        # or do something arbitrary...
        eval { $body = $endpoint->{body_parser}->($body, $message) };
    }

    if ($@) {
        $log->trace("Falling back to empty json body, JSON Parsing broke with: $@");
        $body = {};
    }

    $message->{body} = $body;

    if (is_subroutine($endpoint->{message_filter}) && !$endpoint->{message_filter}->($message)) {
        $log->trace("Message was filtered out, skipping endpoint");
        goto END_NOTIFICATION_LOOP;
    }

    my $response = send_http_request($endpoint, $message);
    my $resp_code = $response->{status_code};
    if (is_http_status_error($resp_code) && is_subroutine($endpoint->{on_error})) {
        $log->debug("Calling error handler");
        $endpoint->{on_error}->($response, $message);
    }

  END_NOTIFICATION_LOOP:
    $log->info("DONE - Notifying endpoint");
}

sub connect_to_rabbitmq {
    my ($config) = @_;
    my $mq = Net::AMQP::RabbitMQ->new();
    $config->{conn_params}->{port} //= ($config->{conn_params}->{ssl} ? 5671 : 5672);
    $config->{conn_params}->{queue} //= '';
    $log->info('Connecting to RabbitMQ: ' . $config->{host});
    $log->trace('Connection information: ' . Mojo::Util::dumper(
            {
                user => $config->{conn_params}->{user},
                queue => $config->{conn_params}->{queue},
                channel => $config->{conn_params}->{channel},
                exchange => $config->{conn_params}->{exchange},
                routing_key => $config->{conn_params}->{routing_key},
            }
        )
    );

    $mq->connect($config->{host}, $config->{conn_params});

    $log->trace('Opening channel');
    $mq->channel_open($config->{conn_params}->{channel});

    $log->trace('Declaring queue');
    my $queuename = $mq->queue_declare(1, $config->{conn_params}->{queue});

    $log->info('Binding to queue: ' . $queuename);
    $mq->queue_bind($config->{conn_params}->{channel}, $queuename, $config->{conn_params}->{exchange}, $config->{conn_params}->{routing_key});
    $mq->consume($config->{conn_params}->{channel}, $queuename);

    return $mq;
}


my $args = arg_parse();

my $cfg_file_path = $args->{config_file};
die("Config file $cfg_file_path does not exist.") unless -e $cfg_file_path;

my $cfg_code = "package Ratoh::Config::Sandbox;";
$cfg_code .= Mojo::File->new($cfg_file_path)->slurp();
my $config = eval($cfg_code);    ## no critic

die qq{Can't load configuration from file "$cfg_file_path": $@} if $@;
die qq{Configuration file "$cfg_file_path" did not return a hash reference} unless ref $config eq 'HASH';

my $endpoint = $config->{endpoint};

$log->info('Ra-to-H Starts!');

my $retries = 10;

while (1) {
    my $mq;
    eval { $mq = connect_to_rabbitmq($config->{rabbit_mq}) };
    if ($@) {
        $log->error("Error on connection: $@");
        $log->error("Too many errors, bailing out.") and break if $retries == 0;

        $retries--;
        $log->info('Retrying in 5 seconds...');
        sleep 5 and next;
    }
    $retries = 10;

    $log->info('Connected! Awaiting for messages...');

    while (my $message = eval { $mq->recv(0) }) {
        $log->trace('Incoming message: ' . Mojo::Util::dumper($message));
        notify_endpoint($endpoint, $message);
    }

    if ($@) {
        $log->error("Error while connected: $@");
        # Disconect and send to connection routine above.
        $mq->disconnect() and next;
    }
}

$log->info('Ra-to-H Ends!');
