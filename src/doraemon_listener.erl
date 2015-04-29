%%%-------------------------------------------------------------------
%%% @author liyouyou <liyouyou@shopex.cn>
%%% @copyright (C) 2013, liyouyou
%%% @doc
%%%
%%% @end
%%% Created :  9 Aug 2013 by liyouyou <liyouyou@shopex.cn>
%%%-------------------------------------------------------------------
-module(doraemon_listener).

-behaviour(gen_server).

-include("defined.hrl").
-include_lib("amqp_client/include/amqp_client.hrl"). 

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([worker/2]).

-export([id/1]).

-record(state, {mq_server, queue_name, connection, listener_name, channel, prefetch_count }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link([Id, RrdQ]) ->
	io:format("[~p, ~p] ~p starting....\n", [?MODULE, ?LINE, Id]),
    gen_server:start_link({local, Id}, ?MODULE, [Id, RrdQ], []).    


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Id, RrdQ]) ->
    process_flag(trap_exit, true),
    {Host, Conn, [{QueueName, Channel, PrefetchCount}]} = doraemon_queue_utils:listen_queue(RrdQ),
    #'basic.consume_ok'{consumer_tag = _Tag} =
        amqp_channel:subscribe(Channel, #'basic.consume'{queue = list_to_binary(QueueName)}, self()),
    State = #state{mq_server = Host,
                   queue_name = QueueName,
                   connection = Conn,
                   listener_name = Id,
                   prefetch_count = PrefetchCount,
                   channel = Channel
                   },
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({#'basic.deliver'{delivery_tag = Queue_message_tag}, #amqp_msg{payload = BinData}}, State) ->
    ?dio(BinData),
    Msg_state = #msg_state{
                           queue_msg_tag = Queue_message_tag, 
                           mq_req_channel = State#state.channel,
                           listener_name = State#state.listener_name},
    spawn(?MODULE, worker, [Msg_state, BinData ]),
    {noreply, State};
handle_info(_Info, State) ->
    ?dio(_Info),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(Reason, S) ->
	doraemon_queue_utils:close_mq_connection(S#state.connection, S#state.channel),
    io:format("[~p,~p] ~p terminate for reason:~p\n", [?MODULE, ?LINE, self(), Reason]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

worker(Msg_state,  << 1, 0 ,Time:32/big, KeyLen:16/big , Key:KeyLen/binary , Val:64/big , T:8 , Step:16/big, Count:32/big>> = Rest ) -> 
    %doraemon_rrd:update( doraemon_divide_runtime:get_node( Rest ) ,{ if Time > 0 -> Time;true -> doraemon_timer:now() end,Key,Val,T,Step,Count }),
    Node = doraemon_divide_runtime:get_node( Key ),
%%    <<KenGen/big>> = Key,
    gen_server:cast( {doraemon_bucket , Node} , { rrd,store,{ if Time > 0 -> Time;true -> doraemon_timer:now() end,Key,Val,T,Step,Count } ,Msg_state } );
    %gen_server:cast(  { global ,{doraemon_rrd, Node, (KenGen rem KernelCount) +1 } } ,   ),
    %doraemon_queue_utils:ack_queue(Msg_state);
worker(Msg_state, <<2, 0, NameLen:16/big, Name:NameLen/binary, ItemLen:16/big, Item:ItemLen/binary, VLen:16/big, V:VLen/binary, HLen:16/big, H:HLen/binary, SizeLen:16/big, Size:SizeLen/binary, LimitLen:16/big, Limit:LimitLen/binary >> = Rest) ->
    Node = doraemon_divide_runtime:get_node( Name ),
    gen_server:cast(  {doraemon_topn_server,Node} , { store,{Name, Item, doraemon_var:int(V), doraemon_var:int(H), doraemon_var:int(Size), doraemon_var:int(Limit) } , Msg_state } );
    %doraemon_queue_utils:ack_queue(Msg_state);
worker(A, B) ->
    ?dio(other_msg),
    ?dio(A),
    ?dio(B).

id(Num) ->
    doraemon_var:atom("doraemon_listener_" ++ doraemon_var:list(Num)).
