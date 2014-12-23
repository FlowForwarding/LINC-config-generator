.PHONY: compile test run

topology ?= $$PWD/priv/json_example.json
config_template ?= $$PWD/priv/sys.config.template
controller_ip ?= localhost
controller_port ?= 6653

compile:
	./rebar get-deps compile escriptize

test:
	./rebar eunit skip_deps=true
run:
	make && ./config_generator $(topology) $(config_template) \
	$(controller_ip) $(controller_port) \
	&& cat sys.config
