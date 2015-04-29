%%%-------------------------------------------------------------------
%%% @copyright 2013 ShopEx Network Technology Co, .Ltd
%%% @author liyouyou <liyouyou@shopex.cn>
%%% @doc
%%% doraemon_queue_utils.erl
%%% @end
%%% Created : 2013/08/09 07:04:41 liyouyou
%%% #Time-stamp: <syrett 2013-11-06 20:26:25>
%%%-------------------------------------------------------------------

-module(doraemon_queue_utils).

-export([listen_queue/1, close_mq_connection/2,send_message_to_queue/4,ack_queue/1]).

-include_lib("amqp_client/include/amqp_client.hrl"). 
-include("defined.hrl").

-compile(export_all).

get_request_mq_server() ->
    {ok, Request_mq_server} = application:get_env(doraemon, request_mq_server),
    Request_mq_server.

get_request_queue_list(_Rabbitmq_server) ->
    Prefetch_count = 10,
    {ok, Channels} = application:get_env(doraemon, request_channels),
    [{Channel, Prefetch_count} || Channel <- Channels].
get_request_mq_vhost() ->
    case application:get_env(doraemon, request_mq_vhost) of
        undefined ->
            "/";
        {ok, VHost} ->
            VHost
    end.

listen_queue(Options) ->
    {ok, Connection} = build_mq_connection(Options),
    {queue_name, QueueList} = lists:keyfind(queue_name, 1, Options),
    case QueueList of
        [] ->
            ok = amqp_connection:close(Connection),
            throw("no queues");
        _ ->
        {host, Host} = lists:keyfind(host, 1, Options),
        QueueChannel = lists:foldl(fun({QueueName,PrefetchCount}, Acc0) ->
                                           Channel = queue_connect(Connection, QueueName),
                                           amqp_channel:call(Channel, #'basic.qos'{prefetch_count = PrefetchCount}),
                                           [{QueueName, Channel, PrefetchCount}|Acc0]
                                   end, [], QueueList),
        {Host, Connection, QueueChannel}
    end.
                        
queue_connect(Conn, QueueName) ->
    {Ret, Channel} = amqp_connection:open_channel(Conn),
    case Ret of
        error ->
            ?dio(Ret),
            ok = amqp_connection:close(Conn),
            throw("open channel failed");
        ok ->
            ?dio(ok),
            Result = amqp_channel:call(Channel,
                                       #'queue.declare'{queue = list_to_binary(QueueName),
                                                        durable = true}),
            case Result of
                #'queue.declare_ok'{queue = _Q} -> ok;
                _ ->
                    ok = amqp_channel:close(Channel),
                    ok = amqp_connection:close(Conn),
                    throw("queue.declare failed")
            end,
            Channel
    end.
    
build_mq_connection(Options) ->
    io:format("[~p,~p], connect queue, options:~p\n", [?MODULE, ?LINE, Options]),
    NetWork = lists:foldl(fun({host, H}, Acc0) ->
                                  Acc0#amqp_params_network{host=H};
                             ({virtual_host, VH}, Acc0) ->
                                  Acc0#amqp_params_network{virtual_host=VH};
                             ({username, U}, Acc0) ->
                                  Acc0#amqp_params_network{username=U};
                             ({password, P}, Acc0) ->
                                  Acc0#amqp_params_network{password=P};
                             ({port, Port}, Acc0) ->
                                  Acc0#amqp_params_network{port=Port};
                             ({heartbeat, HT}, Acc0) ->
                                  Acc0#amqp_params_network{heartbeat=HT};
                             (_, Acc0) ->
                                  Acc0
                          end, #amqp_params_network{}, Options),
    io:format("[~p,~p], connect queue network:~p\n", [?MODULE, ?LINE, NetWork]),
    case amqp_connection:start(NetWork) of
        {ok, Connection} ->
            {ok, Connection};
        _Error ->
            io:format("[~p,~p]: connect error:~p\n", [?MODULE, ?LINE, _Error]),
            throw("connect error")
    end.


listen_queue(Hostname, Queue_name, Prefetch_count, VHost) ->
    ?dio(3),
    {Connection, Channel} = build_mq_connection(Hostname, Queue_name, VHost),
    ?dio(3),
    amqp_channel:call(Channel, #'basic.qos'{prefetch_count = Prefetch_count}),
    ?dio(3),
%%    Declare = #'exchange.declare'{exchange = <<"amqp.direct">>, type = <<"direct">>},
%%    #'exchange.declare_ok'{} = amqp_channel:call(Channel, Declare),
%%    A = amqp_channel:call(Channel, Declare),
%%    ?dio(A),
    #'basic.consume_ok'{consumer_tag = _Tag} =
        amqp_channel:subscribe(Channel, #'basic.consume'{queue = list_to_binary(Queue_name)}, self()),
    {Connection, Channel}.

build_mq_connection(HostName, QueueName, VHost) ->
    ?dio(HostName),
    {ok, Connection} = amqp_connection:start(#amqp_params_network{host = HostName, virtual_host= doraemon_var:bin(VHost), username= doraemon_var:bin(<<"guest">>), password = doraemon_var:bin(<<"iloveshopex">>)}),
    ?dio(Connection),
    {Ret, Channel} = amqp_connection:open_channel(Connection),
    case Ret of
        error ->
            ?dio(Ret),
            ok = amqp_connection:close(Connection),
            error(fail_build_connection);
        ok ->
            ?dio(ok),
            Result = amqp_channel:call(Channel,
                                       #'queue.declare'{queue = list_to_binary(QueueName),
                                                        durable = true}),
            ?dio(Result),
            case Result of
                #'queue.declare_ok'{queue = _Q} -> ok;
                _ ->
                    ok = amqp_channel:close(Channel),
                    ok = amqp_connection:close(Connection)
            end,
            {Connection, Channel}
    end.

close_mq_connection(Connection, Channel) ->
    ok = amqp_channel:close(Channel),
    ok = amqp_connection:close(Connection),
    ok.

send_message_to_queue(Channel, Queue_name, Exchange, Bin) ->
    ok = amqp_channel:cast(Channel,
                           #'basic.publish'{
                             exchange = doraemon_var:bin(Exchange),
                             routing_key = list_to_binary(Queue_name)},
                           #amqp_msg{payload = Bin}),
    ok.

ack_queue(MsgState) when is_record(MsgState, msg_state) ->
    ?dio(MsgState),
    A = amqp_channel:cast(MsgState#msg_state.mq_req_channel, #'basic.ack'{delivery_tag = MsgState#msg_state.queue_msg_tag}),
    ?dio(A).
    

test() ->
    {ok, Connection} = amqp_connection:start(#amqp_params_network{host = "192.168.15.206", virtual_host= doraemon_var:bin("/") ,username = <<"guest">> , password = <<"iloveshopex">> }).
