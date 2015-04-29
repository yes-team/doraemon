-module(doraemon_timer).
-export([start_link/0, start/0, stop/0, init/0, now/0]).

start_link()->
    Pid = spawn_link(?MODULE, init,[]),
    {ok, Pid}.

start()->
    Pid = spawn(?MODULE, init,[]),
    {ok, Pid}.

stop()->
    case erlang:whereis(?MODULE) of
        undefined -> {error, notfound};
        Pid -> Pid ! stop
    end.

init()->
    ets:new(?MODULE, [set,protected,named_table]),
    register(?MODULE, self()),
    loop().

loop()->
    {M,S,_} = erlang:now(),
    N = M*1000*1000 + S,
    ets:insert(?MODULE, {now, N}),
    doraemon_server:timer_second(N),
    receive 
        stop -> ok
    after timer:seconds(1) ->
        loop()
    end.
    
now()->
    try
        [{now,N}] = ets:lookup(?MODULE, now),
        N
    catch _:_->0
    end.
