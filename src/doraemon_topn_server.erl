-module(doraemon_topn_server).
-behaviour(gen_server).
-include("defined.hrl").
-define(SERVER, ?MODULE).
-record(state, {db}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([local_topn_pids/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
    DB = doraemon_bucket:db(),
    doraemon_global:store(topn_db, DB),
    timer:send_after(timer:seconds(10), topn_write_back), 
    {ok, #state{db=DB}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast( { store,{Name, Item, V, H, Size, Limit} , AmqpStatus} , State) ->
    doraemon_topn:update( Name, Item, V, H, Size, Limit ),
    doraemon_queue_utils:ack_queue(AmqpStatus),
    {noreply , State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(topn_write_back, State) ->
    try
        lists:foreach(fun(P)->
                gen_server:call(P, write_back, 30000)
            end, local_topn_pids())
    catch _:_ -> ok end,
    timer:send_after(timer:seconds(10), topn_write_back), 
    {noreply, State};

handle_info(topn_gc, State) ->
    lists:foreach(fun(P)->
            gen_server:call(P, gc)
        end, local_topn_pids()),
    timer:send_after(timer:hours(1),  topn_gc),
    {noreply, State};

handle_info(_Info, State) ->
    io:format("doraemon_server(info): ~p\n", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

local_topn_pids()->
    Local = node(),
    lists:foldl(fun(N, L)->
            case N of
                {doraemon_topn, _} ->
                    case global:whereis_name(N) of
                        undefined -> L;
                        Pid ->
                            case node(Pid) of
                                Local -> [Pid | L];
                                _ -> L
                            end
                    end;
                _ -> L
            end
    end,[], global:registered_names()).

