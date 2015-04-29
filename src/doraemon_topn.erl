-module(doraemon_topn).
-export([start/1]).
-include("defined.hrl").
-define(Tab, doraemon_topn).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([update/1, update/6, list/1 , archives/1, archives/2, worker/1]). 
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {id, name, size=0, total=0, hours=0, interval_hours=1, 
        orderd, db, limit=240 }).

-compile(export_all).

-define(timeout , 10000).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start(Name) ->
    gen_server:start({global, {?MODULE, Name}}, ?MODULE, [Name], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

id(Hours, S)-> 
    <<"topn", 0:8, (S#state.name)/binary, 0:8, (Hours div S#state.interval_hours):32/big>>.

init([Name]) ->
    %Id = doraemon_bucket:db(Name)
    {ok, #state{name=Name, orderd=ordsets:new() }}.

handle_call(write_back, _From, #state{id=undefined} = S)-> {reply, ok, S };
handle_call(write_back, _From, S) ->
    write_back(S),
    Now = doraemon_timer:now(),
    case Now div (3600*S#state.interval_hours) of
        NewHours when NewHours =:= S#state.hours -> 
            {reply, ok, S};
        NewHours ->
            erase(),
            if 
                NewHours - S#state.hours >= S#state.interval_hours  ->           
                    {reply, ok, S#state{id=id(NewHours, S), orderd=ordsets:new() 
                    , hours=NewHours, total=0, size=0}  , ?timeout}              
                ;true ->                                                         
                    {reply, ok, S#state{id=id(NewHours, S), orderd=ordsets:new() 
                    , hours=NewHours, total=0, size=0} }                         
            end
    end;

handle_call(list, _From, S) ->
   {reply, data(S), S };

handle_call(_Request, _From, State) ->
    {reply, ok, State }.

% 从table中获取上次中断
handle_cast(C, #state{id=undefined} = S) ->
    Hours = doraemon_timer:now() div 3600,
    Id = id(Hours, S),
    S2 = case doraemon_bucket:fetch( Id, []) of
        {ok, Last} when is_list(Last) -> 
            E = binary_to_term(Last),
            O2 = lists:foldl(fun({K, V}, O1)->
                        put(K, {V, true}),
                        ordsets:add_element({V, K}, O1)
                    end, S#state.orderd, E#doraemon_topn.data),
            S#state{total=E#doraemon_topn.total, orderd=O2};
        _ -> S
    end,
    handle_cast(C, S2#state{id=Id, hours=Hours});

handle_cast(#topn_cmd{size=SizeDef} = C, #state{size=Size} = S) when SizeDef < Size ->
    case S#state.orderd of
        [{LastV, LastK}|T] ->
            put(LastK, {LastV, false}),
            handle_cast(C, S#state{size = S#state.size - 1, orderd=T});
        _-> handle_cast(C#topn_cmd{size=Size}, S)
    end;
handle_cast(C, S) when is_record(C, topn_cmd) ->
    {V2, S2} = case get(C#topn_cmd.item) of
        undefined -> {C#topn_cmd.value, S};
        {V, true} ->
            O1 = ordsets:del_element({V, C#topn_cmd.item}, S#state.orderd),
            {V + C#topn_cmd.value, S#state{size = S#state.size-1, orderd=O1}};
        {V, false} -> {V + C#topn_cmd.value, S}
    end,
    {InTop, S3} = is_in_top(C, S2, V2),
    S4 = if 
        InTop ->
            O2 = ordsets:add_element({V2, C#topn_cmd.item}, S3#state.orderd),
            S3#state{size = S3#state.size +1 , orderd = O2};
        true -> S3
    end,
    put(C#topn_cmd.item, {V2, InTop}),
    {noreply, S4#state{
            total=S4#state.total + C#topn_cmd.value, 
            limit = C#topn_cmd.limit,
            interval_hours = C#topn_cmd.interval_hours} };

handle_cast(_Msg, State) ->
    io:format("cast: ~p ~p\n", [_Msg, State]),
    {noreply, State }.


handle_info(timeout, State)  -> 
    {stop , normal , State};
handle_info(_Info, State) ->
    io:format("info: ~p\n", [_Info]),
    {noreply, State }.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%---------------------------------------------------------------

is_in_top(#topn_cmd{size=SizeDef} = C, #state{size=Size} = S, V) when SizeDef > Size-> {true, S};
is_in_top(C, #state{size=Size} = S, V) ->
    case S#state.orderd of
        [{LastV, LastK} | T] when V > LastV ->
            put(LastK, {LastV, false}),
            {true, S#state{size = S#state.size - 1, orderd=T}};
        [{LastV, LastK} | T] -> {false, S};
        _ -> {true, S#state{size=0}}
    end.

worker(Name)-> worker(Name, 3).
worker(Name, 0)-> global:whereis_name({?MODULE,Name});
worker(Name, N)->
    case global:whereis_name({?MODULE, Name}) of
        undefined ->
            doraemon_topn:start(Name),
            worker(Name, N-1);
        Pid -> Pid
    end.

data(S)->
    ordsets:fold(fun({V, K} , L)->
                [{K, V} | L]
        end, [], S#state.orderd).

update(Name, Item, V, H, Size, Limit)->
    update(#topn_cmd{name=Name, item=Item, value=V, interval_hours=H, size=Size, limit=Limit}).
update(T) when is_record(T, topn_cmd)->
    gen_server:cast(worker(T#topn_cmd.name), T).

list(Name) ->
    gen_server:call(worker(Name), list).

archives(Name, Len) when is_integer(Len)->
    ?dio(3),
    archives(Name, {1, Len});
archives(Name, {Start, Len})->
    ?dio({3, Start, Len}),
    STmp = 1,
    A = archives(Name),
	
    ?dio(A),
    lists:sublist(A, STmp, Len).
archives(Name)->
    ?dio({3,Name}),
    case global:whereis_name({?MODULE, Name}) of
        undefined -> ?dio(3),ok;
        Pid -> ?dio(3),gen_server:call(Pid, write_back)
    end,
    A = try
        doraemon_bucket:fold(fun({K, V}, L)->
            case binary:match(K, <<"topn", 0:8, Name/binary, 0:8>> ) of
                {0, _} -> 
                    case V of <<>> -> L ; _ -> [binary_to_term(V) | L] end;
                _ -> throw({iterator_closed, L})
            end
        end, [], [{first_key, <<"topn", 0:8, Name/binary, 0:72>>}])
        catch {iterator_closed, L}-> L end,
    ?dio(A),
    A.

write_back(S)->
    R = #doraemon_topn{
        id = S#state.id, 
        name = S#state.name,
        time = S#state.hours * 3600,
        interval_hours = S#state.interval_hours,
        total = S#state.total,
        data = data(S),
        limit = S#state.limit
    },
    doraemon_bucket:store( S#state.id, term_to_binary(R), [ {sync,false} ]).

