%%%=============================================================================
%%% @author Ramon Lastres <ramon.lastres@erlang-solutions.com>
%%% @doc Code that parses a config file in JSON format and creates a LINC switch
%%% Erlang term part of the sys.config file
%%% Of course it needs to have JSX in the path to work!
%%% @end
%%%=============================================================================
-module(config_generator).

-include_lib("eunit/include/eunit.hrl").

-export([main/1, 
         parse/4]).

-define(PORTS_MAP, ports_map).

%%%=============================================================================
%%% Api functions
%%%=============================================================================

%%%=============================================================================
%%% @doc Takes a file name and returns the 'linc' element that is supposed to 
%%% be part of the sys.config file
%%% @end
%%%=============================================================================

main(Args) ->
  parse(Args).

parse([Filename, FileTemplate, ControllerIP, Port]) ->
  parse(Filename, FileTemplate, ControllerIP, Port).

-spec parse(Filename :: file:name_all(),
            FileTemplate :: file:name_all(),
            ControllerIP :: string(),
            Port :: integer()) -> {linc, [tuple()]}.
parse(Filename, FileTemplate, ControllerIP, Port) ->
    init_port_mapping_ets(),
    {ok, Binary} = file:read_file(Filename),
    {ok, [Config]} = file:consult(FileTemplate),
    Json = jsx:decode(Binary,
                      [{error_handler,
                        fun(RestBin, {decoder, State, _, _, _}, _Config) ->
                                json_error_handler(Filename, Binary, RestBin, State)
                        end}]),
    SwitchConfig = proplists:get_value(<<"switchConfig">>, Json),
    LinkConfig = proplists:get_value(<<"linkConfig">>, Json),
    Linc = generate_linc_element(SwitchConfig, LinkConfig, ControllerIP, Port),
    FinalConfig = [Linc] ++ Config,
    ok = file:write_file("sys.config",io_lib:fwrite("~p.\n", [FinalConfig])).

json_error_handler(Filename, Binary, RestBin, DecoderState) ->
    {ErrorPos, _} = binary:match(Binary, RestBin),
    Newlines = binary:matches(Binary, <<"\n">>, [{scope, {0, ErrorPos}}]),
    LineNo = 1 + length(Newlines),
    case Newlines of
        [] ->
            LastNewlinePos = -1;
        [_|_] ->
            LastNewline = lists:last(Newlines),
            {LastNewlinePos, _} = LastNewline
    end,
    ColNo = ErrorPos - LastNewlinePos,
    io:format(standard_error, "~s:~b:~b: JSON error, decoder state '~p'~n",
              [Filename, LineNo, ColNo, DecoderState]),
    erlang:halt(1).

%%%=============================================================================
%%% Internal Functions
%%%=============================================================================

init_port_mapping_ets() ->
    ets:new(?PORTS_MAP, [named_table]).

map_capable_to_logical_switch_port(CapablePortNo, LogicalPort) ->
    %% Check that we haven't mapped this logical port to something
    %% else already.
    case ets:match(?PORTS_MAP, {'$1', LogicalPort}) of
        [] ->
            true = ets:insert_new(?PORTS_MAP, {CapablePortNo, LogicalPort});
        [_|_] ->
            error({duplicate_port, LogicalPort})
    end.

get_mapping_for_capable_port(LogicalPort) ->
    [[CapablePortNo]] = ets:match(?PORTS_MAP, {'$1', LogicalPort}),
    CapablePortNo.

packet2optical_links(LinkConfig) ->
    lists:filter(fun(X) -> lists:member({<<"type">>, <<"pktOptLink">>}, X) end,
                 LinkConfig).

optical_links(LinkConfig) ->
    lists:filter(fun(X) -> lists:member({<<"type">>, <<"wdmLink">>}, X) end,
                 LinkConfig).

get_logical_switches(SwitchConfig, LinkConfig, ControllerIP, Port) ->
    Dpids = get_switches_dpids(SwitchConfig),
    DpidsToNumber = get_dpids2number(SwitchConfig),
    OpticalLinks = get_optical_links(LinkConfig, SwitchConfig),
    OpticalLinkPorts = get_p2o_links_ports(LinkConfig, SwitchConfig),
    lists:map(fun(X) -> generate_switch_element(X, OpticalLinks,
                                                OpticalLinkPorts, ControllerIP,
                                                Port, DpidsToNumber)
        end, Dpids).

get_switches_dpids(SwitchConfig) ->
    lists:map(fun(X) -> proplists:get_value(<<"nodeDpid">>, X) end,
              SwitchConfig).

get_dpids2number(SwitchConfig) ->
    Dpids = get_switches_dpids(SwitchConfig),
    lists:zip(Dpids, lists:seq(1, length(Dpids))).

%We want the optical port and dpid.
parse_packet2optical_link(P2OLink, SwitchConfig) ->
    Dpids = get_switches_dpids(SwitchConfig),
    DpidsToNumber = get_dpids2number(SwitchConfig),
    Params = proplists:get_value(<<"params">>, P2OLink),
    Dpid1 = proplists:get_value(<<"nodeDpid1">>, P2OLink),
    Dpid2 = proplists:get_value(<<"nodeDpid2">>, P2OLink),
    case lists:member(Dpid1, Dpids) of
        true ->
            {proplists:get_value(Dpid1, DpidsToNumber),
             proplists:get_value(<<"port1">>, Params)};
        _ ->
            {proplists:get_value(Dpid2, DpidsToNumber),
             proplists:get_value(<<"port2">>, Params)}
    end.

parse_optical_link(OpticalLink, DpidsToNumber) ->
    Params = proplists:get_value(<<"params">>, OpticalLink),
    [
      {proplists:get_value(proplists:get_value(<<"nodeDpid1">>, OpticalLink),
                            DpidsToNumber),
        proplists:get_value(<<"port1">>, Params)},
       {proplists:get_value(proplists:get_value(<<"nodeDpid2">>, OpticalLink),
                            DpidsToNumber),
        proplists:get_value(<<"port2">>, Params)}
    ].

get_p2o_links_ports(LinkConfig, SwitchConfig) ->
    lists:map(fun(X) -> parse_packet2optical_link(X, SwitchConfig) end,
              packet2optical_links(LinkConfig)).

get_optical_links(LinkConfig, SwitchConfig) ->
    DpidsToNumber = get_dpids2number(SwitchConfig),
    lists:map(fun(X) -> parse_optical_link(X, DpidsToNumber) end,
              optical_links(LinkConfig)).

get_optical_link_pairs(LinkConfig, SwitchConfig) ->
    DpidsToNumber = get_dpids2number(SwitchConfig),
    lists:map(fun(X) ->
        list_to_tuple(parse_optical_link(X, DpidsToNumber))
    end,optical_links(LinkConfig)).

optical_port_element(LogicalPortsFromOpticalLink,  InitCapablePortNo) ->
    Ports =
        [begin
             {Inc, {_SwId, _LogicalPortNo} = LP} = X,
             CapablePortNo = InitCapablePortNo + Inc,
             map_capable_to_logical_switch_port(CapablePortNo, LP),
             {port, CapablePortNo, [{interface, "dummy"}, {type, optical}]}
         end
         || X <- lists:zip([0,1], LogicalPortsFromOpticalLink)],
    {Ports, InitCapablePortNo + 2}.

p2o_port_element({_SwId, _PortNumber} = LP, CapablePortNo) ->
    map_capable_to_logical_switch_port(CapablePortNo, LP),
    CapablePort = {port, CapablePortNo,
            [{interface, "tap" ++ integer_to_list(CapablePortNo)}]},
    {CapablePort, CapablePortNo + 1}.

get_switch_ports(SwitchDpid, OpticalLinks, P2OLinkPorts) ->
    List = lists:flatten(OpticalLinks ++ P2OLinkPorts),
    [{SwitchDpid, Port} || {Dpid, Port} <- List, Dpid == SwitchDpid].

get_capable_switch_ports(LinkConfig, SwitchConfig) ->
    try
        {OpticalCapablePorts, NextCapablePortNo} =
            lists:mapfoldl(fun optical_port_element/2, _InitCapablePortNo = 1,
                           get_optical_links(LinkConfig, SwitchConfig)),
        {PacketCapablePorts, _} =
            lists:mapfoldl(fun p2o_port_element/2, NextCapablePortNo,
                           get_p2o_links_ports(LinkConfig, SwitchConfig)),
        lists:flatten(OpticalCapablePorts ++ PacketCapablePorts)
    catch
        error:{duplicate_port, {SwitchId, LogicalPortNo}} ->
            DpidsToNumber = get_dpids2number(SwitchConfig),
            {Dpid, SwitchId} = lists:keyfind(SwitchId, 2, DpidsToNumber),
            [SwitchEntry] = [Entry ||
                                Entry <- SwitchConfig,
                                Dpid =:= proplists:get_value(<<"nodeDpid">>, Entry)],
            SwitchName = proplists:get_value(<<"name">>, SwitchEntry),
            io:format(
              standard_error,
              "ERROR: Port number ~b used more than once for switch '~s' (~s)~n",
              [LogicalPortNo, SwitchName, Dpid]),
            erlang:halt(1)
    end.

generate_switch_element(SwitchDpid, OpticalLinks, OpticalLinkPorts,
                        ControllerIP, Port, DpidsToNumber) ->
    Ports = get_switch_ports(proplists:get_value(SwitchDpid, DpidsToNumber),
                                                 OpticalLinks, OpticalLinkPorts),
    {switch, proplists:get_value(SwitchDpid, DpidsToNumber),
     [{backend,linc_us4_oe},
      {datapath_id, binary_to_list(SwitchDpid)},
      {controllers,[{"Switch0-Controller", ControllerIP, list_to_integer(Port), tcp}]},
      {controllers_listener,disabled},
      {queues_status,disabled},
      {ports, lists:map(fun port_queue_element/1, Ports)}]}.

port_queue_element({_SwitchId, LogicalPortNo} = LP) ->
    CapablePortNo = get_mapping_for_capable_port(LP),
    {port, CapablePortNo, [{queues, []}, {port_no, LogicalPortNo}]}.

generate_linc_element(SwitchConfig, LinkConfig, ControllerIP, Port) ->
    {linc,
     [{of_config, disabled},
      {software_desc, <<"LINC-OE OpenFlow Software Switch 1.1">>},
      {capable_switch_ports,  get_capable_switch_ports(LinkConfig,
                                                       SwitchConfig)},
      {capable_switch_queues, []},
      {optical_links, get_optical_link_pairs(LinkConfig, SwitchConfig)},
      {logical_switches, get_logical_switches(SwitchConfig, LinkConfig,
                                              ControllerIP, Port)}]}.

generator_test() ->
  file:copy("sys.config","sys.config."++integer_to_list(
            calendar:datetime_to_gregorian_seconds(calendar:now_to_datetime(now()))
        )),
  io:format("",[]),
  ok = main([os:getenv("PWD")++"/json_example.json",
             os:getenv("PWD")++"/sys.config.template",
             "localhost",
             "4343"]),
  Expect = {ok,[[{linc,
     [{of_config,disabled},
      {software_desc,<<"LINC-OE OpenFlow Software Switch 1.1">>},
      {capable_switch_ports,
          [{port,1,[{interface,"dummy"},{type,optical}]},
           {port,2,[{interface,"dummy"},{type,optical}]},
           {port,3,[{interface,"tap3"}]}]},
      {capable_switch_queues,[]},
      {optical_links,[{{1,20},{2,21}}]},
      {logical_switches,
          [{switch,1,
               [{backend,linc_us4_oe},
                {datapath_id,"00:00:ff:ff:ff:ff:ff:02"},
                {controllers,[{"Switch0-Controller","localhost",4343,tcp}]},
                {controllers_listener,disabled},
                {queues_status,disabled},
                {ports,[{port,1,[{queues,[]}, {port_no, 20}]},
                        {port,3,[{queues,[]}, {port_no, 10}]}]
                }]},
           {switch,2,
               [{backend,linc_us4_oe},
                {datapath_id,"00:00:ff:ff:ff:ff:ff:03"},
                {controllers,[{"Switch0-Controller","localhost",4343,tcp}]},
                {controllers_listener,disabled},
                {queues_status,disabled},
                {ports,[{port,2,[{queues,[]}, {port_no, 21}]}]}
               ]}]}]},
 {epcap,[{verbose,false},{stats_interval,10}]},
 {enetconf,
     [{capabilities,
          [{base,{1,0}},
           {base,{1,1}},
           {startup,{1,0}},
           {'writable-running',{1,0}}]},
      {callback_module,linc_ofconfig},
      {sshd_ip,any},
      {sshd_port,1830},
      {sshd_user_passwords,[{"linc","linc"}]}]},
 {lager,
     [{handlers,
          [{lager_console_backend,info},
           {lager_file_backend,
               [{"log/error.log",error,10485760,"$D0",5},
                {"log/console.log",info,10485760,"$D0",5}]}]}]},
 {sasl,
     [{sasl_error_logger,{file,"log/sasl-error.log"}},
      {errlog_type,error},
      {error_logger_mf_dir,"log/sasl"},
      {error_logger_mf_maxbytes,10485760},
      {error_logger_mf_maxfiles,5}]},
 {sync,[{excluded_modules,[procket]}]}]]},

      {ok,[Res]} = file:consult("sys.config"),

      %% io:format("optical_links:~p\n",[proplists:get_value(optical_links,proplists:get_value(linc,Res))]),


      ?assertEqual(Expect,{ok,[Res]}).


