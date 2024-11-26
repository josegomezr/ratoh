Ratoh 🐁
========

**Ra**bbitMQ-**to**-**H**ttp bridge.

It listens to a RabbitMQ bus, and forwards messages as HTTP Requests.

Usage
-----

Create a `Config.pm`, see the sample file for details. Then run:

```bash
# or just copy the sample with: cp Config.pm{.sample,}
perl main.pl Config.pm
```

And wait for the requests in your HTTP server ✨

Testing
-------

Have a RabbitMQ server available, if not, here's a container to the rescue:
```
docker run --rm -it -p 5672:5672 rabbitmq:3
```

It'll have by default the following exchanges:

```
amq.fanout	fanout
amq.topic	topic
amq.direct	direct
```

Adjust your `Config.pm` to use the exchange of your choice, this project was
born out of listening to `topic` exchanges.

Alongisde the project is also provided `devel_server.pl`, a mojolicious minimal
HTTP echo server. That coincidentally just works with the sample endpoints
config.

```bash
# Start the server at 127.0.0.1:3000
perl devel_server.pl daemon
```

Now with all services up, send messages with the `publisher.pl`:

```
bash publisher.pl
```

Dependencies
------------
- Perl >= v5.26
- [Mojolicious](https://mojolicious.org/), specifically `Mojo::Base`, `Mojo::UserAgent`, `Mojo::URL`, `Mojo::Log`, `Mojo::JSON` & `Mojo::Util`
- [`Net::AMQP::RabbitMQ`](https://metacpan.org/pod/Net::AMQP::RabbitMQ)

Naming
------

_Ratoh_ is similar "Ratón" (🐭) or "Rato" (undefined timespan between 2 minutes
 and 3 weeks in latin america).
