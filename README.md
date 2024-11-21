Ratoh
=====

**Ra**bbitMQ-**to**-**H**ttp bridge.

It listens to a RabbitMQ bus, and forwards messages as HTTP Requests.

Usage:

Create a `Config.pm`, see the sample file for details. Then run:

```bash
perl main.pl
```

And wait for the requests in your HTTP server ✨

Testing
----

Alongisde is provided `devel_server.ru`, a ruby rackup minimal HTTP echo server.

```bash
# Start the server at 127.0.0.1:9292
rackup devel_server.ru
```


Naming
------

_Ratoh_ looks like "Ratón" (🐭) or "Rato" (undefined timespan between 2 minutes
 and 3 weeks in latin america).
