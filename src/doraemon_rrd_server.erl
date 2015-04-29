-module(doraemon_rrd_server).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type, N), {{I, N}, {I, start_link, [N]}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	Count = erlang:system_info(schedulers),
	L = [?CHILD(doraemon_rrd, worker, N) || N <- lists:seq(1, Count)],
    {ok, { {one_for_one, 5, 10}, L} }.


