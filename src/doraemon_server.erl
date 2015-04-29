-module(doraemon_server).
-behaviour(gen_server).
-include("defined.hrl").
-define(SERVER, ?MODULE).
-record(state, {count=0, count_last=0, mcount=0, mcount_last=0, line=0}).


%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, sync/0, sync/1, counter/0, count/0, timer_second/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3 , time_serialize_distinct/0 , time_bucket_cache/0 ]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init([]) ->
    doraemon_divide:init()
    %doraemon_global:store(running, true)
    %,doraemon_bucket:db(distinct)
    %,doraemon_bucket:db(bucket)
    %,doraemon_bucket:filter()
    ,ets:new(doraemon_rrd, [set, public, named_table])
    ,ets:new(doraemon_bucket_cache, [public, set, named_table])
    ,ets:new(doraemon_bucket_cache_index, [public, ordered_set, named_table])
    %,spawn( ?MODULE , time_serialize_distinct , [] )
    %,spawn( ?MODULE , time_bucket_cache , [] )
    %,CacheWritePid = spawn( doraemon_bucket, cache_write , [] )
    %,doraemon_global:store( doraemon_bucket_cache_write , CacheWritePid )
    %ets:new(doraemon_global , [public, named_table])
    ,{ok, #state{}}.

time_serialize_distinct() ->
    receive 
        _ -> ok
    after
        1000 -> ok
    end
    , doraemon_distinct:seriazlize()
    ,time_serialize_distinct().


time_bucket_cache() ->
    receive 
        _ -> ok
    after
        60000 -> ok
    end
    ,gc_bucket_cache()
    ,time_bucket_cache().

gc_bucket_cache() ->
    gc_bucket_cache( ets:first( doraemon_bucket_cache_index ) ,doraemon_timer:now() div 60 ).

gc_bucket_cache( Pk = {PreTime , PreKey} , Now ) when Now > PreTime ->
    CurKey = ets:next( doraemon_bucket_cache_index , Pk )
    ,ets:delete( doraemon_bucket_cache_index , Pk )
    ,case { ets:lookup( doraemon_bucket_cache_index , { PreTime+1 , PreKey} ) , ets:lookup( doraemon_bucket_cache_index , { PreTime+2 ,PreKey } ) } of
        { [] , [] }  -> 
            ets:delete( doraemon_bucket_cache , PreKey )
        ;_ -> ok
    end
    ,gc_bucket_cache( CurKey , Now )
;gc_bucket_cache( _ , _ ) ->ok.

handle_call(count, _From, S) ->
    {reply, {S#state.count_last, S#state.mcount}, S};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(counter, S) ->
    {noreply, S#state{count=S#state.count+1, mcount=S#state.mcount+1}};

handle_cast({timer_second, Now}, S) ->
    S2 = case Now - S#state.line of
        N when N > 60 -> S#state{mcount_last=S#state.mcount, mcount=0};
        _ -> S
    end,
    {noreply, S#state{count_last=S#state.count, count=0}};

handle_cast(_Cast, State) ->
    io:format("doraemon_server(cast): ~p\n", [_Cast]),
    {noreply, State}.

handle_info(_Info, State) ->
    io:format("doraemon_server(info): ~p\n", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    doraemon_distinct:seriazlize()
    ,io:format( "doraemon server terminated\n\n", [] )
    ,ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

sync()->
    ets:foldl(fun(A, _)->
        erlang:display(A)
    end, [], doraemon_worker),
    gen_server:abcast(?MODULE, {sync, node()}).
sync(N)->
    gen_server:cast({?MODULE, N}, {sync, node()}).

counter()->
    gen_server:cast(?MODULE, counter).

count()->
    gen_server:call(?MODULE, count).

timer_second(Now)->
    gen_server:cast(?MODULE, {timer_second, Now}).
