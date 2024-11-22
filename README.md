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

Alongisde is provided `devel_server.ru`, a ruby rackup minimal HTTP echo server.
That coincidentally just works with the sample config.

```bash
# Start the server at 127.0.0.1:9292
rackup devel_server.ru
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
