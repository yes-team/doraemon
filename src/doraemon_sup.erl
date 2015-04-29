
-module(doraemon_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-export([add_listener/1,stop_listener/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(CHILD_ARG(Id, Module, Args, Type),
        {Id, {Module, start_link, [Args]}, permanent, 50000, Type, [Module]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    S = [
         ?CHILD(doraemon_global, worker),
         ?CHILD(doraemon_timer, worker),
         ?CHILD(doraemon_server, worker),
         ?CHILD(doraemon_httpd, worker),
         ?CHILD(doraemon_bucket, worker),
         ?CHILD(doraemon_topn_server, worker),
         ?CHILD(doraemon_flow, worker),
         ?CHILD(doraemon_rrd_server, supervisor)] ++
         start_listener(),
    {ok, { {one_for_one, 5, 10}, S} }.


start_listener() ->
    RrdQ = doraemon_var:get_app_env(doraemon, rrd_queue, []),
    {connection_num, Num} = lists:keyfind(connection_num, 1, RrdQ),
    lists:foldl(fun(N, Acc0) ->
                        Id = doraemon_listener:id(N),
                        [?CHILD_ARG(Id, doraemon_listener, [Id, RrdQ], worker) | Acc0]
                end, [], lists:seq(1, Num)).
    

add_listener(Num) ->
    Id = doraemon_listener:id(Num),
    case erlang:whereis(Id) of
        undefined ->
            RrdQ = doraemon_var:get_app_env(doraemon, rrd_queue, []),
            ChildSpec = ?CHILD_ARG(Id, doraemon_listener, [Id, RrdQ], worker),
            supervisor:start_child(?MODULE, ChildSpec);
        _ ->
            io:format("sorry, pid:~p already exists\n", [Id]),
            ok
    end.

stop_listener(Num) ->
	Id = doraemon_listener:id(Num),
	supervisor:terminate_child(?MODULE, Id),
	supervisor:delete_child(?MODULE, Id).
