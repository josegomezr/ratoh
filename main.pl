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

my $log = Mojo::Log->new(level => $ENV{RATO_LOG} // 'debug');

# TODO: properly do argparse here.
sub arg_parse {
    return {
        config_file => shift (@ARGV) // './Config.pm'
    }
}

sub send_http_request {
    my ($target, $body) = @_;
    my $url = $target->{url};
    my $pointer = Mojo::JSON::Pointer->new($body);

    do { } while ($url =~ s!%\{([^\}]+)\}%!($pointer->get($1)//"-broken:$1-broken-")!ge);

    $url = Mojo::URL->new($url);
    my $method = $target->{method} // 'get';
    my $ua = Mojo::UserAgent->new();
    my $tx = $ua->build_tx($method => $url => {}, json => $body);
    $tx->req->headers->user_agent('RaToH/1.0.0');
    # Apply pre-request changes
    $target->{pre_request}->($tx->req) if is_subroutine($target->{pre_request});

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

sub notify_targets {
    my ($targets, $message) = @_;
    foreach my $target_name (keys $targets->%*) {
        my $log = $log->context($target_name, $message->{routing_key}, $message->{consumer_tag});

        $log->info("START - Notifying target");

        my $target = $targets->{$target_name};
        my $body = $message->{body};
        my $body_parser = $target->{body_parser} // 'PARSE_JSON';

        if ($body_parser eq 'PARSE_JSON') {
            eval { $body = Mojo::JSON::decode_json($message->{body}) };
        } elsif (is_subroutine $target->{body_parser}) {
            # or do something arbitrary...
            eval { $body = $target->{body_parser}->($body, $message) };
        }

        if ($@) {
            $log->trace("Falling back to empty json body, JSON Parsing broke with: $@");
            $body = {};
        }

        $message->{body} = $body;

        if (is_subroutine($target->{message_filter}) && !$target->{message_filter}->($message)) {
            $log->trace("Message was filtered out, skipping target");
            goto END_NOTIFICATION_LOOP;
        }

        my $response = send_http_request($target, $message);
        my $resp_code = $response->{status_code};
        if (is_http_status_error($resp_code) && is_subroutine($target->{on_error})) {
            $log->debug("Calling error handler");
            $target->{on_error}->($response, $message);
        }

      END_NOTIFICATION_LOOP:
        $log->info("DONE - Notifying target");
    }
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
my $config = eval($cfg_code);

die qq{Can't load configuration from file "$cfg_file_path": $@} if $@;
die qq{Configuration file "$cfg_file_path" did not return a hash reference} unless ref $config eq 'HASH';

my $targets = $config->{endpoints};

my $mq = connect_to_rabbitmq($config->{rabbit_mq});

$log->info('Ra-to-H Starts!');

while (my $message = $mq->recv(0)) {
    $log->trace('Incoming message: ' . Mojo::Util::dumper($message));
    notify_targets($targets, $message);
}

$log->info('Disconnecting');
$log->info('Ra-to-H Ends!');

$mq->disconnect();
