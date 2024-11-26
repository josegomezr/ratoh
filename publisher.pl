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
        config_file => shift (@ARGV) // './Config.pm'
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

    return $mq;
}


my $args = arg_parse();

my $cfg_file_path = $args->{config_file};
die("Config file $cfg_file_path does not exist.") unless -e $cfg_file_path;

my $cfg_code = "package Ratoh::Config::Sandbox;";
$cfg_code .= Mojo::File->new($cfg_file_path)->slurp();
my $config = eval($cfg_code); ## no critic

die qq{Can't load configuration from file "$cfg_file_path": $@} if $@;
die qq{Configuration file "$cfg_file_path" did not return a hash reference} unless ref $config eq 'HASH';


$log->info('Connecting');
my $mq = connect_to_rabbitmq($config->{rabbit_mq});

$mq->publish($config->{rabbit_mq}->{conn_params}->{channel}, 'my.message', Mojo::JSON::encode_json({a => 'b'}), { exchange => $config->{rabbit_mq}->{conn_params}->{exchange} });
print $@;
$mq->disconnect();

$log->info('Ra-to-H Ends!');
