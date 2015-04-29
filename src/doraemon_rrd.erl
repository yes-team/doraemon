-module(doraemon_rrd).
-behaviour(gen_server).
-include("defined.hrl").
%-record(state, {bucket}).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
-export([merge_v/5, fetch/4 ]).
-record(rrd, {name, interval, type, archives, number_type=int}).
-define(record_key(Name, X, N, Cell),
        <<"rrd",0, Name/binary, 0, X:16/big, N:16/big, Cell:16/big>>).
-define(info_key(Name), <<"rrdinfo",0,Name/binary>>).

-export([whereis_name/1, register_name/2, unregister_name/1]).

-record(state, {db_fp}).
-compile(export_all).

start_link(N) ->
    gen_server:start({via, ?MODULE, N}, ?MODULE, [N], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([N]) ->
%    bnow_listener:active_node(self()),
    {ok, #state{ db_fp = doraemon_bucket:db() }}.

whereis_name(Name)->
    case ets:lookup(?MODULE, Name) of
        [{_, Pid}|_] -> Pid;
        _ -> undefined
    end.

register_name(Name, Pid)->
    ets:insert(?MODULE, {Name, Pid}),
    yes.

unregister_name(Name)->
    ets:delete(?MODULE, Name).

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({store,{T,K,V,F,S,C}, AmqpStatus}, #state{ db_fp = Db } = State) ->
    update( Db, { T,K,V,F,S,C } ),
    doraemon_queue_utils:ack_queue(AmqpStatus),
    {noreply, State};
handle_cast(_Cast, State) ->
    io:format("~p(cast): ~p\n", [?MODULE, _Cast]),
    {noreply, State}.

handle_info(_Info, State) ->
    io:format("~p(info): ~p\n", [?MODULE, _Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


update( Db, { Start0, Name, Value, Type , Interval,Count } )->
    Time0 = doraemon_var:int(Start0),
    {_, R} = ensure_item( Name, Interval, Type),
    Now = doraemon_timer:now(),
    {Time, Diff} = case Now - Time0 of
            D when D < 0 -> {Now, 0};
            D -> {Time0, D}
    end,
    lists:foreach(fun({X, N})->
        if
            Diff > (X * N * R#rrd.interval) -> ok;
            true ->
                Step = Time div (X * R#rrd.interval),
                Cell = Step rem N,
                {V2, C2} = case doraemon_bucket:fetch( ?record_key(Name, X, N, Cell), [{fill_cache , true}]) of
                    {ok, <<Step:32/big, V0:64/big, C0:32>>} ->
                        merge_v(Value, Count, V0, C0, R#rrd.type);
                    _ -> {Value, 1}
                end,
		try
                doraemon_bucket:store( Db, ?record_key(Name, X, N, Cell), 
                        <<Step:32/big, (doraemon_var:int(V2)):64/big, C2:32/big>>, [{sync, false}])
		catch _:_Err->
			io:format("error: ~p:~p\n", [_Err, {?MODULE, ?FILE, Name, Step, V2, C2}])
		end
        end
    end, R#rrd.archives).

fetch(Name , Start0 , End ) ->
    fetch(Name , Start0 , End , 30).
fetch(Name, Start0, End, IntervalV) when is_binary( Name )->
    %bnow_bucket:apply(?MODULE,  {fetch, Name, Start0, End, IntervalV}, Name).
    try
        {ok, R} = read_info(Name),
%        Start = case IntervalV of
%                I when is_number(I) and (I > 1)->
%                    IntervalV * ( (Start0 + 28800 ) div IntervalV) - 28800 ;
%                _ -> Start0
%        end,
Start = Start0,
        {ok, {X, TotalCell}} = select_archive(R#rrd.archives, R#rrd.interval, doraemon_timer:now() - Start),
%%        io:format("[~p,~p], ~p, ~p, ~p\n", [?MODULE, ?LINE, X, TotalCell, R]),
        Interval = R#rrd.interval * ( IntervalV div R#rrd.interval),

        Now = doraemon_timer:now(),
        N = X * R#rrd.interval,


        EndStep = End div N,
        case ceil(Start / N) of
            StartStep when StartStep > EndStep -> {0, []};
            StartStep ->
                Read = case (EndStep rem TotalCell) - (StartStep rem TotalCell) of
                    D when D > 0 -> [{StartStep , StartStep rem TotalCell, EndStep rem TotalCell}];
                    D when D < 0 ->
                        [{ StartStep, StartStep rem TotalCell, TotalCell},
                         { StartStep + TotalCell - (StartStep rem TotalCell) , 0, EndStep rem TotalCell}];
                    0 ->
                        [{StartStep, StartStep rem TotalCell, StartStep rem TotalCell}]
                end,
                Lcur = pick_data( Name, X, TotalCell, Read),
                Lbase = [ {StepN, {0,0}} || StepN <- lists:seq(StartStep, EndStep)],
                Lrst = orddict:merge(fun(_, _, Vn)-> Vn end, Lbase, lists:reverse(Lcur)),
                process_interval(IntervalV, Lrst, R, X)
        end
    catch _:_-> {sum, []}
    end.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

ceil(X) ->
    T = erlang:trunc(X),
    case (X - T) of
        Neg when Neg < 0 -> T;
        Pos when Pos > 0 -> T + 1;
        _ -> T
    end.

%local({fetch, Name, Start0, End, IntervalV}, Bucket) when is_binary(Name)->

%local({update, Name, Time0 ,Value, Interval, Type}, Bucket)->
 
process_interval(Interval, L0, R, X)->
    Lrst = lists:foldl(fun({Step, V}, Ln)->
            [{Step * R#rrd.interval * X, V} | Ln]
        end, [], L0),
    if
        is_integer(Interval) 
        and (interval=/=R#rrd.interval)
        and (Interval > 0) ->
            if 
                R#rrd.interval =:= Interval -> {R#rrd.type, Lrst};
                true ->
                    {R#rrd.type,
                        lists:reverse(merge_x(Lrst, clear, Interval,
                                R#rrd.type, []))}
            end;
        true -> {R#rrd.type, Lrst}
    end.

pick_data( Name, X, N, Read)->
    lists:foldl(fun({Step, StartCell, EndCell}, L0)->
        try
            doraemon_bucket:fold( fun({K, Vbin}, L)->
                <<CurCell:16/big>> = binary:part(K, {byte_size(K)-2,2}),
                
                if 
                    CurCell > EndCell -> throw({iterator_closed, L});
                    true ->
                        <<Step2:32/big, V:64/big, C:32/big>> = Vbin,
                        case (CurCell - StartCell) - (Step2 - Step) of
                            0 -> [{Step2, {V, C}} | L];
                            _ -> L
                        end
                end
            end, L0, [{first_key, ?record_key(Name, X, N, StartCell)}])
        catch {iterator_closed, L1}-> L1 end
    end, [], Read).

merge_v(V1, C1, V2, C2, Type)->
    case Type of
        ?T_AVG ->
            case C1 + C2 of
                0 -> {0,0};
                C3 ->
                V3 = V1 div C3 + ( ( V2 * C2 ) div C3 ),
                {V3, C3}
            end;
        ?T_MIN -> {erlang:min(V1 , V2), 1};
        ?T_MAX -> {erlang:max(V1 , V2), 1};
        _ -> {V1 + V2, 1}
    end.

merge_x(TL, Last, I, Type, L) ->
    [{Time, {V, C}}|T] = lists:reverse(TL),
    merge_x([{Time, {V, C}}|T], Last, I, Type, L, Time + I).


merge_x([], clear, _I, _T, L, _ET)-> 
    %io:format("\n\n", []), 
    lists:reverse(L);
merge_x([], {LastTime, {LastV, LastCnt}}, I, _T, L, ET)-> 
    lists:reverse([{ET - I, {LastV,LastCnt}} | L]);
merge_x([{Time, {V, C}}|T], Last, I, Type, L, NowEndTime) ->
    {V2, C2} = case Last of
        clear -> {V, C};
        {_, {LastV, LastCnt}} ->
            merge_v(V, C, LastV, LastCnt, Type)
        end,
    if
        Time < NowEndTime ->
             %%io:format("aaa:~p:~p:~p\n ", [Time, NowEndTime, I]), 
             merge_x(T, {Time, {V2, C2}}, I, Type, L, NowEndTime);
        true ->
             %%io:format("b:~p:~p:~p\n ", [Time, NowEndTime, I]), 
            merge_x(T, clear, I, Type, [{NowEndTime - I, {V2, C2}} | L], NowEndTime+I)
        end.

%merge_x([], clear, _I, _T, L)-> 
%    %io:format("\n\n", []), 
%    L;
%merge_x([], {LastTime, {LastV, LastCnt}}, _I, _T, L)-> 
%    [{LastTime, {LastV,LastCnt}} | L];
%merge_x([{Time, {V, C}}|T], Last, I, Type, L)->
%    {V2, C2} = case Last of
%        clear -> {V, C};
%        {_, {LastV, LastCnt}} ->
%            merge_v(V, C, LastV, LastCnt, Type)
%        end,
%    case Time rem I of
%        0 -> 
%             io:format("~p:~p\n ", [Time, I]), 
%            merge_x(T, clear, I, Type, [{Time, {V2, C2}} | L]);
%        _ -> 
%             io:format("~p:~p\n ", [Time, I]), 
%    merge_x(T, {Time, {V2, C2}}, I, Type, L)
%    end.
%
select_archive([], _, _) -> {error, notfound};
select_archive([{X, N}|T], I, Diff) when X*I*N>=Diff-> {ok, {X, N}};
select_archive([_|T], I, Diff) -> select_archive(T, I, Diff).

%-------------------------------------------------------------------

   
read_info(Name)->
    case doraemon_bucket:fetch(?info_key(Name), [ {fill_cache,true} ]) of
        {ok, Bin} -> {ok, binary_to_term(Bin)};
        _ -> undefined
    end.

ensure_item( Name, Interval, Type)->
    case read_info( Name) of
        {ok, R} when is_record(R, rrd) -> 
        ?dio(?LINE),
        {found, R};
        _ ->
        ?dio(?LINE),
            N = 86400 div Interval,
            add_item( Name, Interval, Type, 
                [{1, N}, {10, N}, {60, N}, {360, N}])
    end.

add_item( Name, Interval, Type, Archives)->
        ?dio(?LINE),
    R = #rrd{name=Name, interval=Interval, type=Type,
                archives=Archives},
        ?dio(?LINE),
    doraemon_bucket:store(?info_key(Name), term_to_binary(R), [{sync,false}]),
        ?dio(?LINE),
    lists:foreach(fun({X, N})->
        doraemon_bucket:store(?record_key(Name, X, N, (N+1)), <<>>, [{sync,false}])
    end, Archives),
        ?dio(?LINE),
    {created, R}.

%find_step( BucketId, Name, X , StartTime ) ->
%    K = { read_rrd_info ,{ BucketId, Name } }
%    ,R = case get( K ) of
%        undefined -> 
%            case read_info( BucketId - 1 , Name ) of
%                {ok,Rr} -> 
%                     put(K , Rr)
%                    ,Rr
%                ;_-> undefined
%            end
%        ;R1 -> R1
%    end
%    ,if 
%       R =:= undefined -> undefined
%       ;true -> StartTime div (X * R#rrd.interval)
%     end.
%
