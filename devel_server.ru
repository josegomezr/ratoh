# rackup config.ru

require 'cgi'
require 'pp'

run Proc.new {|env|
  headers = env.select{ _1 =~ /^(REQUEST|HTTP|REMOTE)_/ }
  qs = CGI.parse(env["QUERY_STRING"])
  body = env['rack.input'].read

  puts("HEADERS:")
  puts("===")
  pp(headers)

  0.then do
    puts("QUERY STRING:")
    puts("===")
    pp(qs)
  end if qs.size > 0

  0.then do
    puts("BODY:")
    puts("===")
    puts(body)
  end if body.size > 0

  puts("===")
  [400, {}, ['']]
}
