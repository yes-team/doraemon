%%%-------------------------------------------------------------------
%%% @copyright 2013 ShopEx Network Technology Co, .Ltd
%%% @author liyouyou <liyouyou@shopex.cn>
%%% @doc
%%% doraemon_webapi.erl
%%% @end
%%% Created : 2013/07/18 01:09:13 liyouyou
%%% #Time-stamp: <liyouyou 2013-08-14 10:19:12>
%%%-------------------------------------------------------------------

-module(doraemon_webapi).
-behaviour(cowboy_http_handler).
-behaviour(cowboy_http_websocket_handler).
-include_lib("cowboy/include/http.hrl").
-include("defined.hrl").
-compile(export_all).
-export([init/3, handle/2, terminate/2]).

-export([
     websocket_init/3 , websocket_handle/3,
    websocket_info/3 , websocket_terminate/3,
    fetch_data/5
]).


-record(state, {}).

init({tcp, http}, Req, _Opts) ->
    case cowboy_http_req:header('Upgrade', Req) of
        {<<"websocket">>, _} ->
            {upgrade, protocol, cowboy_http_websocket};
        {_, R2} -> 
            {ok, R2, #state{}}
    end.

websocket_init(_Any, Req, []) ->
    Req2 = cowboy_http_req:compact(Req),
    io:format("request ~p\n", [self()]),
    doraemon_flow:link(),
    {ok, Req2, undefined, hibernate}.

websocket_handle(_Any, Req, State) ->
    {ok, Req, State}.

websocket_info({data, Bin}, Req, State) when is_binary(Bin)->
    {reply, {text, Bin},  Req, State, hibernate };

websocket_info(_Info, Req, State) ->
    {ok, Req, State, hibernate}.

websocket_terminate(_Reason, _Req, _State) ->
    ok.

handle(#http_req{path=[<<"api">>, <<"data">>]} = R, S) ->
    %% TODO 处理api data

    {P0, R1} = cowboy_http_req:qs_vals(R),
    Keys0 = parse_query_items(P0, []),
%    Rr = case doraemon_cert:valid( R1, Keys0 ) of
%        {true , Keys , R2} ->
            {Type, Params} = case proplists:lookup(<<"type">>, P0) of
                {_, <<"collage">>} ->
                    {collage, proplists:delete(<<"step">>, P0)};
                _ -> {list, P0}
            end,
            {Start, End} = time_range(Params, 3600),
            {ok, L} = fetch_data(rrd, Keys0, Start, End, Params),
            {ok, R3} = render_data(rrd, Type, L, Keys0, R1, {Start, End})
            ,R3
%        ;{false , Why , R2} ->
%            {ok, R3} = cowboy_http_req:reply(200, [], [Why], R2),
%            R3
%        ;_ ->
%            {ok, R2} = cowboy_http_req:reply(404, [], "Not exists api", R1),
%            R2
%    end
    ,{ok, R3, S};    

handle(#http_req{path=[<<"api">>, <<"topn">>]}=R, S) ->
    {Params, R1} = cowboy_http_req:qs_vals(R),
    Keys0 = parse_query_items(Params, []),
%%    Rr = case bnow_cert:valid( R1, Keys0 ) of
%%        {true , Keys , R2} ->
            {Start, End} = time_range(Params, 24*3600),
            {ok, L} = fetch_data(topn,Keys0, Start, End,Params),
            {ok, R3} = render_data(topn, L, Keys0, R1, {Start, End}),
            R3
%%        ;{false , Why , R2} ->
%%            {ok, R3} = cowboy_http_req:reply(200, [], [Why], R2),
%%            R3
%%        ;_ ->
%%            {ok, R2} = cowboy_http_req:reply(404, [], "Not exists api", R1),
%%            R2
%%    end
    ,{ok, R3, S};

handle(#http_req{path=[<<"api">>, <<"archive">>]}=R, S) ->
    {Params, R1} = cowboy_http_req:qs_vals(R),
    Keys0 = parse_query_items(Params, []),
    {Start, End} = time_range(Params, 24*3600),
    {ok, L} = fetch_data(archive,Keys0, Start, End,Params),
    {ok, R3} = render_data(archive, L, Keys0, R1, {Start, End}),
    {ok, R3, S};

handle(R, S) ->
    ?dio(R),
    {ok, R2} = cowboy_http_req:reply(404, [], "Not exists api", R),
    {ok, R2, S}.    

terminate(_Req, _State) ->
    ok.

parse_query_items([], L) -> lists:reverse(L);
parse_query_items([{<<"d[]">>, V} | T], L)->
    parse_query_items(T, [{V, V} | L]);
parse_query_items([{<<"d[", N/binary>>, V} | T], L)->
    case binary:last(N) of
        $] -> parse_query_items(T, [{V, binary:part(N, 0, byte_size(N)-1)} | L]);
        _ -> parse_query_items(T, L)
    end;
parse_query_items([{<<"d">>, V} | T], L)->
    parse_query_items(T, [{V, V} | L]);
parse_query_items([{_,_} | T], L)-> parse_query_items(T, L).

fetch_data(rrd, Items, Start, End, Params)->
    Step = case proplists:lookup(<<"step">>, Params) of
        none -> 60;
        {_, StepBin} -> doraemon_var:int(StepBin, 60)
    end,
    {ok, lists:foldl(fun({Item, Label}, L)->
            [{Label, rpc:call( doraemon_divide_runtime:get_node(Item),doraemon_rrd,fetch ,[Item, Start, End, Step])} | L]
        end, [], Items)};

fetch_data(topn, Items, Start, End, Params ) ->
    Size = case proplists:lookup(<<"size">>, Params) of
        none -> 10;
        {_, Sizebin} -> doraemon_var:int(Sizebin, 10)
    end,
    {ok, lists:foldl(fun({Item, Label}, L)->
            [{Label, fetch_topn_data( Item,Size,Start,End )} | L]
        end, [], Items)};
fetch_data(archive, Items, Start, End, Params ) ->
    Size = case proplists:lookup(<<"size">>, Params) of
        none -> 10;
        {_, Sizebin} -> doraemon_var:int(Sizebin, 10)
    end,
    Len = case proplists:lookup(<<"len">>, Params) of
        none -> 1;
        {_, Lenbin} -> doraemon_var:int(Lenbin, 10)
    end,
    {ok, lists:foldl(fun({Item, Label}, L)->
            [{Label, doraemon_topn:archives( Item,Len )} | L]
        end, [], Items)}.


fetch_topn_data( Item , Size , Start , End ) ->
    S1 = Start div 3600
      %  ,E1 = End div 3600
        ,E1 = doraemon_timer:now() div 3600
        ,S = S1 * 3600
        ,E = E1 * 3600
        ,Istart = (Start - S) + 1
        ,Ilen = max(E1 - S1,1)
        ,PItemPrepared = ets:new( item_prepared ,[set , private] )
        ,PItemOrder = ets:new( item_order , [ordered_set,private] )
        ,A = rpc:call( doraemon_divide_runtime:get_node(Item) , doraemon_topn , archives ,[ Item , { Istart , Ilen } ] )
        %,io:format("~p,~p, ~p, ~p\n", [PItemPrepared,PItemOrder, Start, End])
        ,merge_topn( A , PItemPrepared ,PItemOrder , Start , End )
        ,Ts = fetch_order_topn(  PItemOrder , Size , undefined , [] )
        ,ets:delete( PItemPrepared )
        ,ets:delete( PItemOrder )
        ,{ Ts , S , E + 3599 }.

merge_topn( [] , P , O,_S,_E ) ->
    ?dio(2),
    ets:foldl( fun({K,V},_) ->
        ets:insert( O, {{V,K},K} )
    end , [] , P )
;merge_topn( [T|Ts],P,O,S,E ) ->
%% io:format(">> ~p, ~p\n", [T#bnow_topn.time , S]),
    ?dio(2),
    if
        T#doraemon_topn.time >= S , T#doraemon_topn.time =< E ->
            lists:foreach( fun({K,V}) ->
                V1 = case ets:lookup( P , K ) of
                    [] -> V
                    ;[{_,Vo}] -> Vo + V
                end
                ,ets:insert( P , { K,V1 } )
            end ,  T#doraemon_topn.data )
        ;true -> ok
    end
    ,merge_topn( Ts , P , O, S,E ).

fetch_order_topn( _O, 0,_K,R ) -> R
;fetch_order_topn( _O , _ , '$end_of_table' , R ) -> R
;fetch_order_topn( O , L , undefined , R ) ->
    case ets:last(O) of
        '$end_of_table' -> R;
        K1 ->
            {V, K} = K1,
            fetch_order_topn( O, L - 1 , K1 , [{K,V}|R] )
    end
;fetch_order_topn( O , L,Kp ,R) ->
    case ets:prev(O, Kp) of
        '$end_of_table' -> R;
        K1 ->
            {V, K} = K1,
            fetch_order_topn( O, L-1 , K1 , [{K,V}|R] )
    end.

render_data(rrd, collage, L,  _Items, R, {Begin0, End})->
    Content = ["[", join(lists:reverse(lists:map(fun({K, {Type, Vl}})->
                Begin = case Vl of 
                    [] -> Begin0;
                    _ -> case lists:last(Vl) of
                        {T1, _} -> T1;
                        _ -> Begin0
                    end
                end,
                {V, _} = lists:foldl(fun({_, {Vi,Vc}}, {Ri,Rc})->
                        merge_v(Vi, Vc, Ri, Rc, Type)
                    end,{0,0}, Vl),
                [<<"\n {\"name\":\"">>, K, <<"\", \"value\":">>
                    , doraemon_var:bin(V), <<", \"func\":\"">>,
                    doraemon_var:bin(Type) , <<"\", \"start\":">>,
                    doraemon_var:bin(Begin),
                    <<", \"end\":">>,
                    doraemon_var:bin(End),
                    <<"}">> ]
        end, L)), ","), "]"],
    output_json(R, Content);

render_data(rrd, list, L,  _Items, R, _)->
    Content = js_data(L),
    output_json(R, Content).

render_data(topn, L,  _Items, R, _)->
    Content = js_data(topn,L),
    output_json(R, Content);

render_data(archive, L,  _Items, R, _)->
    Content = js_data_archive(L),
    output_json(R, Content).

merge_v(V1, C1, V2, C2, Type)->
    case Type of
        ?T_AVG ->
            case C1 + C2 of
                0 -> {0,0};
                C3 ->
                V3 = V1 + ( ( V2 - V1 ) div C3 ),
                {V3, C3}
            end;
        ?T_MIN -> {erlang:min(V1 , V2), 1};
        ?T_MAX -> {erlang:max(V1 , V2), 1};
        _ -> {V1 + V2, 1}
    end.
time_range(Params, Length)->
    Now = doraemon_timer:now(),
    End = case proplists:lookup(<<"end">>, Params) of
        none -> Now;
        {_, Endbin} -> 
                  %min(list_to_integer(binary_to_list( Endbin ) ), Now)
                  list_to_integer(binary_to_list( Endbin ) )
    end,
    Start = case proplists:lookup(<<"start">>, Params) of
        none -> End - Length;
        {_, StartBin} ->
                    min(list_to_integer(binary_to_list( StartBin )), End - 3600)
    end,
    {Start, End}.

output_json(R, Content)->
    case cowboy_http_req:qs_val(<<"var">>, R) of
        {undefined, R1} ->
            cowboy_http_req:reply(200, [{<<"Content-Type">>, <<"text/javascript; charset=utf-8">>}], Content, R1);
        {Var, R1}->
            cowboy_http_req:reply(200, [{<<"Content-Type">>, <<"text/javascript; charset=utf-8">>}], ["var ",Var,"=",Content,";"], R1)

    end.

js_data_archive([{ _ , Items}|_]) ->
    Fun = fun(Item , Acc) ->
            Data = lists:foldl( fun( {K,V } , Acc) -> [ binary_to_list(iolist_to_binary( ["[ \"",doraemon_var:list(K),"\" , \"",doraemon_var:list(V),"\" ]" ] ))| Acc ] end, [] , Item#doraemon_topn.data ),
            Lst = string:join( lists:reverse(Data) , "," ),
            [["{ ",
                %"\"id\" : \"" , Item#doraemon_topn.id , "\" ,",
                "\"name\" : \"" , Item#doraemon_topn.name , "\" , ",
                "\"time\" : \"", doraemon_var:list( Item#doraemon_topn.time ) , "\" ," ,
                "\"interval_hours\" :\"" , doraemon_var:list( Item#doraemon_topn.interval_hours ) , "\" ,",
                "\"total\" : \"" , doraemon_var:list( Item#doraemon_topn.total ) , "\" ,",
                "\"data\" : \n[" , Lst , " ],\n",
                "\"limit\" : \"" , doraemon_var:list( Item#doraemon_topn.limit ) , "\""
            "}"] | Acc]
    end,
    [ "[" , string:join(  lists:foldl( Fun , [] , Items )  ,","), "]"].
    

js_data(Items)->
    js_data_item(Items, [<<"]">>]).

js_data_item([{Label, {_, Data}} | T], L)->
    DataList = case lists:foldl(fun({Time, {V, _}}, L0) ->
            [<<",\n">> | [ "     [", doraemon_var:list(Time), "000,",
            doraemon_var:list(V),
            "]" | L0]]
            end, [], Data) of
                [] -> [];
                [_| DataList0] -> DataList0
        end,
    L2 = [
        <<"\n {\"name\":\"">>, Label, <<"\",\n  \"data\": [\n">>,
        DataList,
        <<"]}\n">>
    | L],

    case T of
        [] -> [<<"[">> | L2];
        _ -> js_data_item(T, [<<",">> | L2])
    end;
js_data_item([], L)-> <<"[]">>.

js_data(topn,Items)->
    js_data_item(topn,Items, [<<"]">>]).

js_data_item(topn,[{Label, { Data , Start, End}} | T], L)->
    DataTmp = lists:foldl(fun({Name, Value}, L0) ->
                                  [<<",\n">> | [ "     {\"name\":\"", doraemon_var:list(Name), "\",",
                                                 "\"value\":",doraemon_var:list(Value),
                                                 "}" | L0]]
                          end, [], Data),
    DataList = case DataTmp of
                   [] -> [];
                   [_| DataList0] -> DataList0
               end,
    L2 = [
        <<"\n  {\"name\":\"">>, Label, <<"\",\n   \"time\":{\n    \"start\":">>
        ,doraemon_var:list(Start),<<",\n    \"end\":">>
        ,doraemon_var:list(End),<<"\n   },\n">>, <<"   \"data\": [\n">>,
        DataList,
        <<"]}\n">>
    | L],
    case T of
        [] -> [<<"[">> | L2];
        _ -> js_data_item(topn,T, [<<",">> | L2])
    end;
js_data_item(topn,[], L)-> 
    <<"[]">>.



join([], _)->[];
join([H | []], _)-> H;
join([H | T], Separator)-> join(T, Separator, [H]).
join([], _, L)-> lists:reverse(L);
join([H | T], Separator, L)->join(T, Separator, [ H | [Separator | L ]]).
