module Pdns
    # The workhorse class for the framework, speads directly to PDNS
    # via STDIN and STDOUT. 
    #
    # It requires your PDNS to speak ABI version 2.
    class Runner
        def initialize(configfile = "/etc/pdns/pipe-backend.cfg")
            STDOUT.sync = true
            STDIN.sync = true
            STDERR.sync = true
        
            @config = Pdns::Config.new(configfile)

            @resolver = Pdns::Resolvers.new

            Pdns.warn("Runner starting")

            load_records

            handshake
            pdns_loop

            Pdns.warn("Runner exiting")
        end

        # load all files ending in .prb from the records dir
        def load_records
            Pdns::Resolvers.empty!

            if File.exists?(@config.records_dir)
                records = Dir.new(@config.records_dir) 
                records.entries.grep(/\.prb$/).each do |r|
                    Pdns.warn("Loading new record from #{@config.records_dir}/#{r}")
                    Kernel.load("#{@config.records_dir}/#{r}")
                end
            else
                raise("Can't find records dir #{@config.records_dir}")
            end

            # store when we last loaded, the main loop will call this
            # methods once a configurable interval 
            @lastrecordload = Time.now
        end

        # Listens on STDIN for messages from PDNS and process them
        def pdns_loop
            STDIN.each do |pdnsinput|
                pdnsinput.chomp!

                Pdns.debug("Got '#{pdnsinput}' from pdns")
                t = pdnsinput.split("\t")

                # Requests like:
                # Q foo.my.net  IN  ANY -1  1.2.3.4 0.0.0.0
                if t.size == 7
                    request = {:qname       => t[1],
                               :qclass      => t[2].to_sym,
                               :qtype       => t[3].to_sym,
                               :id          => t[4],
                               :remoteip    => t[5],
                               :localip     => t[6]}

                    if @resolver.can_answer?(request)
                        Pdns.info("Handling lookup for #{request[:qname]} from #{request[:remoteip]}")

                        begin
                            answers = @resolver.do_query(request)
                        rescue Pdns::UnknownRecord => e
                            Pddns.error("Could not serve request for #{request[:qname]} record was not found")

                            puts("FAIL")
                            next
                        rescue Pdns::RecordCallError => e
                            Pdns.error("Could not serve request for #{request[:qname]} record block failed: #{e}")

                            puts("FAIL")
                            next
                        rescue Exception => e
                            Pdns.error("Got unexpected exception while serving #{request[:qname]}: #{e}")
                            puts("FAIL")
                            next
                        end

                        # Backends are like entire zones, so in the :record type of entry we need to have
                        # an SOA still this really is only to keep PDNS happy so we just fake it in those cases.
                        #
                        # PDNS loves doing ANY requests, it'll do a lot of those even if clients do like TXT only
                        # this is some kind of internal optimisation, not helping us since we dont cache but
                        # so we return SOA in cases where:
                        #
                        # - records type is :record, in future we might support a zone type it would need to do 
                        #   its own SOAs then
                        # - only if we're asked for SOA or ANY records, else we'll confuse things
                        if (@resolver.type(request) == :record) && (request[:qtype] == :SOA || request[:qtype] == :ANY)
                            ans = answers.fudge_soa(@config.soa_contact, @config.soa_nameserver)

                            Pdns.debug(ans)
                            puts ans
                        end

                        # SOA requests should not get anything else than the fudged answer above
                        if request[:qtype] != :SOA
                            answers.response.each do |ans| 
                                Pdns.debug(ans)
                                puts ans
                            end
                        end

                        Pdns.debug("END")
                        puts("END")
                    else
                       Pdns.info("Asked to serve #{request[:qname]} but don't know how")

                       # Send an END and not a FAIL, FAIL results in PDNS sending SERVFAIL to the clients
                       # which is just very retarded, #fail.
                       #
                       # The example in the docs and tarball behaves the same way.
                       puts("END")
                    end
                # requests like: AXFR 1, see issue 5
                elsif t.size == 2
                    Pdns.debug("END")
                    puts("END")
                else
                    Pdns.error("PDNS sent '#{pdnsinput}' which made no sense")
                    puts("FAIL")
                end

                if (Time.now - @lastrecordload) > @config.reload_interval
                    Pdns.info("Reloading records from disk due to reload_interval")
                    load_records
                end
            end
        end

        # Handshakes with PDNS, if PDNS is not set up for ABI version 2 handshake will fail
        # and the backend will exit
        def handshake
            unless STDIN.gets.chomp =~ /HELO\t2/
                Pdns.error("Did not receive an ABI version 2 handshake correctly from pdns")
                puts("FAIL")
                exit
            end

            Pdns.info("Ruby PDNS backend starting with PID #{$$}")

            puts("OK\tRuby PDNS backend starting")
        end
    end
end

# vi:tabstop=4:expandtab:ai:filetype=ruby
