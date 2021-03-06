#!/usr/bin/ruby

# Simple tester that runs a record and just dumps the result to stdout in a way
# that is for now readable enough, we'll make it prettier soon.

require 'pdns.rb'
require 'getoptlong'

opts = GetoptLong.new(
    [ '--record', '-r', GetoptLong::REQUIRED_ARGUMENT],
    [ '--type', '-t', GetoptLong::REQUIRED_ARGUMENT],
    [ '--remoteip', GetoptLong::REQUIRED_ARGUMENT],
    [ '--config', '-c', GetoptLong::REQUIRED_ARGUMENT]
)

conffile = "/etc/pdns/pdns-ruby-backend.cfg"
record = nil
type = :ANY
remoteip = "127.0.0.1"
localip = "127.0.0.1"

opts.each do |opt, arg|
    case opt
        when '--type'
            type = arg.to_sym
        when '--record'
            record = arg
        when '--remoteip'
            remoteip = arg
        when '--config'
            conffile = arg
    end
end


runner = Pdns::Runner.new(conffile, "tester")

request = {:qname       => record,
           :qclass      => :IN,
           :qtype       => type,
           :id          => 1,
           :remoteip    => remoteip,
           :localip     => localip}


puts("\nResponse for #{type.to_s} query on #{record} from #{remoteip}")
puts

begin
    response = runner.resolver.do_query(request)
    puts response
rescue Exception => e
    puts e 
end

# vi:tabstop=4:expandtab:ai:filetype=ruby
