-module(doraemon_global).
-behaviour(gen_server).
-include("defined.hrl").
-define(SERVER, ?MODULE).
-record(state, {}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, store/2, fetch/1]).

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
    %ets:new(bnow_cache, [public, set, named_table]),
    ets:new(doraemon_global, [public, set, named_table]),
    %ets:new(bnow_worker, [set, public, named_table]),    
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    io:format("~p(info): ~p\n", [?MODULE, _Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

store(Key, Value)->
    ets:insert(doraemon_global, {Key, Value}).

fetch(Key)->
    case ets:lookup(doraemon_global, Key) of
        [{_, V}|_] -> V;
        [] -> undefined
    end.

