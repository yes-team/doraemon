-module(doraemon_webflow).  
-behaviour(cowboy_http_handler).  
-behaviour(cowboy_http_websocket_handler).  
-include_lib("cowboy/include/http.hrl").
-include("defined.hrl").

-export([init/3, handle/2, terminate/2]).  
-record(state, {channels}).

-export([  
    websocket_init/3, websocket_handle/3,  
    websocket_info/3, websocket_terminate/3  
]).

init({tcp, http}, Req, _Opts) ->
    case cowboy_http_req:header('Upgrade', Req) of
        {<<"websocket">>, _} ->
            {upgrade, protocol, cowboy_http_websocket};
        {_, R2} -> {ok, R2, #state{}}
    end.

bad_request(R, S)->
    {ok, R2} = cowboy_http_req:reply(404, [{<<"Content-Type">>, <<"text/html">>}], 
        "<h1>flow 404 Not found</h1><hr />", R),
    {ok, R2, S}.

handle(R, S) ->
    case cowboy_http_req:qs_val(<<"callback">>, R) of
        {undefined, R1} -> bad_request(R1, S);
        {Callback, R1} ->
            case cowboy_http_req:qs_val(<<"channel">>, R1) of
                {undefined, R2} -> bad_request(R2, S);
                {Ch, R2}->
                    case binary:split(Ch, <<",">>, [global]) of
                        [] ->  bad_request(R2, S);
                        L ->
                            doraemon_flow:link(),
                            lists:foreach(fun(Channel)->
                                doraemon_flow:join(Channel)
                                end, L),
                            {ok, R3} = cowboy_http_req:chunked_reply(200,
                                [{<<"Content-Type">>, <<"text/html">>}], R2),
                            inet:setopts(R1#http_req.socket, [{active, once}]),
                            Body =
                            <<"<html><header><title>live</title></header><body><h1>live api</h1>",0:1024,"</body>
                            <script>callback=", Callback/binary, ";callback({'type':'ping'});</script>">>,
                            cowboy_http_req:chunk(Body, R3),
                            flow_loop(R3),
                            {ok, R3, S}
                    end
            end
    end.

flow_loop(R)->
    receive
        {data, Data} ->
            cowboy_http_req:chunk([<<"<script>try{ callback(">>, Data,
                <<"); }catch(err){ if(console) if(console.info) console.info(err) }</script>">>], R),
            flow_loop(R);
        {tcp_closed, Sock} when Sock=:= R#http_req.socket ->
            ok;
        {tcp, Sock, _} when Sock=:= R#http_req.socket ->
            inet:setopts(Sock, [{active, once}]),
            flow_loop(R);
        _ -> 
            flow_loop(R)
    after timer:seconds(20) ->
            cowboy_http_req:chunk(<<"<script>callback({'type':'ping'});</script>">>, R),
        flow_loop(R)
    end.

terminate(_Req, _State) ->
    ok.

websocket_init(_Any, Req, []) ->
    Req2 = cowboy_http_req:compact(Req),
    doraemon_flow:link(),
    {ok, Req2, undefined, hibernate}.

websocket_handle({text, Json}, Req, State) -> 
    case mochijson2:decode(Json) of
        {struct, Msg} ->
            case proplists:lookup(<<"type">>, Msg) of
                { _ , <<"getrrd">>} ->
                    {_, { _ , Jdata} } = proplists:lookup(<<"data">> , Msg),


    Keys0 = parse_query_items(Jdata, []),
            {Type, Params} = case proplists:lookup(<<"type">>, Jdata) of
                {_, <<"collage">>} ->
                    {collage, proplists:delete(<<"step">>, Jdata)};
                _ -> {list, Jdata}
            end,
            {Start, End} = time_range(Params, 3600),
            {ok, L} = fetch_data(rrd, Keys0, Start, End, Params),
            Rs = render_data(rrd, Type, L, {Start, End}),

                    %{ok , Resdata , _} = doraemon_webapi:handle(#http_req{path=[<<"api">>, <<"data">>]}, S) ->

                    %io:format("aaa ~p\n" , [Rs]),


		    {reply,
			{text, [<< "{\"type\":\"data\", \"data\":">> ,
case proplists:lookup( <<"var">> , Jdata ) of
    { <<"var">>,Var } -> [ "var ", Var , "=" ,  Rs , <<";">> ] ;
    _ -> Rs
end

,
case proplists:lookup( <<"reqid">> , Jdata ) of
    { <<"reqid">>,Reqid } -> [ ",\"reqid\": ",  <<"\"">> ,Reqid ,<<"\"">> ] ;
    _ -> <<>>
end
,
<<"}" >> ]},  
			Req, State, hibernate
		    };
                _ ->
		    {reply,
			{text, << "{\"type\":\"error\", \"data\":\"bad action type\"}" >>},  
			Req, State, hibernate
		    }
            end;
        _ ->
            {reply,
                {text, << "{\"type\":\"error\", \"data\":\"bad action type\"}" >>},  
                Req, State, hibernate
            }
    end;


websocket_handle(_Any, Req, State) ->  
    {ok, Req, State}.  

websocket_info({data, Bin}, Req, State)->
    {reply, {text, Bin},  Req, State, hibernate };
    
websocket_info(_Info, Req, State) ->  
    {ok, Req, State, hibernate}.  
  
websocket_terminate(_Reason, _Req, _State) ->  
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




render_data(rrd, collage, L, {Begin0, End})->
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
Content;

render_data(rrd, list, L,   _)->
    Content = js_data(L),
Content.



fetch_data(rrd, Items, Start, End, Params)->
    Step = case proplists:lookup(<<"step">>, Params) of
        none -> 60;
        {_, StepBin} -> doraemon_var:int(StepBin, 60)
    end,
    {ok, lists:foldl(fun({Item, Label}, L)->
            [{Label, rpc:call( doraemon_divide_runtime:get_node(Item),doraemon_rrd,fetch ,[Item, Start, End, Step])} | L]
        end, [], Items)}.




time_range(Params, Length)->
    Now = doraemon_timer:now(),
    End = case proplists:lookup(<<"end">>, Params) of
        none -> Now;
        {_, Endbin} -> 
                  min(list_to_integer(binary_to_list( Endbin ) ), Now)
    end,
    Start = case proplists:lookup(<<"start">>, Params) of
        none -> End - Length;
        {_, StartBin} ->
                    min(list_to_integer(binary_to_list( StartBin )), End - 3600)
    end,
    {Start, End}.

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



join([], _)->[];
join([H | []], _)-> H;
join([H | T], Separator)-> join(T, Separator, [H]).
join([], _, L)-> lists:reverse(L);
join([H | T], Separator, L)->join(T, Separator, [ H | [Separator | L ]]).


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

